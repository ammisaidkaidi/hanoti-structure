from pathlib import Path
import json
root=Path('/home/user/hanouti/data')
file='011_order_edit_routines.sql'
manifest=json.loads((root/'tests/fixtures/routines-manifest.json').read_text())
assert not any(x['file']==file for x in manifest), 'Already generated: do not rerun blindly'
parts=[]
def fn(name,args,types,body,declare='',public=False):
 sig=f'{name}({", ".join(types)})'
 parts.append(f'CREATE FUNCTION {name}({args})\nRETURNS jsonb\nLANGUAGE plpgsql VOLATILE SECURITY DEFINER\nSET search_path = pg_catalog, pg_temp\nAS $fn$\n'+('DECLARE\n'+declare+'\n' if declare else '')+'BEGIN\n'+body.strip()+'\nEND;\n$fn$;\n'+f'REVOKE ALL ON FUNCTION {sig} FROM PUBLIC;\n')
 manifest.append({'name':name,'signature':sig,'file':file,'exposed':public})
permission="""PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.update_draft',p_kind||'_order',
    (v_order->>'owner_user_id')::uuid,v_order->>'party_type',(v_order->>'party_id')::uuid);"""
fn('erp._lock_edit_order','p_kind text, p_order_id uuid',['text','uuid'],"""
  -- EVERY lease operation and draft save takes the parent row before its lease row.
  IF p_kind='sales' THEN
    SELECT id,created_by_user_id,customer_id AS party_id,status,updated_at INTO v_order
      FROM erp.sales_orders WHERE id=p_order_id FOR UPDATE;
  ELSIF p_kind='purchase' THEN
    SELECT id,created_by_user_id,supplier_id AS party_id,status,updated_at INTO v_order
      FROM erp.purchase_orders WHERE id=p_order_id FOR UPDATE;
  ELSE RAISE EXCEPTION 'Unsupported order kind' USING ERRCODE='22023'; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('id',v_order.id,'kind',p_kind,'owner_user_id',v_order.created_by_user_id,
    'party_id',v_order.party_id,'party_type',CASE WHEN v_order.party_id IS NULL THEN NULL
      WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END,'status',v_order.status,'updated_at',v_order.updated_at);
""",'v_order record;')
fn('erp._assert_order_edit','p_actor uuid, p_kind text, p_order_id uuid, p_lease_token uuid',['uuid','text','uuid','uuid'],"""
  PERFORM auth._require_active_actor(p_actor);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF v_order->>'status'<>'draft' THEN RAISE EXCEPTION 'Only drafts may be edited' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_lease FROM erp.order_edit_locks
    WHERE (p_kind='sales' AND sales_order_id=p_order_id)
       OR (p_kind='purchase' AND purchase_order_id=p_order_id) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Open the draft for editing first' USING ERRCODE='55000'; END IF;
  -- Wall clock AFTER waiting for row locks; transaction/statement start times are unsafe here.
  IF p_lease_token IS NULL OR v_lease.lease_token IS DISTINCT FROM p_lease_token
    OR v_lease.owner_user_id IS DISTINCT FROM p_actor OR v_lease.expires_at IS NULL
    OR v_lease.expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'Editing session expired, closed, or belongs to another editor; reopen the draft' USING ERRCODE='55000';
  END IF;
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'lease_token',v_lease.lease_token,
    'generation',v_lease.generation::text,'expires_at',v_lease.expires_at,'updated_at',v_order->'updated_at');
""",'v_order jsonb; v_lease erp.order_edit_locks%ROWTYPE;')
fn('erp._open_order_edit','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],"""
  PERFORM auth._require_active_actor(p_actor);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF v_order->>'status'<>'draft' THEN RAISE EXCEPTION 'Only drafts may be opened for editing' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_lease FROM erp.order_edit_locks
    WHERE (p_kind='sales' AND sales_order_id=p_order_id)
       OR (p_kind='purchase' AND purchase_order_id=p_order_id) FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO erp.order_edit_locks(sales_order_id,purchase_order_id)
      VALUES(CASE WHEN p_kind='sales' THEN p_order_id END,CASE WHEN p_kind='purchase' THEN p_order_id END)
      RETURNING * INTO v_lease;
  END IF;
  v_now:=clock_timestamp();
  IF v_lease.owner_user_id IS NOT NULL AND v_lease.expires_at>v_now THEN
    -- Same actor in another tab is not a new editing session; never reveal the existing token.
    RAISE EXCEPTION 'Draft is already open for editing; renew the existing session or close it first' USING ERRCODE='55P03';
  END IF;
  IF v_lease.owner_user_id IS NOT NULL THEN
    PERFORM erp._audit(p_actor,'order.'||p_kind||'.edit_expired',p_kind||'_order',p_order_id,
      jsonb_build_object('previous_editor',v_lease.owner_user_id,'generation',v_lease.generation::text,'expired_at',v_lease.expires_at));
  END IF;
  UPDATE erp.order_edit_locks SET owner_user_id=p_actor,lease_token=gen_random_uuid(),
    generation=generation+1,opened_at=v_now,renewed_at=v_now,expires_at=v_now+interval '5 minutes',updated_at=v_now
    WHERE id=v_lease.id RETURNING * INTO v_lease;
  PERFORM erp._audit(p_actor,'order.'||p_kind||'.edit_opened',p_kind||'_order',p_order_id,
    jsonb_build_object('editor',p_actor,'generation',v_lease.generation::text,'expires_at',v_lease.expires_at));
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'lease_token',v_lease.lease_token,
    'generation',v_lease.generation::text,'expires_at',v_lease.expires_at,'updated_at',v_order->'updated_at');
""",'v_order jsonb; v_lease erp.order_edit_locks%ROWTYPE; v_now timestamptz;')
fn('erp.open_order_edit','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],"""
  PERFORM erp._require_write_context(p_actor,'Open draft editing session');
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  """+permission+"""
  RETURN erp._open_order_edit(p_actor,p_kind,p_order_id);
""",'v_order jsonb;',True)
fn('erp.renew_order_edit','p_actor uuid, p_kind text, p_order_id uuid, p_lease_token uuid',['uuid','text','uuid','uuid'],"""
  PERFORM erp._require_write_context(p_actor,'Renew draft editing session');
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  """+permission+"""
  PERFORM erp._assert_order_edit(p_actor,p_kind,p_order_id,p_lease_token);
  v_now:=clock_timestamp();
  UPDATE erp.order_edit_locks SET renewed_at=v_now,expires_at=v_now+interval '5 minutes',updated_at=v_now
    WHERE ((p_kind='sales' AND sales_order_id=p_order_id) OR (p_kind='purchase' AND purchase_order_id=p_order_id))
      AND owner_user_id=p_actor AND lease_token=p_lease_token AND expires_at>v_now
    RETURNING * INTO v_lease;
  IF NOT FOUND THEN RAISE EXCEPTION 'Editing session expired; renewal cannot revive it' USING ERRCODE='55000'; END IF;
  -- Heartbeats update the lease row; no high-volume audit event and no draft version change.
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'generation',v_lease.generation::text,'expires_at',v_lease.expires_at);
""",'v_order jsonb; v_lease erp.order_edit_locks%ROWTYPE; v_now timestamptz;',True)
fn('erp.close_order_edit',"p_actor uuid, p_kind text, p_order_id uuid, p_lease_token uuid, p_reason text DEFAULT 'Editing finished'",['uuid','text','uuid','uuid','text'],"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  PERFORM erp._lock_edit_order(p_kind,p_order_id);
  SELECT * INTO v_lease FROM erp.order_edit_locks
    WHERE (p_kind='sales' AND sales_order_id=p_order_id)
       OR (p_kind='purchase' AND purchase_order_id=p_order_id) FOR UPDATE;
  IF NOT FOUND OR p_lease_token IS NULL OR v_lease.owner_user_id IS DISTINCT FROM p_actor
    OR v_lease.lease_token IS DISTINCT FROM p_lease_token THEN
    RAISE EXCEPTION 'This editing session is no longer yours to close' USING ERRCODE='55000';
  END IF;
  -- Releasing one's own matching session is safe even if edit permission was revoked or it expired.
  UPDATE erp.order_edit_locks SET owner_user_id=NULL,lease_token=NULL,opened_at=NULL,renewed_at=NULL,expires_at=NULL,
    generation=generation+1,updated_at=clock_timestamp() WHERE id=v_lease.id;
  PERFORM erp._audit(p_actor,'order.'||p_kind||'.edit_closed',p_kind||'_order',p_order_id,
    jsonb_build_object('previous_editor',v_lease.owner_user_id,'closed_generation',v_lease.generation::text,'reason',p_reason));
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'closed',true,'generation',(v_lease.generation+1)::text);
""",'v_lease erp.order_edit_locks%ROWTYPE;',True)
fn('erp.force_close_order_edit','p_actor uuid, p_kind text, p_order_id uuid, p_expected_generation bigint, p_reason text',['uuid','text','uuid','bigint','text'],"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.force_close_edit',p_kind||'_order',
    (v_order->>'owner_user_id')::uuid,v_order->>'party_type',(v_order->>'party_id')::uuid);
  SELECT * INTO v_lease FROM erp.order_edit_locks
    WHERE (p_kind='sales' AND sales_order_id=p_order_id)
       OR (p_kind='purchase' AND purchase_order_id=p_order_id) FOR UPDATE;
  IF NOT FOUND OR v_lease.owner_user_id IS NULL THEN RAISE EXCEPTION 'No editing session to close' USING ERRCODE='55000'; END IF;
  IF p_expected_generation IS NULL OR p_expected_generation IS DISTINCT FROM v_lease.generation THEN
    RAISE EXCEPTION 'Editing session changed; refresh before force-closing' USING ERRCODE='40001';
  END IF;
  UPDATE erp.order_edit_locks SET owner_user_id=NULL,lease_token=NULL,opened_at=NULL,renewed_at=NULL,expires_at=NULL,
    generation=generation+1,updated_at=clock_timestamp() WHERE id=v_lease.id;
  PERFORM erp._audit(p_actor,'order.'||p_kind||'.edit_force_closed',p_kind||'_order',p_order_id,
    jsonb_build_object('previous_editor',v_lease.owner_user_id,'closed_generation',v_lease.generation::text,'reason',p_reason));
  -- Deliberately does NOT give the supervisor ownership or a token. Explicit reopen is required.
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'closed',true,'generation',(v_lease.generation+1)::text);
""",'v_order jsonb; v_lease erp.order_edit_locks%ROWTYPE;',True)
fn('erp.order_edit_status','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],"""
  -- The ordinary read check remains in force; an editing lease never blocks authorized viewing.
  PERFORM erp.order_totals(p_actor,p_kind,p_order_id);
  SELECT * INTO v_lease FROM erp.order_edit_locks
    WHERE (p_kind='sales' AND sales_order_id=p_order_id)
       OR (p_kind='purchase' AND purchase_order_id=p_order_id);
  v_active:=coalesce(v_lease.owner_user_id IS NOT NULL AND v_lease.expires_at>clock_timestamp(),false);
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'is_locked',v_active,
    'owner_user_id',CASE WHEN v_active THEN v_lease.owner_user_id END,
    'generation',coalesce(v_lease.generation,0)::text,'expires_at',v_lease.expires_at);
""",'v_lease erp.order_edit_locks%ROWTYPE; v_active boolean;',True)
text='-- UNAPPLIED DECLARATIONS ONLY. Apply the full baseline through 011 before granting access.\n-- SECURITY DEFINER ownership and EXECUTE grants are reviewed separately in the privilege template.\nBEGIN;\n\n'+'\n'.join(parts)+'\nCOMMIT;\n'
(root/'migrations/hanouti'/file).write_text(text)
for item in manifest:
 if item['name']=='erp._save_order_draft':item['signature']='erp._save_order_draft(uuid, text, jsonb, text, uuid, timestamptz, uuid)'
 if item['name'] in ('erp.save_sales_order_draft','erp.save_purchase_order_draft'):
  item['signature']=item['name']+'(uuid, jsonb, text, uuid, timestamptz, uuid)'
(root/'tests/fixtures/routines-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(len(manifest),'functions;',sum(x['exposed'] for x in manifest),'backend entry points.')
