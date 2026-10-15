-- UNEXECUTED assertions. Fresh disposable PostgreSQL database only: baseline 001..011 + catalog.
-- Provisioning/test administrator; never run automatically or against production.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DO $test$
DECLARE
  actor uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid(); brand uuid:=gen_random_uuid();
  product uuid:=gen_random_uuid(); minimal_product uuid:=gen_random_uuid(); warehouse uuid:=gen_random_uuid();
  customer uuid:=gen_random_uuid(); supplier uuid:=gen_random_uuid(); order_id uuid; line_id uuid;
  brand_name text; initial_name text; current_name text; saved_name text;
  doc jsonb; sales jsonb; purchase jsonb; detail jsonb; previous jsonb; expected_time timestamptz;
BEGIN
  INSERT INTO auth.users(id,email,display_name,status) VALUES(actor,actor||'@example.test','Name fixture','active');
  INSERT INTO auth.roles(id,code,name) VALUES(role_id,'names_'||replace(role_id::text,'-',''),'Name fixture');
  INSERT INTO auth.user_roles(user_id,role_id) VALUES(actor,role_id);
  INSERT INTO auth.role_permissions(role_id,permission_id,effect,record_scope,change_reason)
    SELECT role_id,id,'allow','all','Disposable name fixture' FROM auth.permissions WHERE code IN
      ('order.sales.create_draft','order.sales.update_draft','order.sales.read','order.purchase.create_draft','order.purchase.read');
  INSERT INTO erp.customers(id,code,name) VALUES(customer,customer::text,'Name customer');
  INSERT INTO erp.suppliers(id,code,name) VALUES(supplier,supplier::text,'Name supplier');
  INSERT INTO erp.warehouses(id,code,name) VALUES(warehouse,warehouse::text,'Name warehouse');
  brand_name:='Brand '||brand::text;
  INSERT INTO erp.brands(id,name) VALUES(brand,brand_name);
  INSERT INTO erp.products(id,sku,abbreviation,name,full_name,attributes,material,dimensions,color,brand_id,series,made_in,quality,reference,currency_code,sale_price)
    VALUES(product,product::text,' DR ','Drill','Caller spoof','Cordless','Steel','20 mm','Black',brand,'X1','Algeria','A','REF-1','DZD',100);
  initial_name:='DR Drill Cordless Steel 20 mm Black '||brand_name||' /X1 Algeria A REF-1';
  ASSERT (SELECT full_name=initial_name FROM erp.products WHERE id=product);
  INSERT INTO erp.products(id,sku,name,currency_code,sale_price) VALUES(minimal_product,minimal_product::text,' Solo ','DZD',100);
  ASSERT (SELECT full_name='Solo' FROM erp.products WHERE id=minimal_product);

  doc:=jsonb_build_object('order_number','FN-S-'||product::text,'customer_id',customer,'warehouse_id',warehouse,'currency_code','DZD',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity','2')));
  sales:=erp.save_sales_order_draft(actor,doc,'Create named sales line');
  order_id:=(sales->>'id')::uuid;
  SELECT id INTO line_id FROM erp.sales_order_items WHERE sales_order_id=order_id;
  ASSERT (SELECT full_name=initial_name FROM erp.sales_order_items WHERE id=line_id);
  purchase:=erp.save_purchase_order_draft(actor,jsonb_build_object('order_number','FN-P-'||product::text,'supplier_id',supplier,
    'warehouse_id',warehouse,'currency_code','DZD','lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity','1','unit_cost','80'))),'Create named purchase line');
  ASSERT (SELECT full_name=initial_name FROM erp.purchase_order_items WHERE purchase_order_id=(purchase->>'id')::uuid);
  detail:=erp.order_detail(actor,'sales',order_id);
  ASSERT detail->'item_snapshots'->0->>'full_name'=initial_name;
  ASSERT NOT (detail->'document'->'lines'->0 ? 'full_name');

  UPDATE erp.products SET name='Drill II',attributes=repeat('x',700) WHERE id=product;
  SELECT full_name INTO current_name FROM erp.products WHERE id=product;
  ASSERT length(current_name)>500 AND current_name<>initial_name;
  ASSERT (SELECT full_name=initial_name FROM erp.sales_order_items WHERE id=line_id);
  ASSERT (SELECT full_name=initial_name FROM erp.purchase_order_items WHERE purchase_order_id=(purchase->>'id')::uuid);
  UPDATE erp.products SET frozen=true WHERE id=product;
  BEGIN UPDATE erp.products SET name='Blocked' WHERE id=product; RAISE EXCEPTION 'Expected frozen product rejection'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  ASSERT (SELECT full_name=current_name FROM erp.products WHERE id=product);

  previous:=erp._set_edit_context(actor,'sales',order_id,(sales->'edit_lock'->>'lock_version')::bigint,'write','Test stored name protection');
  UPDATE erp.sales_order_items SET quantity=3 WHERE id=line_id;
  ASSERT (SELECT full_name=initial_name FROM erp.sales_order_items WHERE id=line_id);
  BEGIN UPDATE erp.sales_order_items SET full_name='Rewritten' WHERE id=line_id; RAISE EXCEPTION 'Expected snapshot rewrite rejection'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  -- A frozen, active product remains usable; the item captures its stored label, ignoring supplied text.
  INSERT INTO erp.sales_order_items(sales_order_id,line_number,product_id,sku_snapshot,full_name,description,unit_code,quantity,unit_price)
    VALUES(order_id,2,product,product::text,'Spoofed item','Drill II','each',1,100) RETURNING full_name INTO saved_name;
  ASSERT saved_name=current_name;
  PERFORM erp._restore_edit_context(previous);
  UPDATE erp.products SET frozen=false WHERE id=product;

  SELECT updated_at INTO expected_time FROM erp.sales_orders WHERE id=order_id;
  sales:=erp.save_sales_order_draft(actor,doc,'Recreate items with latest product name',order_id,expected_time,(sales->'edit_lock'->>'lock_version')::bigint);
  ASSERT (SELECT full_name=current_name FROM erp.sales_order_items WHERE sales_order_id=order_id);
  ASSERT (SELECT full_name=initial_name FROM erp.purchase_order_items WHERE purchase_order_id=(purchase->>'id')::uuid);

  -- Shared brand rename alone is not a product-row update; rebuilding occurs on the next ordinary product edit.
  UPDATE erp.brands SET name=brand_name||' Renamed' WHERE id=brand;
  ASSERT (SELECT full_name=current_name FROM erp.products WHERE id=product);
  UPDATE erp.products SET full_name='Another spoof' WHERE id=product;
  ASSERT (SELECT full_name<>current_name AND full_name<>'Another spoof' AND position('Renamed' in full_name)>0 FROM erp.products WHERE id=product);
  ASSERT (SELECT full_name=current_name FROM erp.sales_order_items WHERE sales_order_id=order_id);
END;
$test$;
ROLLBACK;
-- Still requires live separate-login ACL checks and concurrent product edits versus order-item creation.
