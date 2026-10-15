from pathlib import Path
import json
R=Path('/home/user/hanouti/data'); m=json.loads((R/'tests/fixtures/routines-manifest.json').read_text()); files={}
def fn(file,name,args,types,returns,body,declare='',public=False):
 sig=f'{name}({", ".join(types)})';m.append({'name':name,'signature':sig,'file':file,'exposed':public})
 files.setdefault(file,[]).append(f'CREATE FUNCTION {name}({args})\nRETURNS {returns}\nLANGUAGE plpgsql VOLATILE SECURITY DEFINER\nSET search_path = pg_catalog, pg_temp\nAS $fn$\n'+('DECLARE\n'+declare+'\n' if declare else '')+'BEGIN\n'+body.strip()+'\nEND;\n$fn$;\n'+f'REVOKE ALL ON FUNCTION {sig} FROM PUBLIC;\n')
G='010_row_guards.sql';L='011_order_edit_routines.sql'
fn(G,'auth._database_admin','p_table oid',['oid'],'boolean',"""
  -- session_user remains the authenticated database login inside SECURITY DEFINER calls.
  RETURN EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=p_table AND pg_has_role(session_user,c.relowner,'USAGE'))
    OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname='hanouti_data_admin' AND pg_has_role(session_user,r.oid,'MEMBER'));
""")
fn(G,'auth._row_metadata_guard','',[],'trigger',"""
  IF TG_OP='DELETE' THEN
    IF OLD.frozen THEN RAISE EXCEPTION 'Frozen row is read-only; a database administrator must unfreeze it first' USING ERRCODE='55000'; END IF;
    RETURN OLD;
  END IF;
  IF NEW.frozen IS NULL THEN RAISE EXCEPTION 'frozen cannot be null' USING ERRCODE='23502'; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.frozen AND NOT auth._database_admin(TG_RELID) THEN RAISE EXCEPTION 'Only a database administrator may freeze rows' USING ERRCODE='42501'; END IF;
    NEW.updated_at:=clock_timestamp();
    v_changed:=NEW.frozen;
  ELSE
    v_changed:=NEW.frozen IS DISTINCT FROM OLD.frozen;
    IF v_changed THEN
      IF NOT auth._database_admin(TG_RELID) THEN RAISE EXCEPTION 'Only a database administrator may change frozen' USING ERRCODE='42501'; END IF;
      IF (to_jsonb(NEW)-ARRAY['frozen','updated_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['frozen','updated_at']) THEN
        RAISE EXCEPTION 'Freeze or unfreeze separately from other row changes' USING ERRCODE='22023';
      END IF;
    ELSIF OLD.frozen THEN
      RAISE EXCEPTION 'Frozen row is read-only; unfreeze it first' USING ERRCODE='55000';
    END IF;
    -- Heartbeats/lock transitions are not document content edits and do not invalidate its save timestamp.
    IF TG_TABLE_SCHEMA='erp' AND TG_TABLE_NAME IN ('sales_orders','purchase_orders') AND NOT v_changed
      AND (to_jsonb(NEW)-ARRAY['locked_by','locked_at','lock_version','updated_at'])=(to_jsonb(OLD)-ARRAY['locked_by','locked_at','lock_version','updated_at'])
      AND (to_jsonb(NEW)->'locked_by',to_jsonb(NEW)->'locked_at',to_jsonb(NEW)->'lock_version')
        IS DISTINCT FROM (to_jsonb(OLD)->'locked_by',to_jsonb(OLD)->'locked_at',to_jsonb(OLD)->'lock_version') THEN
      NEW.updated_at:=OLD.updated_at;
    ELSE NEW.updated_at:=greatest(clock_timestamp(),OLD.updated_at+interval '1 microsecond'); END IF;
  END IF;
  IF v_changed THEN
    SELECT jsonb_object_agg(a.attname,to_jsonb(NEW)->a.attname ORDER BY a.attnum) INTO v_key
      FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
      WHERE i.indrelid=TG_RELID AND i.indisprimary;
    INSERT INTO app.audit_events(source_schema,action,entity_type,entity_id,metadata,occurred_at)
      VALUES(TG_TABLE_SCHEMA,CASE WHEN NEW.frozen THEN 'row.freeze' ELSE 'row.unfreeze' END,TG_TABLE_NAME,
        v_key::text,jsonb_build_object('database_login',session_user,'frozen',NEW.frozen),clock_timestamp());
  END IF;
  RETURN NEW;
""",'v_changed boolean := false; v_key jsonb;')
fn(G,'erp._set_edit_context','p_actor uuid, p_kind text, p_id uuid, p_version bigint, p_action text, p_reason text',['uuid','text','uuid','bigint','text','text'],'jsonb',"""
  v_old:=jsonb_build_object('actor',current_setting('hanouti.actor_id',true),'kind',current_setting('hanouti.order_kind',true),
    'id',current_setting('hanouti.order_id',true),'version',current_setting('hanouti.lock_version',true),
    'action',current_setting('hanouti.lock_action',true),'reason',current_setting('hanouti.change_reason',true));
  PERFORM set_config('hanouti.actor_id',coalesce(p_actor::text,''),true);
  PERFORM set_config('hanouti.order_kind',coalesce(p_kind,''),true);
  PERFORM set_config('hanouti.order_id',coalesce(p_id::text,''),true);
  PERFORM set_config('hanouti.lock_version',coalesce(p_version::text,''),true);
  PERFORM set_config('hanouti.lock_action',coalesce(p_action,''),true);
  PERFORM set_config('hanouti.change_reason',coalesce(p_reason,''),true);
  RETURN v_old;
""",'v_old jsonb;')
fn(G,'erp._restore_edit_context','p_previous jsonb',['jsonb'],'void',"""
  PERFORM set_config('hanouti.actor_id',coalesce(p_previous->>'actor',''),true);
  PERFORM set_config('hanouti.order_kind',coalesce(p_previous->>'kind',''),true);
  PERFORM set_config('hanouti.order_id',coalesce(p_previous->>'id',''),true);
  PERFORM set_config('hanouti.lock_version',coalesce(p_previous->>'version',''),true);
  PERFORM set_config('hanouti.lock_action',coalesce(p_previous->>'action',''),true);
  PERFORM set_config('hanouti.change_reason',coalesce(p_previous->>'reason',''),true);
""")
fn(G,'erp._context_actor','p_kind text, p_id uuid',['text','uuid'],'uuid',"""
  IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'Order writes require READ COMMITTED' USING ERRCODE='25001'; END IF;
  BEGIN
    v_actor:=nullif(current_setting('hanouti.actor_id',true),'')::uuid;
    IF nullif(current_setting('hanouti.order_kind',true),'') IS DISTINCT FROM p_kind
      OR nullif(current_setting('hanouti.order_id',true),'')::uuid IS DISTINCT FROM p_id THEN
      RAISE EXCEPTION 'Authenticated order context required' USING ERRCODE='42501';
    END IF;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Invalid authenticated order context' USING ERRCODE='42501'; END;
  PERFORM auth._require_active_actor(v_actor);
  RETURN v_actor;
""",'v_actor uuid;')
fn(G,'erp._order_write_guard','',[],'trigger',"""
  v_kind:=CASE WHEN TG_TABLE_NAME='sales_orders' THEN 'sales' ELSE 'purchase' END;
  v_party_type:=CASE WHEN v_kind='sales' THEN 'customer' ELSE 'supplier' END;
  v_party_key:=v_party_type||'_id';
  -- The earlier metadata trigger permits only an administrator's standalone frozen transition.
  IF TG_OP='UPDATE' AND NEW.frozen IS DISTINCT FROM OLD.frozen THEN
    NEW.locked_by:=NULL; NEW.locked_at:=NULL; NEW.lock_version:=OLD.lock_version+1;
    RETURN NEW;
  END IF;
  -- Administrator-only metadata touch after changing an item's frozen flag, not business data.
  IF TG_OP='UPDATE' AND auth._database_admin(TG_RELID)
    AND (to_jsonb(NEW)-'updated_at')=(to_jsonb(OLD)-'updated_at') THEN RETURN NEW; END IF;
  IF TG_OP='DELETE' THEN v_row:=to_jsonb(OLD); ELSE v_row:=to_jsonb(NEW); END IF;
  v_actor:=erp._context_actor(v_kind,(v_row->>'id')::uuid);
  v_party:=(v_row->>v_party_key)::uuid;
  IF v_party IS NULL THEN v_party_type:=NULL; END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.status<>'draft' OR NEW.created_by_user_id IS DISTINCT FROM v_actor THEN RAISE EXCEPTION 'New order must be an actor-owned draft' USING ERRCODE='23514'; END IF;
    PERFORM auth._require_permission(v_actor,'order.'||v_kind||'.create_draft',v_kind||'_order',v_actor,v_party_type,v_party);
    IF NEW.frozen THEN NEW.locked_by:=NULL; NEW.locked_at:=NULL; NEW.lock_version:=0;
    ELSE NEW.locked_by:=v_actor; NEW.locked_at:=clock_timestamp(); NEW.lock_version:=1;
      PERFORM erp._audit(v_actor,'order.'||v_kind||'.edit_opened',v_kind||'_order',NEW.id,jsonb_build_object('lock_version','1','editor',v_actor));
    END IF;
    RETURN NEW;
  END IF;
  BEGIN v_version:=nullif(current_setting('hanouti.lock_version',true),'')::bigint;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'Invalid lock version' USING ERRCODE='55000'; END;
  IF TG_OP='UPDATE' AND (NEW.locked_by,NEW.locked_at,NEW.lock_version) IS DISTINCT FROM (OLD.locked_by,OLD.locked_at,OLD.lock_version) THEN
    IF (to_jsonb(NEW)-ARRAY['locked_by','locked_at','lock_version','updated_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['locked_by','locked_at','lock_version','updated_at'])
      OR NEW.lock_version IS DISTINCT FROM OLD.lock_version THEN RAISE EXCEPTION 'Change locking separately; lock_version is database-managed' USING ERRCODE='22023'; END IF;
    v_action:=current_setting('hanouti.lock_action',true);
    v_now:=clock_timestamp();
    IF v_action IN ('close','force_close') THEN
      IF NEW.locked_by IS NOT NULL OR NEW.locked_at IS NOT NULL OR OLD.locked_by IS NULL THEN RAISE EXCEPTION 'No matching lock to close' USING ERRCODE='55000'; END IF;
      IF v_version IS NULL OR v_version IS DISTINCT FROM OLD.lock_version THEN RAISE EXCEPTION 'Lock changed; refresh before closing' USING ERRCODE='40001'; END IF;
      IF v_action='force_close' THEN
        PERFORM erp._require_write_context(v_actor,current_setting('hanouti.change_reason',true));
        PERFORM auth._require_permission(v_actor,'order.'||v_kind||'.force_close_edit',v_kind||'_order',OLD.created_by_user_id,v_party_type,v_party);
      ELSIF OLD.locked_by IS DISTINCT FROM v_actor THEN RAISE EXCEPTION 'Only the lock owner may close it normally' USING ERRCODE='42501'; END IF;
      NEW.lock_version:=OLD.lock_version+1;
      PERFORM erp._audit(v_actor,'order.'||v_kind||CASE WHEN v_action='force_close' THEN '.edit_force_closed' ELSE '.edit_closed' END,
        v_kind||'_order',OLD.id,jsonb_build_object('previous_editor',OLD.locked_by,'closed_version',OLD.lock_version::text,'reason',current_setting('hanouti.change_reason',true)));
    ELSIF v_action IN ('open','renew') THEN
      IF OLD.status<>'draft' OR NEW.locked_by IS DISTINCT FROM v_actor THEN RAISE EXCEPTION 'An editor may only acquire a draft for themself' USING ERRCODE='42501'; END IF;
      PERFORM auth._require_permission(v_actor,'order.'||v_kind||'.update_draft',v_kind||'_order',OLD.created_by_user_id,v_party_type,v_party);
      IF v_action='open' THEN
        IF OLD.locked_by IS NOT NULL AND OLD.locked_at>v_now-interval '5 minutes' THEN RAISE EXCEPTION 'Order already locked; close it before reopening' USING ERRCODE='55P03'; END IF;
        IF OLD.locked_by IS NOT NULL THEN
          PERFORM erp._audit(v_actor,'order.'||v_kind||'.edit_expired',v_kind||'_order',OLD.id,jsonb_build_object('previous_editor',OLD.locked_by,'lock_version',OLD.lock_version::text));
        END IF;
        NEW.lock_version:=OLD.lock_version+1;
        PERFORM erp._audit(v_actor,'order.'||v_kind||'.edit_opened',v_kind||'_order',OLD.id,jsonb_build_object('editor',v_actor,'lock_version',NEW.lock_version::text));
      ELSE
        IF OLD.locked_by IS DISTINCT FROM v_actor OR OLD.locked_at IS NULL OR OLD.locked_at<=v_now-interval '5 minutes'
          OR v_version IS NULL OR v_version IS DISTINCT FROM OLD.lock_version THEN RAISE EXCEPTION 'Expired or replaced lock cannot be renewed' USING ERRCODE='55000'; END IF;
        NEW.lock_version:=OLD.lock_version;
      END IF;
      NEW.locked_at:=v_now;
    ELSE RAISE EXCEPTION 'Use explicit open, renew or close operations for lock fields' USING ERRCODE='42501'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.status<>'draft' OR OLD.locked_by IS DISTINCT FROM v_actor OR OLD.locked_at IS NULL
    OR OLD.locked_at<=clock_timestamp()-interval '5 minutes' OR v_version IS NULL OR v_version IS DISTINCT FROM OLD.lock_version THEN
    RAISE EXCEPTION 'A current actor-owned draft lock is required' USING ERRCODE='55000';
  END IF;
  PERFORM auth._require_permission(v_actor,'order.'||v_kind||CASE WHEN TG_OP='DELETE' THEN '.delete_draft' ELSE '.update_draft' END,
    v_kind||'_order',OLD.created_by_user_id,CASE WHEN (to_jsonb(OLD)->>v_party_key) IS NULL THEN NULL WHEN v_kind='sales' THEN 'customer' ELSE 'supplier' END,(to_jsonb(OLD)->>v_party_key)::uuid);
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF (to_jsonb(NEW)-ARRAY['notes','expected_on','updated_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['notes','expected_on','updated_at']) THEN
    RAISE EXCEPTION 'Order identity, parties, currency and lifecycle are not editable through this draft path' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
""",'v_kind text; v_party_type text; v_party_key text; v_party uuid; v_actor uuid; v_row jsonb; v_version bigint; v_action text; v_now timestamptz;')
fn(G,'erp._order_item_guard','',[],'trigger',"""
  v_kind:=CASE WHEN TG_TABLE_NAME='sales_order_items' THEN 'sales' ELSE 'purchase' END;
  v_key:=CASE WHEN v_kind='sales' THEN 'sales_order_id' ELSE 'purchase_order_id' END;
  IF TG_OP='DELETE' THEN v_item:=to_jsonb(OLD); ELSE v_item:=to_jsonb(NEW); END IF;
  v_id:=(v_item->>v_key)::uuid;
  IF TG_OP='UPDATE' AND (to_jsonb(NEW)->v_key) IS DISTINCT FROM (to_jsonb(OLD)->v_key) THEN RAISE EXCEPTION 'An item cannot be moved to another order' USING ERRCODE='22023'; END IF;
  v_order:=erp._lock_edit_order(v_kind,v_id);
  IF (v_order->>'frozen')::boolean THEN RAISE EXCEPTION 'Frozen order protects all its items' USING ERRCODE='55000'; END IF;
  IF TG_OP='UPDATE' AND NEW.frozen IS DISTINCT FROM OLD.frozen THEN
    -- The preceding generic trigger has already verified a database administrator and flag-only change.
    v_admin_metadata:=true;
  ELSE
    v_actor:=erp._context_actor(v_kind,v_id);
    BEGIN v_version:=nullif(current_setting('hanouti.lock_version',true),'')::bigint;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'Invalid lock version' USING ERRCODE='55000'; END;
    PERFORM erp._assert_order_edit(v_actor,v_kind,v_id,v_version);
    PERFORM auth._require_permission(v_actor,'order.'||v_kind||'.update_draft',v_kind||'_order',(v_order->>'owner_user_id')::uuid,
      v_order->>'party_type',(v_order->>'party_id')::uuid);
  END IF;
  -- Parent timestamp changes even for direct item DML; the parent lock is held through commit.
  IF v_kind='sales' THEN UPDATE erp.sales_orders SET updated_at=clock_timestamp() WHERE id=v_id;
  ELSE UPDATE erp.purchase_orders SET updated_at=clock_timestamp() WHERE id=v_id; END IF;
  IF NOT v_admin_metadata THEN
    PERFORM erp._audit(v_actor,'order.'||v_kind||'.item_'||lower(TG_OP),v_kind||'_order',v_id,
      jsonb_build_object('item_id',v_item->>'id','lock_version',v_version::text));
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
""",'v_kind text; v_key text; v_id uuid; v_actor uuid; v_version bigint; v_item jsonb; v_order jsonb; v_admin_metadata boolean := false;')
fn(L,'erp._lock_edit_order','p_kind text, p_order_id uuid',['text','uuid'],'jsonb',"""
  IF p_kind='sales' THEN
    SELECT id,created_by_user_id,customer_id AS party_id,status,updated_at,frozen,locked_by,locked_at,lock_version
      INTO v_order FROM erp.sales_orders WHERE id=p_order_id FOR UPDATE;
  ELSIF p_kind='purchase' THEN
    SELECT id,created_by_user_id,supplier_id AS party_id,status,updated_at,frozen,locked_by,locked_at,lock_version
      INTO v_order FROM erp.purchase_orders WHERE id=p_order_id FOR UPDATE;
  ELSE RAISE EXCEPTION 'Unsupported order kind' USING ERRCODE='22023'; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('id',v_order.id,'kind',p_kind,'owner_user_id',v_order.created_by_user_id,
    'party_id',v_order.party_id,'party_type',CASE WHEN v_order.party_id IS NULL THEN NULL WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END,
    'status',v_order.status,'updated_at',v_order.updated_at,'frozen',v_order.frozen,'locked_by',v_order.locked_by,
    'locked_at',v_order.locked_at,'lock_version',v_order.lock_version::text);
""",'v_order record;')
fn(L,'erp._assert_order_edit','p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint',['uuid','text','uuid','bigint'],'jsonb',"""
  PERFORM auth._require_active_actor(p_actor);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF (v_order->>'frozen')::boolean OR v_order->>'status'<>'draft' THEN RAISE EXCEPTION 'Only unfrozen drafts may be edited' USING ERRCODE='55000'; END IF;
  IF p_lock_version IS NULL OR (v_order->>'lock_version')::bigint IS DISTINCT FROM p_lock_version
    OR (v_order->>'locked_by')::uuid IS DISTINCT FROM p_actor OR v_order->>'locked_at' IS NULL
    OR (v_order->>'locked_at')::timestamptz<=clock_timestamp()-interval '5 minutes' THEN
    RAISE EXCEPTION 'Draft lock expired, closed or replaced; reopen before editing' USING ERRCODE='55000';
  END IF;
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'locked_by',p_actor,'locked_at',v_order->'locked_at',
    'lock_version',v_order->>'lock_version','expires_at',(v_order->>'locked_at')::timestamptz+interval '5 minutes','updated_at',v_order->'updated_at');
""",'v_order jsonb;')
fn(L,'erp.open_order_edit','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],'jsonb',"""
  PERFORM erp._require_write_context(p_actor,'Open draft');
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.update_draft',p_kind||'_order',(v_order->>'owner_user_id')::uuid,v_order->>'party_type',(v_order->>'party_id')::uuid);
  IF v_order->>'locked_by' IS NOT NULL AND (v_order->>'locked_at')::timestamptz>clock_timestamp()-interval '5 minutes' THEN RAISE EXCEPTION 'Order already locked; close it before reopening' USING ERRCODE='55P03'; END IF;
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,NULL,'open','Open draft');
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_by=p_actor,locked_at=clock_timestamp() WHERE id=p_order_id RETURNING lock_version INTO v_version;
  ELSE UPDATE erp.purchase_orders SET locked_by=p_actor,locked_at=clock_timestamp() WHERE id=p_order_id RETURNING lock_version INTO v_version; END IF;
  v_result:=erp._assert_order_edit(p_actor,p_kind,p_order_id,v_version);
  PERFORM erp._restore_edit_context(v_previous);
  RETURN v_result;
""",'v_order jsonb; v_previous jsonb; v_result jsonb; v_version bigint;',True)
fn(L,'erp.renew_order_edit','p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint',['uuid','text','uuid','bigint'],'jsonb',"""
  PERFORM erp._require_write_context(p_actor,'Renew draft');
  PERFORM erp._assert_order_edit(p_actor,p_kind,p_order_id,p_lock_version);
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,p_lock_version,'renew','Renew draft');
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_at=clock_timestamp() WHERE id=p_order_id;
  ELSE UPDATE erp.purchase_orders SET locked_at=clock_timestamp() WHERE id=p_order_id; END IF;
  v_result:=erp._assert_order_edit(p_actor,p_kind,p_order_id,p_lock_version);
  PERFORM erp._restore_edit_context(v_previous);
  RETURN v_result;
""",'v_previous jsonb; v_result jsonb;',True)
for force in (False,True):
 name='erp.force_close_order_edit' if force else 'erp.close_order_edit'
 args="p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint, p_reason text"+('' if force else " DEFAULT 'Editing finished'")
 action='force_close' if force else 'close'
 fn(L,name,args,['uuid','text','uuid','bigint','text'],'jsonb',f"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF v_order->>'locked_by' IS NULL THEN RAISE EXCEPTION 'No editing lock to close' USING ERRCODE='55000'; END IF;
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,p_lock_version,'{action}',p_reason);
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version;
  ELSE UPDATE erp.purchase_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version; END IF;
  PERFORM erp._restore_edit_context(v_previous);
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'closed',true,'lock_version',v_version::text);
""",'v_order jsonb; v_previous jsonb; v_version bigint;',True)
fn(L,'erp.order_edit_status','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],'jsonb',"""
  PERFORM erp.order_totals(p_actor,p_kind,p_order_id);
  IF p_kind='sales' THEN SELECT frozen,locked_by,locked_at,lock_version INTO v_order FROM erp.sales_orders WHERE id=p_order_id;
  ELSE SELECT frozen,locked_by,locked_at,lock_version INTO v_order FROM erp.purchase_orders WHERE id=p_order_id; END IF;
  v_active:=NOT v_order.frozen AND v_order.locked_by IS NOT NULL AND v_order.locked_at>clock_timestamp()-interval '5 minutes';
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'frozen',v_order.frozen,'is_locked',coalesce(v_active,false),
    'locked_by',CASE WHEN v_active THEN v_order.locked_by END,'locked_at',v_order.locked_at,
    'lock_version',v_order.lock_version::text,'expires_at',v_order.locked_at+interval '5 minutes');
""",'v_order record; v_active boolean;',True)
# Triggers are enabled only after every helper has been declared (end of file 011).
import re
all_tables=[]
for p in sorted((R/'migrations/hanouti').glob('00[2-6]*.sql')):
 all_tables+=re.findall(r'CREATE TABLE (\w+)\.(\w+) \(',p.read_text())
for filename,defs in files.items():
 text='-- UNAPPLIED DECLARATIONS ONLY. Fresh baseline; apply all files before enabling application access.\n-- SECURITY DEFINER functions require reviewed owner/runtime privileges.\nBEGIN;\n\n'+'\n'.join(defs)
 if filename==L:
  text+='\n-- Trigger order is intentional: metadata/frozen protection before order-specific checks.\n'
  for schema,table in all_tables:
   text+=f'CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON {schema}.{table}\n  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();\n'
  for table in ('sales_orders','purchase_orders'):
   text+=f'CREATE TRIGGER b_order_write BEFORE INSERT OR UPDATE OR DELETE ON erp.{table}\n  FOR EACH ROW EXECUTE FUNCTION erp._order_write_guard();\n'
  for table in ('sales_order_items','purchase_order_items'):
   text+=f'CREATE TRIGGER b_order_item_write BEFORE INSERT OR UPDATE OR DELETE ON erp.{table}\n  FOR EACH ROW EXECUTE FUNCTION erp._order_item_guard();\n'
 text+='\nCOMMIT;\n';(R/'migrations/hanouti'/filename).write_text(text)
(R/'tests/fixtures/routines-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print('Tables:',len(all_tables),'routines:',len(m),'entry points:',sum(x['exposed'] for x in m))
