-- UNEXECUTED privilege assertions. Disposable database only, after 020_erp_routine_privileges.sql.
-- Run as the test provisioning administrator, then separately audit the actual backend login.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE v_entry jsonb; v_oid oid; v_table record; v_schema text;
BEGIN
  ASSERT NOT pg_has_role('hanouti_backend','hanouti_routine_owner','MEMBER');
  ASSERT NOT pg_has_role('hanouti_backend','hanouti_data_admin','MEMBER');
  ASSERT to_regclass('erp.order_edit_locks') IS NULL;
  ASSERT to_regprocedure('erp.save_sales_order_draft(uuid,jsonb,text,uuid,timestamptz,uuid)') IS NULL;
  ASSERT to_regprocedure('erp.save_purchase_order_draft(uuid,jsonb,text,uuid,timestamptz,uuid)') IS NULL;
  -- A fresh baseline has no legacy writer overloads capable of bypassing the header-lock gate.
  ASSERT to_regprocedure('erp.save_sales_order_draft(uuid,jsonb,text,uuid,timestamptz)') IS NULL;
  ASSERT to_regprocedure('erp.save_purchase_order_draft(uuid,jsonb,text,uuid,timestamptz)') IS NULL;
  ASSERT to_regprocedure('erp._save_order_draft(uuid,text,jsonb,text,uuid,timestamptz)') IS NULL;
  ASSERT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('hanouti_backend','hanouti_routine_owner','hanouti_data_admin')
    AND (rolsuper OR rolcanlogin OR rolcreaterole OR rolcreatedb OR rolbypassrls));
  FOREACH v_schema IN ARRAY ARRAY['auth','erp','app','settings'] LOOP
    ASSERT NOT has_schema_privilege('hanouti_backend',v_schema,'CREATE');
  END LOOP;
  FOR v_table IN SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('auth','erp','app','settings') AND c.relkind IN ('r','p')
  LOOP
    ASSERT NOT has_table_privilege('hanouti_backend',v_table.oid,'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER');
    ASSERT NOT has_any_column_privilege('hanouti_backend',v_table.oid,'SELECT, INSERT, UPDATE, REFERENCES');
  END LOOP;
  FOR v_entry IN SELECT value FROM jsonb_array_elements($list$[{"signature": "auth._require_active_actor(uuid)", "exposed": false}, {"signature": "auth._party_member(uuid, text, uuid)", "exposed": false}, {"signature": "auth.has_permission(uuid, text, text, uuid, text, uuid)", "exposed": true}, {"signature": "auth._require_permission(uuid, text, text, uuid, text, uuid)", "exposed": false}, {"signature": "settings._validate_context(uuid, jsonb)", "exposed": false}, {"signature": "settings._validate_value(settings.setting_definitions, jsonb, jsonb)", "exposed": false}, {"signature": "settings._resolve(uuid, text, jsonb)", "exposed": false}, {"signature": "settings.resolve(uuid, text, jsonb)", "exposed": true}, {"signature": "settings._boolean(uuid, text, jsonb)", "exposed": false}, {"signature": "settings._number(uuid, text, jsonb)", "exposed": false}, {"signature": "erp._require_write_context(uuid, text)", "exposed": false}, {"signature": "erp._audit(uuid, text, text, uuid, jsonb)", "exposed": false}, {"signature": "erp._validate_quantity(uuid, numeric, jsonb)", "exposed": false}, {"signature": "erp.stock_balance(uuid, uuid, uuid)", "exposed": true}, {"signature": "erp._check_stock_result(uuid, uuid, uuid, numeric, jsonb)", "exposed": false}, {"signature": "erp.adjust_stock(uuid, uuid, uuid, numeric, text, text)", "exposed": true}, {"signature": "erp.transfer_stock(uuid, uuid, uuid, uuid, numeric, text, text)", "exposed": true}, {"signature": "erp._save_order_draft(uuid, text, jsonb, text, uuid, timestamptz, bigint)", "exposed": false}, {"signature": "erp.save_sales_order_draft(uuid, jsonb, text, uuid, timestamptz, bigint)", "exposed": true}, {"signature": "erp.save_purchase_order_draft(uuid, jsonb, text, uuid, timestamptz, bigint)", "exposed": true}, {"signature": "erp.order_totals(uuid, text, uuid)", "exposed": true}, {"signature": "erp.order_detail(uuid, text, uuid)", "exposed": true}, {"signature": "erp.sales_payment_balance(uuid, uuid)", "exposed": true}, {"signature": "auth._database_admin(oid)", "exposed": false}, {"signature": "auth._row_metadata_guard()", "exposed": false}, {"signature": "erp._set_edit_context(uuid, text, uuid, bigint, text, text)", "exposed": false}, {"signature": "erp._restore_edit_context(jsonb)", "exposed": false}, {"signature": "erp._context_actor(text, uuid)", "exposed": false}, {"signature": "erp._order_write_guard()", "exposed": false}, {"signature": "erp._order_item_guard()", "exposed": false}, {"signature": "erp._lock_edit_order(text, uuid)", "exposed": false}, {"signature": "erp._assert_order_edit(uuid, text, uuid, bigint)", "exposed": false}, {"signature": "erp.open_order_edit(uuid, text, uuid)", "exposed": true}, {"signature": "erp.renew_order_edit(uuid, text, uuid, bigint)", "exposed": true}, {"signature": "erp.close_order_edit(uuid, text, uuid, bigint, text)", "exposed": true}, {"signature": "erp.force_close_order_edit(uuid, text, uuid, bigint, text)", "exposed": true}, {"signature": "erp.order_edit_status(uuid, text, uuid)", "exposed": true}, {"signature": "erp._product_full_name_guard()", "exposed": false}]$list$::jsonb) LOOP
    v_oid:=to_regprocedure(v_entry->>'signature');
    ASSERT v_oid IS NOT NULL;
    ASSERT has_function_privilege('hanouti_backend',v_oid,'EXECUTE')=(v_entry->>'exposed')::boolean;
    ASSERT (SELECT prosecdef AND proowner=(SELECT oid FROM pg_roles WHERE rolname='hanouti_routine_owner')
      AND proconfig @> ARRAY['search_path=pg_catalog, pg_temp'] FROM pg_proc WHERE oid=v_oid);
    ASSERT NOT EXISTS(SELECT 1 FROM pg_proc p, LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE p.oid=v_oid AND a.grantee=0 AND a.privilege_type='EXECUTE');
  END LOOP;
END;
$test$;
ROLLBACK;
