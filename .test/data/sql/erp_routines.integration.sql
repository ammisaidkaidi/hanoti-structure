-- UNEXECUTED integration test declarations. Requires a NEW disposable hanouti-compatible DB,
-- migrations 001..011 and seeds/010_erp_routine_catalog.sql. Run as a test administrator ONLY.
-- No live credentials or production data. Always rolls back fixtures on successful completion.
-- This is not a migration/seed and is NEVER run by pnpm test/check.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DO $test$
DECLARE
  actor uuid:=gen_random_uuid(); portal uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  portal_role uuid:=gen_random_uuid(); second_role uuid:=gen_random_uuid(); party uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); w1 uuid:=gen_random_uuid(); w2 uuid:=gen_random_uuid();
  movement uuid; transfer_id uuid; draft jsonb; doc jsonb; purchase jsonb; result jsonb; before_audit bigint;
BEGIN
  INSERT INTO auth.users(id,email,display_name,status) VALUES
    (actor,actor||'@example.test','Test worker','active'),(portal,portal||'@example.test','Test portal user','active');
  INSERT INTO auth.roles(id,code,name) VALUES(role_id,'test_'||replace(role_id::text,'-',''),'Test worker');
  INSERT INTO auth.user_roles(user_id,role_id) VALUES(actor,role_id);
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT role_id,p.id,'allow','all','Disposable integration fixture' FROM auth.permissions p
    WHERE p.code IN ('stock.read','stock.adjust','stock.transfer','order.sales.read','order.sales.create_draft','order.sales.update_draft',
      'order.purchase.read','order.purchase.create_draft','order.purchase.update_draft','payment.read','settings.read');
  INSERT INTO erp.customers(id,code,name) VALUES(party,party::text,'Test customer');
  INSERT INTO erp.suppliers(id,code,name) VALUES(supplier,supplier::text,'Test supplier');
  INSERT INTO erp.warehouses(id,code,name) VALUES(w1,w1::text,'Source'),(w2,w2::text,'Destination');
  INSERT INTO erp.products(id,sku,name,currency_code,sale_price) VALUES(product,product::text,'Test stock product','DZD',100);

  -- Default deny, resource-type matching, and no implicit grant from knowing an ID.
  ASSERT auth.has_permission(portal,'stock.read','stock')=false;
  ASSERT auth.has_permission(actor,'stock.read','payment')=false;
  BEGIN PERFORM erp.stock_balance(portal,product,w1); RAISE EXCEPTION 'Expected denial'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM erp.adjust_stock(actor,product,w1,10,'fixture-opening','Opening fixture'); RAISE EXCEPTION 'Expected approval block'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO settings.gsettings(setting_key,scope_type,value,change_reason) VALUES
    ('stock.require_adjustment_approval','global','false','Test direct adjustment'),
    ('stock.require_transfer_approval','global','false','Test direct transfer');
  movement:=erp.adjust_stock(actor,product,w1,10,'fixture-opening','Opening fixture');
  SELECT count(*) INTO before_audit FROM app.audit_events WHERE actor_user_id=actor;
  ASSERT erp.adjust_stock(actor,product,w1,10,'fixture-opening','Opening fixture')=movement;
  ASSERT (SELECT count(*) FROM app.audit_events WHERE actor_user_id=actor)=before_audit;
  BEGIN PERFORM erp.adjust_stock(actor,product,w1,11,'fixture-opening','Opening fixture'); RAISE EXCEPTION 'Expected key conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
  transfer_id:=erp.transfer_stock(actor,product,w1,w2,4,'fixture-transfer','Move stock');
  ASSERT erp.stock_balance(actor,product,w1)=6;
  ASSERT erp.stock_balance(actor,product,w2)=4;
  ASSERT (SELECT count(*) FROM erp.stock_movements WHERE transfer_group_id=transfer_id)=2;
  ASSERT (SELECT sum(quantity_delta) FROM erp.stock_movements WHERE transfer_group_id=transfer_id)=0;
  ASSERT erp.transfer_stock(actor,product,w1,w2,4,'fixture-transfer','Move stock')=transfer_id;
  BEGIN PERFORM erp.adjust_stock(actor,product,w1,-7,'fixture-too-low','Too much'); RAISE EXCEPTION 'Expected stock failure'; EXCEPTION WHEN check_violation THEN NULL; END;
  ASSERT NOT EXISTS(SELECT 1 FROM erp.stock_movements WHERE idempotency_key='adj:fixture-too-low');
  BEGIN PERFORM erp.transfer_stock(actor,product,w1,w1,1,'fixture-same','Invalid'); RAISE EXCEPTION 'Expected warehouse failure'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

  -- Draft snapshots/totals and optimistic edit token. No invoice or payment-posting routines.
  doc:=jsonb_build_object('order_number',actor::text,'customer_id',party,'warehouse_id',w1,'currency_code','DZD',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',2)));
  draft:=erp.save_sales_order_draft(actor,doc,'Test draft');
  result:=erp.order_totals(actor,'sales',(draft->>'id')::uuid);
  ASSERT (result->>'total')::numeric=200;
  BEGIN PERFORM erp.save_sales_order_draft(actor,doc,'Stale edit',(draft->>'id')::uuid,'2000-01-01'::timestamptz,(draft->'edit_lock'->>'lock_version')::bigint); RAISE EXCEPTION 'Expected edit conflict'; EXCEPTION WHEN serialization_failure THEN NULL; END;
  doc:=jsonb_set(doc,'{lines,0,quantity}','3');
  draft:=erp.save_sales_order_draft(actor,doc,'Edit draft',(draft->>'id')::uuid,(draft->>'updated_at')::timestamptz,(draft->'edit_lock'->>'lock_version')::bigint);
  ASSERT (erp.order_totals(actor,'sales',(draft->>'id')::uuid)->>'total')::numeric=300;
  ASSERT (erp.order_detail(actor,'sales',(draft->>'id')::uuid)->'document'->'lines'->0->>'quantity')::numeric=3;
  BEGIN PERFORM erp.save_sales_order_draft(actor,jsonb_set(jsonb_set(doc,'{lines,0,quantity}','-1'),'{order_number}',to_jsonb('negative-'||actor::text)),'Bad negative draft'); RAISE EXCEPTION 'Expected positive quantity guard'; EXCEPTION WHEN check_violation THEN NULL; WHEN unique_violation THEN RAISE EXCEPTION 'Test needs a fresh order number'; END;

  INSERT INTO erp.payments(sales_order_id,currency_code,direction,method,status,amount,idempotency_key,paid_at)
    VALUES((draft->>'id')::uuid,'DZD','receipt','cash','completed',100,'fixture-receipt',CURRENT_TIMESTAMP),
          ((draft->>'id')::uuid,'DZD','refund','cash','completed',20,'fixture-refund',CURRENT_TIMESTAMP);
  ASSERT (erp.sales_payment_balance(actor,(draft->>'id')::uuid)->>'balance')::numeric=220;
  BEGIN PERFORM erp.save_sales_order_draft(actor,doc,'Linked payment edit',(draft->>'id')::uuid,(draft->>'updated_at')::timestamptz,(draft->'edit_lock'->>'lock_version')::bigint); RAISE EXCEPTION 'Expected downstream block'; EXCEPTION WHEN check_violation THEN NULL; END;
  purchase:=erp.save_purchase_order_draft(actor,jsonb_build_object('order_number',supplier::text,'supplier_id',supplier,'warehouse_id',w1,'currency_code','DZD',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',5,'unit_cost',50))),'Test purchase');
  ASSERT (erp.order_totals(actor,'purchase',(purchase->>'id')::uuid)->>'total')::numeric=250;

  -- Own-party access requires the verified membership, not a submitted customer UUID.
  INSERT INTO auth.roles(id,code,name) VALUES(portal_role,'portal_'||replace(portal_role::text,'-',''),'Test portal');
  INSERT INTO auth.user_roles(user_id,role_id) VALUES(portal,portal_role);
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT portal_role,id,'allow','own_party','Test portal scope' FROM auth.permissions WHERE code='order.sales.read';
  BEGIN PERFORM erp.order_totals(portal,'sales',(draft->>'id')::uuid); RAISE EXCEPTION 'Expected membership denial'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO auth.party_memberships(user_id,party_type,party_id,status,can_act_on_behalf,verified_at,change_reason)
    VALUES(portal,'customer',party,'active',true,CURRENT_TIMESTAMP,'Verified test fixture');
  ASSERT (erp.order_totals(portal,'sales',(draft->>'id')::uuid)->>'total')::numeric=300;
  UPDATE auth.party_memberships SET status='suspended',can_act_on_behalf=false WHERE user_id=portal;
  BEGIN PERFORM erp.order_totals(portal,'sales',(draft->>'id')::uuid); RAISE EXCEPTION 'Expected suspended membership denial'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO auth.subject_permissions(permission_id,subject_type,user_id,effect,record_scope,change_reason)
    SELECT id,'user',actor,'deny','all','Test explicit deny' FROM auth.permissions WHERE code='stock.read';
  ASSERT auth.has_permission(actor,'stock.read','stock')=false;

  INSERT INTO auth.subject_permissions(permission_id,subject_type,customer_id,effect,record_scope,change_reason)
    SELECT id,'customer',party,'deny','own_party','Test party denial' FROM auth.permissions WHERE code='order.sales.read';
  ASSERT (erp.order_totals(actor,'sales',(draft->>'id')::uuid)->>'total')::numeric=300;
  UPDATE auth.party_memberships SET status='active',can_act_on_behalf=true WHERE user_id=portal;
  BEGIN PERFORM erp.order_totals(portal,'sales',(draft->>'id')::uuid); RAISE EXCEPTION 'Expected party-specific denial'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  -- Four strategies, independent literal expectations and fail-closed role conflicts.
  INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,is_overridable,resolution_strategy,scope_precedence,change_permission_code) VALUES
    ('test.global','test','Global resolution','boolean','true',false,'global_only',ARRAY['global'],'settings.update_global'),
    ('test.specific','test','Specific resolution','boolean','false',true,'most_specific',ARRAY['global','role','user'],'settings.update_global'),
    ('test.all','test','Restrictive resolution','boolean','true',true,'all_must_allow',ARRAY['global','user'],'settings.update_global'),
    ('test.cap','test','Minimum cap','decimal','100',true,'minimum_cap',ARRAY['global','user'],'settings.update_global');
  INSERT INTO settings.settings(setting_key,scope_type,scope_id,value,change_reason) VALUES
    ('test.specific','user',actor,'true','Test override'),('test.all','user',actor,'false','Test restriction'),('test.cap','user',actor,'40','Test cap');
  ASSERT settings.resolve(actor,'test.global')->'value'='true'::jsonb;
  ASSERT settings.resolve(actor,'test.specific')->'value'='true'::jsonb;
  ASSERT settings.resolve(actor,'test.all')->'value'='false'::jsonb;
  ASSERT settings.resolve(actor,'test.cap')->'value'='40'::jsonb;
  UPDATE settings.settings SET valid_from=CURRENT_TIMESTAMP-interval '2 hours',valid_until=CURRENT_TIMESTAMP-interval '1 hour' WHERE setting_key='test.cap';
  ASSERT settings.resolve(actor,'test.cap')->'value'='100'::jsonb;
  INSERT INTO auth.roles(id,code,name) VALUES(second_role,'second_'||replace(second_role::text,'-',''),'Conflicting role');
  INSERT INTO auth.user_roles(user_id,role_id) VALUES(actor,second_role);
  INSERT INTO settings.gsettings(setting_key,scope_type,role_id,value,change_reason) VALUES
    ('test.specific','role',role_id,'true','First role'),('test.specific','role',second_role,'false','Second role');
  BEGIN PERFORM settings.resolve(actor,'test.specific'); RAISE EXCEPTION 'Expected role conflict'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM settings.resolve(actor,'missing.setting'); RAISE EXCEPTION 'Expected missing definition failure'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,change_permission_code) VALUES
    ('test.currency','test','Currency check','currency_amount','{"amount":50,"currency":"DZD"}','settings.update_global');
  ASSERT settings.resolve(actor,'test.currency','{"currency":"DZD"}')->'value'->'amount'='50'::jsonb;
  BEGIN PERFORM settings.resolve(actor,'test.currency','{"currency":"EUR"}'); RAISE EXCEPTION 'Expected currency mismatch'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,validation_rules,change_permission_code) VALUES
    ('test.integer','test','Integer check','integer','1','{}','settings.update_global'),
    ('test.string','test','String check','string','"ok"','{"min_length":1,"max_length":5}','settings.update_global'),
    ('test.uuid','test','UUID check','uuid',to_jsonb(actor),'{}','settings.update_global'),
    ('test.object','test','Object check','object','{"name":"sample"}','{"required_keys":["name"],"allowed_keys":["name"]}','settings.update_global');
  INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,enum_values,change_permission_code)
    VALUES('test.enum','test','Enum check','enum','"a"','["a","b"]','settings.update_global');
  ASSERT settings.resolve(actor,'test.integer')->'value'='1'::jsonb;
  ASSERT settings.resolve(actor,'test.string')->'value'='"ok"'::jsonb;
  ASSERT settings.resolve(actor,'test.uuid')->'value'=to_jsonb(actor);
  ASSERT settings.resolve(actor,'test.object')->'value'='{"name":"sample"}'::jsonb;
  ASSERT settings.resolve(actor,'test.enum')->'value'='"a"'::jsonb;
  INSERT INTO settings.gsettings(setting_key,scope_type,value,change_reason) VALUES
    ('test.integer','global','1.5','Invalid integer fixture'),('test.string','global','"too long"','Invalid length fixture'),
    ('test.uuid','global','"invalid-uuid"','Invalid UUID fixture'),('test.object','global','{"unexpected":1}','Invalid object fixture'),
    ('test.enum','global','"c"','Invalid enum fixture');
  BEGIN PERFORM settings.resolve(actor,'test.integer'); RAISE EXCEPTION 'Expected integer validation'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM settings.resolve(actor,'test.string'); RAISE EXCEPTION 'Expected length validation'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM settings.resolve(actor,'test.uuid'); RAISE EXCEPTION 'Expected UUID validation'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM settings.resolve(actor,'test.object'); RAISE EXCEPTION 'Expected object validation'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM settings.resolve(actor,'test.enum'); RAISE EXCEPTION 'Expected enum validation'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,allow_null,is_overridable,resolution_strategy,scope_precedence,change_permission_code)
    VALUES('test.unset','test','Explicit unset','boolean','null',true,true,'most_specific',ARRAY['global','user'],'settings.update_global'),
      ('test.unset_restriction','test','Unset is not permission','boolean','null',true,true,'all_must_allow',ARRAY['global','user'],'settings.update_global');
  ASSERT settings.resolve(actor,'test.unset')->'value'='null'::jsonb;
  BEGIN PERFORM settings.resolve(actor,'test.unset_restriction'); RAISE EXCEPTION 'Expected restrictive unset failure'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  UPDATE settings.setting_definitions SET validation_rules='{"unknown_rule":true}' WHERE key='test.global';
  BEGIN PERFORM settings.resolve(actor,'test.global'); RAISE EXCEPTION 'Expected unsupported validation failure'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END;
$test$;
ROLLBACK;
