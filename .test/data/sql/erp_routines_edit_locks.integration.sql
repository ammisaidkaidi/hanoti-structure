-- UNEXECUTED assertions for a NEW disposable database: baseline 001..011 plus catalog seed.
-- Test provisioning administrator only. No connection/execution is wired into package scripts.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DO $test$
DECLARE
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); ar uuid:=gen_random_uuid(); br uuid:=gen_random_uuid();
  customer uuid:=gen_random_uuid(); supplier uuid:=gen_random_uuid(); warehouse uuid:=gen_random_uuid(); product uuid:=gen_random_uuid();
  doc jsonb; draft jsonb; purchase jsonb; state jsonb; previous jsonb;
  oid uuid; line_id uuid; old_version bigint; current_version bigint; before_time timestamptz;
BEGIN
  INSERT INTO auth.users(id,email,display_name,status) VALUES
    (a,a||'@example.test','Editor A','active'),(b,b||'@example.test','Supervisor B','active');
  INSERT INTO auth.roles(id,code,name) VALUES
    (ar,'editor_'||replace(ar::text,'-',''),'Editor fixture'),(br,'supervisor_'||replace(br::text,'-',''),'Supervisor fixture');
  INSERT INTO auth.user_roles(user_id,role_id) VALUES(a,ar),(b,br);
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT ar,id,'allow','all','Editing fixture' FROM auth.permissions WHERE code IN
      ('order.sales.read','order.sales.create_draft','order.sales.update_draft','order.purchase.read','order.purchase.create_draft','order.purchase.update_draft');
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT br,id,'allow','all','Supervisor fixture' FROM auth.permissions WHERE code IN
      ('order.sales.read','order.sales.update_draft','order.sales.force_close_edit','order.purchase.read','order.purchase.update_draft','order.purchase.force_close_edit');
  INSERT INTO erp.customers(id,code,name) VALUES(customer,customer::text,'Guard test customer');
  INSERT INTO erp.suppliers(id,code,name) VALUES(supplier,supplier::text,'Guard test supplier');
  INSERT INTO erp.warehouses(id,code,name) VALUES(warehouse,warehouse::text,'Guard test warehouse');
  INSERT INTO erp.products(id,sku,name,currency_code,sale_price) VALUES(product,product::text,'Guard test product','DZD',100);
  doc:=jsonb_build_object('order_number',a::text,'customer_id',customer,'warehouse_id',warehouse,'currency_code','DZD',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity','2')));
  -- Creating with lines must not acquire an additional update_draft prerequisite.
  DELETE FROM auth.role_permissions WHERE role_id=ar AND permission_id=(SELECT id FROM auth.permissions WHERE code='order.sales.update_draft');
  draft:=erp.save_sales_order_draft(a,doc,'Create-only draft');
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT ar,id,'allow','all','Restore editing permission' FROM auth.permissions WHERE code='order.sales.update_draft';
  oid:=(draft->>'id')::uuid; old_version:=(draft->'edit_lock'->>'lock_version')::bigint;
  ASSERT old_version=1;
  ASSERT (SELECT locked_by=a AND locked_at IS NOT NULL AND lock_version=old_version FROM erp.sales_orders WHERE id=oid);
  ASSERT nullif(current_setting('hanouti.actor_id',true),'') IS NULL;
  state:=erp.order_edit_status(b,'sales',oid);
  ASSERT state->'is_locked'='true'::jsonb AND (state->>'locked_by')::uuid=a;
  ASSERT (erp.order_totals(b,'sales',oid)->>'total')::numeric=200;
  BEGIN PERFORM erp.open_order_edit(b,'sales',oid); RAISE EXCEPTION 'Expected supervisor open refusal'; EXCEPTION WHEN lock_not_available THEN NULL; END;
  BEGIN PERFORM erp.open_order_edit(a,'sales',oid); RAISE EXCEPTION 'Expected same-user second-session refusal'; EXCEPTION WHEN lock_not_available THEN NULL; END;
  BEGIN PERFORM erp.save_sales_order_draft(b,doc,'Not the editor',oid,(draft->>'updated_at')::timestamptz,old_version); RAISE EXCEPTION 'Expected supervisor write refusal'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  before_time:=(draft->>'updated_at')::timestamptz;
  state:=erp.renew_order_edit(a,'sales',oid,old_version);
  ASSERT (state->>'lock_version')::bigint=old_version;
  ASSERT (SELECT updated_at=before_time FROM erp.sales_orders WHERE id=oid);

  -- These are privileged manual DML tests, not privileges available to the backend.
  BEGIN
    INSERT INTO erp.sales_order_items(sales_order_id,line_number,product_id,sku_snapshot,description,unit_code,quantity,unit_price)
      VALUES(oid,2,product,product::text,'Raw line','unit',1,100);
    RAISE EXCEPTION 'Expected missing context rejection';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  previous:=erp._set_edit_context(a,'sales',oid,old_version,'write','Manual trigger acceptance test');
  INSERT INTO erp.sales_order_items(sales_order_id,line_number,product_id,sku_snapshot,description,unit_code,quantity,unit_price)
    VALUES(oid,2,product,product::text,'Raw line','unit',1,100) RETURNING id INTO line_id;
  ASSERT (SELECT updated_at>before_time FROM erp.sales_orders WHERE id=oid);
  PERFORM erp._restore_edit_context(previous);
  BEGIN PERFORM erp.save_sales_order_draft(a,doc,'Stale replacement',oid,before_time,old_version); RAISE EXCEPTION 'Expected stale timestamp rejection'; EXCEPTION WHEN serialization_failure THEN NULL; END;

  -- Freeze is an administrator-only, standalone metadata operation; stored generated totals are ignored by the flag-only comparator.
  UPDATE erp.sales_order_items SET frozen=true WHERE id=line_id;
  previous:=erp._set_edit_context(a,'sales',oid,old_version,'write','Frozen item test');
  BEGIN UPDATE erp.sales_order_items SET quantity=3 WHERE id=line_id; RAISE EXCEPTION 'Expected frozen line rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN DELETE FROM erp.sales_order_items WHERE id=line_id; RAISE EXCEPTION 'Expected frozen line deletion rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  PERFORM erp._restore_edit_context(previous);
  UPDATE erp.sales_order_items SET frozen=false WHERE id=line_id;
  UPDATE erp.sales_orders SET frozen=true WHERE id=oid;
  ASSERT (SELECT locked_by IS NULL AND lock_version>old_version FROM erp.sales_orders WHERE id=oid);
  previous:=erp._set_edit_context(a,'sales',oid,old_version,'write','Frozen parent test');
  BEGIN UPDATE erp.sales_order_items SET quantity=3 WHERE id=line_id; RAISE EXCEPTION 'Expected frozen parent rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN UPDATE erp.sales_orders SET frozen=false,notes='Combined bypass' WHERE id=oid; RAISE EXCEPTION 'Expected mixed unfreeze rejection'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM erp._restore_edit_context(previous);
  ASSERT (erp.order_totals(b,'sales',oid)->>'total')::numeric=300;
  UPDATE erp.sales_orders SET frozen=false WHERE id=oid;
  state:=erp.open_order_edit(a,'sales',oid); old_version:=(state->>'lock_version')::bigint;

  PERFORM erp.force_close_order_edit(b,'sales',oid,old_version,'Explicit takeover');
  ASSERT erp.order_edit_status(b,'sales',oid)->'is_locked'='false'::jsonb;
  BEGIN PERFORM erp.renew_order_edit(a,'sales',oid,old_version); RAISE EXCEPTION 'Expected revoked editor rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  state:=erp.open_order_edit(b,'sales',oid); current_version:=(state->>'lock_version')::bigint;
  ASSERT current_version>old_version;
  BEGIN PERFORM erp.force_close_order_edit(b,'sales',oid,old_version,'Stale screen'); RAISE EXCEPTION 'Expected stale close rejection'; EXCEPTION WHEN serialization_failure THEN NULL; END;

  -- Deterministic expiry fixture only: a disposable-db owner temporarily disables exactly the lock guard.
  -- Ordinary writes cannot backdate locked_at; the production trigger always supplies server time.
  ALTER TABLE erp.sales_orders DISABLE TRIGGER b_order_write;
  UPDATE erp.sales_orders SET locked_at=clock_timestamp()-interval '6 minutes' WHERE id=oid;
  ALTER TABLE erp.sales_orders ENABLE TRIGGER b_order_write;
  BEGIN PERFORM erp.renew_order_edit(b,'sales',oid,current_version); RAISE EXCEPTION 'Expected expired renewal rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  state:=erp.open_order_edit(a,'sales',oid);
  ASSERT (state->>'lock_version')::bigint>current_version;
  before_time:=(state->>'updated_at')::timestamptz;
  draft:=erp.save_sales_order_draft(a,doc,'Replace after takeover',oid,before_time,(state->>'lock_version')::bigint);
  ASSERT (SELECT updated_at=(draft->>'updated_at')::timestamptz FROM erp.sales_orders WHERE id=oid);

  -- Generic read-only semantics do not mean inactivity: a frozen active account still authorizes reads.
  UPDATE auth.users SET frozen=true WHERE id=a;
  ASSERT (erp.order_totals(a,'sales',oid)->>'total')::numeric=200;
  BEGIN UPDATE auth.users SET display_name='Changed' WHERE id=a; RAISE EXCEPTION 'Expected generic frozen rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  UPDATE auth.users SET frozen=false WHERE id=a;
  BEGIN TRUNCATE app.notifications; RAISE EXCEPTION 'Expected truncate rejection'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT EXISTS(SELECT 1 FROM app.audit_events WHERE action='row.freeze' AND metadata->>'database_login'=session_user);

  doc:=jsonb_build_object('order_number',b::text,'supplier_id',supplier,'warehouse_id',warehouse,'currency_code','DZD',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity','2','unit_cost','80')));
  purchase:=erp.save_purchase_order_draft(a,doc,'Purchase draft');
  BEGIN PERFORM erp.open_order_edit(b,'purchase',(purchase->>'id')::uuid); RAISE EXCEPTION 'Expected purchase editor exclusion'; EXCEPTION WHEN lock_not_available THEN NULL; END;
  UPDATE erp.purchase_orders SET frozen=true WHERE id=(purchase->>'id')::uuid;
  BEGIN DELETE FROM erp.purchase_order_items WHERE purchase_order_id=(purchase->>'id')::uuid; RAISE EXCEPTION 'Expected frozen purchase child rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END;
$test$;
ROLLBACK;
-- Still required: real separate-login ACL/freeze tests and two concurrent sessions. SET ROLE from a
-- superuser does NOT emulate a non-admin session_user for frozen-administration checks.
