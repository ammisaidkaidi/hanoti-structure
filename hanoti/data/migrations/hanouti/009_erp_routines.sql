-- UNAPPLIED DECLARATIONS ONLY. Target: hanouti. No connection, execution or grants to business users.
-- SECURITY DEFINER deployment requires the restricted owner/runtime template; see ERP_ROUTINES.md.
-- Draft functions depend on the helpers in 011; finish the full unapplied baseline before use.
BEGIN;

CREATE FUNCTION erp._require_write_context(p_actor uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
PERFORM auth._require_active_actor(p_actor);
  IF p_reason IS NULL OR btrim(p_reason)='' OR length(p_reason)>2000 THEN RAISE EXCEPTION 'A nonblank reason of at most 2000 characters is required' USING ERRCODE='22023'; END IF;
  -- Product-row locks serialize ledger writers; READ COMMITTED refreshes the aggregate after waiting.
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'ERP write routines require READ COMMITTED' USING ERRCODE='25001';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION erp._require_write_context(uuid, text) FROM PUBLIC;

CREATE FUNCTION erp._audit(p_actor uuid, p_action text, p_entity_type text, p_entity_id uuid, p_metadata jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
INSERT INTO app.audit_events(source_schema,actor_user_id,action,entity_type,entity_id,metadata,occurred_at)
  VALUES ('erp',p_actor,p_action,p_entity_type,p_entity_id::text,p_metadata,clock_timestamp());
END;
$fn$;
REVOKE ALL ON FUNCTION erp._audit(uuid, text, text, uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION erp._validate_quantity(p_actor uuid, p_quantity numeric, p_context jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_places numeric;
BEGIN
IF p_quantity IS NULL OR p_quantity IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    OR p_quantity=0 OR abs(p_quantity)>=1000000000000000 OR p_quantity<>round(p_quantity,3) THEN
    RAISE EXCEPTION 'Quantity must be finite, nonzero and fit NUMERIC(18,3) exactly' USING ERRCODE='22023';
  END IF;
  v_places := settings._number(p_actor,'quantity.decimal_places',p_context);
  IF trunc(v_places)<>v_places OR v_places<0 OR v_places>3 THEN RAISE EXCEPTION 'Unsupported quantity precision' USING ERRCODE='22023'; END IF;
  IF p_quantity<>round(p_quantity,v_places::integer)
    OR (NOT settings._boolean(p_actor,'quantity.allow_fractional',p_context) AND p_quantity<>trunc(p_quantity)) THEN
    RAISE EXCEPTION 'Quantity violates the effective precision policy' USING ERRCODE='22023';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION erp._validate_quantity(uuid, numeric, jsonb) FROM PUBLIC;

CREATE FUNCTION erp.stock_balance(p_actor uuid, p_product uuid, p_warehouse uuid)
RETURNS numeric
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_balance numeric;
BEGIN
PERFORM auth._require_permission(p_actor,'stock.read','stock');
  IF NOT EXISTS(SELECT 1 FROM erp.products WHERE id=p_product AND kind='stock') OR NOT EXISTS(SELECT 1 FROM erp.warehouses WHERE id=p_warehouse) THEN
    RAISE EXCEPTION 'Stock target unavailable' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(sum(m.quantity_delta),0) INTO v_balance FROM erp.stock_movements m WHERE m.product_id=p_product AND m.warehouse_id=p_warehouse;
  RETURN v_balance;
END;
$fn$;
REVOKE ALL ON FUNCTION erp.stock_balance(uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION erp._check_stock_result(p_actor uuid, p_product uuid, p_warehouse uuid, p_delta numeric, p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_balance numeric; v_negative jsonb; v_available jsonb;
BEGIN
v_negative := settings._resolve(p_actor,'stock.allow_negative_balance',p_context);
  v_available := settings._resolve(p_actor,'stock.require_available_quantity',p_context);
  IF jsonb_typeof(v_negative->'value')<>'boolean' OR jsonb_typeof(v_available->'value')<>'boolean' THEN RAISE EXCEPTION 'Invalid stock policy type' USING ERRCODE='22023'; END IF;
  SELECT coalesce(sum(quantity_delta),0) INTO v_balance FROM erp.stock_movements WHERE product_id=p_product AND warehouse_id=p_warehouse;
  IF v_balance+p_delta<0 AND ((v_negative->>'value')::boolean IS NOT TRUE OR (v_available->>'value')::boolean) THEN
    RAISE EXCEPTION 'Insufficient stock under the effective policy' USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('before',v_balance,'after',v_balance+p_delta,'negative_balance_policy',v_negative,'available_quantity_policy',v_available);
END;
$fn$;
REVOKE ALL ON FUNCTION erp._check_stock_result(uuid, uuid, uuid, numeric, jsonb) FROM PUBLIC;

CREATE FUNCTION erp.adjust_stock(p_actor uuid, p_product uuid, p_warehouse uuid, p_delta numeric, p_key text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_existing erp.stock_movements%ROWTYPE; v_context jsonb; v_effect jsonb; v_id uuid;
BEGIN
PERFORM erp._require_write_context(p_actor,p_reason);
  PERFORM auth._require_permission(p_actor,'stock.adjust','stock');
  IF p_key IS NULL OR btrim(p_key)='' OR length(p_key)>120 THEN RAISE EXCEPTION 'Invalid idempotency key' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hanouti.stock:'||p_key,0));
  SELECT * INTO v_existing FROM erp.stock_movements WHERE idempotency_key='adj:'||p_key;
  IF FOUND THEN
    IF v_existing.kind IS DISTINCT FROM 'adjustment' OR v_existing.product_id IS DISTINCT FROM p_product
      OR v_existing.warehouse_id IS DISTINCT FROM p_warehouse OR v_existing.quantity_delta IS DISTINCT FROM p_delta
      OR v_existing.recorded_by_user_id IS DISTINCT FROM p_actor OR v_existing.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'Idempotency key conflicts with an earlier request' USING ERRCODE='23505';
    END IF;
    RETURN v_existing.id;
  END IF;
  PERFORM 1 FROM erp.products WHERE id=p_product AND is_active AND kind='stock' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stock product required' USING ERRCODE='22023'; END IF;
  PERFORM 1 FROM erp.warehouses WHERE id=p_warehouse AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active warehouse required' USING ERRCODE='22023'; END IF;
  v_context := jsonb_build_object('product',p_product,'warehouse',p_warehouse,'document_kind','stock_adjustment');
  PERFORM erp._validate_quantity(p_actor,p_delta,v_context);
  IF settings._boolean(p_actor,'stock.require_adjustment_approval',v_context) THEN
    RAISE EXCEPTION 'Approval workflow required; direct adjustment is disabled' USING ERRCODE='42501';
  END IF;
  v_effect := erp._check_stock_result(p_actor,p_product,p_warehouse,p_delta,v_context);
  INSERT INTO erp.stock_movements(product_id,warehouse_id,kind,quantity_delta,idempotency_key,reason,recorded_by_user_id,occurred_at)
  VALUES(p_product,p_warehouse,'adjustment',p_delta,'adj:'||p_key,p_reason,p_actor,clock_timestamp()) RETURNING id INTO v_id;
  PERFORM erp._audit(p_actor,'stock.adjust','stock_movement',v_id,jsonb_build_object('product_id',p_product,'warehouse_id',p_warehouse,'quantity_delta',p_delta,'reason',p_reason,'stock',v_effect));
  RETURN v_id;
END;
$fn$;
REVOKE ALL ON FUNCTION erp.adjust_stock(uuid, uuid, uuid, numeric, text, text) FROM PUBLIC;

CREATE FUNCTION erp.transfer_stock(p_actor uuid, p_product uuid, p_from uuid, p_to uuid, p_quantity numeric, p_key text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_out erp.stock_movements%ROWTYPE; v_in erp.stock_movements%ROWTYPE; v_from_context jsonb; v_to_context jsonb; v_from_effect jsonb; v_to_effect jsonb; v_group uuid;
BEGIN
PERFORM erp._require_write_context(p_actor,p_reason);
  PERFORM auth._require_permission(p_actor,'stock.transfer','stock');
  IF p_from IS NULL OR p_to IS NULL OR p_from=p_to THEN RAISE EXCEPTION 'Transfer requires two different warehouses' USING ERRCODE='22023'; END IF;
  IF p_key IS NULL OR btrim(p_key)='' OR length(p_key)>120 THEN RAISE EXCEPTION 'Invalid idempotency key' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hanouti.stock:'||p_key,0));
  SELECT * INTO v_out FROM erp.stock_movements WHERE idempotency_key='out:'||p_key;
  SELECT * INTO v_in FROM erp.stock_movements WHERE idempotency_key='in:'||p_key;
  IF v_out.id IS NOT NULL OR v_in.id IS NOT NULL THEN
    IF v_out.id IS NULL OR v_in.id IS NULL OR v_out.kind IS DISTINCT FROM 'transfer_out' OR v_in.kind IS DISTINCT FROM 'transfer_in'
      OR v_out.transfer_group_id IS NULL OR v_out.transfer_group_id IS DISTINCT FROM v_in.transfer_group_id
      OR v_out.product_id IS DISTINCT FROM p_product OR v_in.product_id IS DISTINCT FROM p_product
      OR v_out.warehouse_id IS DISTINCT FROM p_from OR v_in.warehouse_id IS DISTINCT FROM p_to
      OR v_out.quantity_delta IS DISTINCT FROM -p_quantity OR v_in.quantity_delta IS DISTINCT FROM p_quantity
      OR v_out.recorded_by_user_id IS DISTINCT FROM p_actor OR v_in.recorded_by_user_id IS DISTINCT FROM p_actor
      OR v_out.reason IS DISTINCT FROM p_reason OR v_in.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'Idempotency key conflicts with an earlier request' USING ERRCODE='23505';
    END IF;
    RETURN v_out.transfer_group_id;
  END IF;
  PERFORM 1 FROM erp.products WHERE id=p_product AND is_active AND kind='stock' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stock product required' USING ERRCODE='22023'; END IF;
  -- Ordered warehouse locks avoid inversions between opposite transfers.
  PERFORM 1 FROM erp.warehouses WHERE id IN(p_from,p_to) AND is_active ORDER BY id FOR SHARE;
  IF (SELECT count(*) FROM erp.warehouses WHERE id IN(p_from,p_to) AND is_active)<>2 THEN RAISE EXCEPTION 'Active warehouses required' USING ERRCODE='22023'; END IF;
  IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'Transfer quantity must be positive' USING ERRCODE='22023'; END IF;
  v_from_context:=jsonb_build_object('product',p_product,'warehouse',p_from,'document_kind','stock_transfer');
  v_to_context:=jsonb_build_object('product',p_product,'warehouse',p_to,'document_kind','stock_transfer');
  PERFORM erp._validate_quantity(p_actor,p_quantity,v_from_context);
  PERFORM erp._validate_quantity(p_actor,p_quantity,v_to_context);
  IF settings._boolean(p_actor,'stock.require_transfer_approval',v_from_context)
    OR settings._boolean(p_actor,'stock.require_transfer_approval',v_to_context) THEN
    RAISE EXCEPTION 'Approval workflow required; direct transfer is disabled' USING ERRCODE='42501';
  END IF;
  v_from_effect:=erp._check_stock_result(p_actor,p_product,p_from,-p_quantity,v_from_context);
  v_to_effect:=erp._check_stock_result(p_actor,p_product,p_to,p_quantity,v_to_context);
  v_group:=gen_random_uuid();
  INSERT INTO erp.stock_movements(product_id,warehouse_id,kind,quantity_delta,transfer_group_id,idempotency_key,reason,recorded_by_user_id,occurred_at)
  VALUES(p_product,p_from,'transfer_out',-p_quantity,v_group,'out:'||p_key,p_reason,p_actor,clock_timestamp()),
        (p_product,p_to,'transfer_in',p_quantity,v_group,'in:'||p_key,p_reason,p_actor,clock_timestamp());
  PERFORM erp._audit(p_actor,'stock.transfer','stock_transfer',v_group,jsonb_build_object('product_id',p_product,'from_warehouse',p_from,'to_warehouse',p_to,'quantity',p_quantity,'reason',p_reason,'source_stock',v_from_effect,'destination_stock',v_to_effect));
  RETURN v_group;
END;
$fn$;
REVOKE ALL ON FUNCTION erp.transfer_stock(uuid, uuid, uuid, uuid, numeric, text, text) FROM PUBLIC;

CREATE FUNCTION erp._save_order_draft(p_actor uuid, p_kind text, p_document jsonb, p_reason text, p_order_id uuid, p_expected_updated_at timestamptz, p_lock_version bigint)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_party_type text; v_party_key text; v_party uuid; v_warehouse uuid; v_currency text;
v_owner uuid; v_id uuid; v_old record; v_updated timestamptz; v_expected_on date;
v_snapshot jsonb; v_line jsonb; v_position integer := 0; v_base jsonb; v_context jsonb;
v_product_id uuid; v_product record; v_quantity numeric; v_price_key text; v_price numeric;
v_discount numeric; v_tax numeric; v_amount numeric; v_cap numeric; v_threshold numeric;
v_edit_lock jsonb; v_edit_version bigint; v_previous_context jsonb;
BEGIN
PERFORM erp._require_write_context(p_actor,p_reason);
  IF p_kind IS NULL OR p_kind NOT IN ('sales','purchase') OR p_document IS NULL OR jsonb_typeof(p_document)<>'object' THEN RAISE EXCEPTION 'Invalid draft document' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_document) k WHERE k NOT IN ('order_number','customer_id','supplier_id','warehouse_id','currency_code','notes','expected_on','lines')) THEN RAISE EXCEPTION 'Unsupported draft field' USING ERRCODE='22023'; END IF;
  IF (p_kind='sales' AND (p_document ? 'supplier_id' OR p_document ? 'expected_on')) OR (p_kind='purchase' AND p_document ? 'customer_id') THEN RAISE EXCEPTION 'Field belongs to another document kind' USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(p_document->'order_number') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'currency_code') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'warehouse_id') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'lines') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Draft header and lines are required' USING ERRCODE='22023'; END IF;
  IF btrim(p_document->>'order_number')='' OR length(p_document->>'order_number')>64
    OR (p_document->>'currency_code') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Invalid order number or currency' USING ERRCODE='22023'; END IF;
  IF p_document ? 'notes' AND jsonb_typeof(p_document->'notes') NOT IN ('string','null') THEN RAISE EXCEPTION 'Notes must be text or null' USING ERRCODE='22023'; END IF;
  IF length(p_document->>'notes')>4000 OR jsonb_array_length(p_document->'lines')>1000 THEN RAISE EXCEPTION 'Draft size limit exceeded' USING ERRCODE='22023'; END IF;
  v_party_type:=CASE WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END;
  v_party_key:=v_party_type||'_id';
  IF p_document ? v_party_key AND jsonb_typeof(p_document->v_party_key) NOT IN ('string','null') THEN RAISE EXCEPTION 'Invalid party field' USING ERRCODE='22023'; END IF;
  v_party:=(p_document->>v_party_key)::uuid;
  v_warehouse:=(p_document->>'warehouse_id')::uuid;
  v_currency:=p_document->>'currency_code';
  IF p_kind='purchase' AND v_party IS NULL THEN RAISE EXCEPTION 'Supplier required' USING ERRCODE='22023'; END IF;
  IF p_document ? 'expected_on' AND p_document->'expected_on'<>'null'::jsonb THEN
    IF jsonb_typeof(p_document->'expected_on')<>'string' OR (p_document->>'expected_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'Invalid expected date' USING ERRCODE='22023'; END IF;
    v_expected_on:=(p_document->>'expected_on')::date;
  END IF;
  v_owner:=p_actor;
  v_id:=p_order_id;
  IF v_id IS NOT NULL THEN
    IF p_kind='sales' THEN
      SELECT created_by_user_id,updated_at,status,order_number,customer_id,warehouse_id,currency_code
        INTO v_old FROM erp.sales_orders WHERE id=v_id FOR UPDATE;
    ELSE
      SELECT created_by_user_id,updated_at,status,order_number,supplier_id AS customer_id,warehouse_id,currency_code
        INTO v_old FROM erp.purchase_orders WHERE id=v_id FOR UPDATE;
    END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
    v_owner:=v_old.created_by_user_id;
    PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.update_draft',p_kind||'_order',v_owner,
      CASE WHEN v_old.customer_id IS NULL THEN NULL ELSE v_party_type END,v_old.customer_id);
    IF v_old.status<>'draft' THEN RAISE EXCEPTION 'Only drafts may be edited' USING ERRCODE='23514'; END IF;
    -- No supervisor bypass: both the actor and the current lock version must match.
    PERFORM erp._assert_order_edit(p_actor,p_kind,v_id,p_lock_version);
    IF p_expected_updated_at IS NULL OR p_expected_updated_at IS DISTINCT FROM v_old.updated_at THEN RAISE EXCEPTION 'Draft changed; reload before editing' USING ERRCODE='40001'; END IF;
    IF v_old.order_number IS DISTINCT FROM p_document->>'order_number' OR v_old.customer_id IS DISTINCT FROM v_party
      OR v_old.warehouse_id IS DISTINCT FROM v_warehouse OR v_old.currency_code IS DISTINCT FROM v_currency THEN
      RAISE EXCEPTION 'Draft identity, party, warehouse and currency cannot be reassigned by this routine' USING ERRCODE='22023';
    END IF;
    IF (p_kind='sales' AND EXISTS(SELECT 1 FROM erp.payments WHERE sales_order_id=v_id))
      OR (p_kind='sales' AND EXISTS(SELECT 1 FROM erp.stock_movements m JOIN erp.sales_order_items i ON i.id=m.sales_order_item_id WHERE i.sales_order_id=v_id))
      OR (p_kind='purchase' AND EXISTS(SELECT 1 FROM erp.stock_movements m JOIN erp.purchase_order_items i ON i.id=m.purchase_order_item_id WHERE i.purchase_order_id=v_id)) THEN
      RAISE EXCEPTION 'Draft has downstream records and cannot be replaced' USING ERRCODE='23514';
    END IF;
    v_updated:=greatest(clock_timestamp(),v_old.updated_at+interval '1 microsecond');
  ELSE
    IF p_expected_updated_at IS NOT NULL OR p_lock_version IS NOT NULL THEN RAISE EXCEPTION 'New drafts cannot supply an existing edit session or version' USING ERRCODE='22023'; END IF;
    PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.create_draft',p_kind||'_order',p_actor,
      CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
    v_id:=gen_random_uuid(); v_updated:=clock_timestamp();
  END IF;
  PERFORM 1 FROM erp.warehouses WHERE id=v_warehouse AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active warehouse required' USING ERRCODE='22023'; END IF;
  IF v_party IS NOT NULL THEN
    IF p_kind='sales' THEN SELECT jsonb_build_object('name',name) INTO v_snapshot FROM erp.customers WHERE id=v_party AND is_active;
    ELSE SELECT jsonb_build_object('name',name) INTO v_snapshot FROM erp.suppliers WHERE id=v_party AND is_active; END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active party required' USING ERRCODE='22023'; END IF;
  ELSE v_snapshot:='{}'::jsonb;
  END IF;
  v_previous_context:=erp._set_edit_context(p_actor,p_kind,v_id,p_lock_version,CASE WHEN p_order_id IS NULL THEN 'create' ELSE 'write' END,p_reason);
  IF p_order_id IS NULL THEN
    IF p_kind='sales' THEN
      INSERT INTO erp.sales_orders(id,order_number,customer_id,warehouse_id,currency_code,customer_snapshot,notes,created_by_user_id,updated_at)
        VALUES(v_id,p_document->>'order_number',v_party,v_warehouse,v_currency,v_snapshot,p_document->>'notes',p_actor,v_updated) RETURNING lock_version INTO v_edit_version;
    ELSE
      INSERT INTO erp.purchase_orders(id,order_number,supplier_id,warehouse_id,currency_code,supplier_snapshot,notes,expected_on,created_by_user_id,updated_at)
        VALUES(v_id,p_document->>'order_number',v_party,v_warehouse,v_currency,v_snapshot,p_document->>'notes',v_expected_on,p_actor,v_updated) RETURNING lock_version INTO v_edit_version;
    END IF;
  ELSE
    IF p_kind='sales' THEN
      DELETE FROM erp.sales_order_items WHERE sales_order_id=v_id;
      UPDATE erp.sales_orders SET notes=p_document->>'notes',updated_at=v_updated WHERE id=v_id;
    ELSE
      DELETE FROM erp.purchase_order_items WHERE purchase_order_id=v_id;
      UPDATE erp.purchase_orders SET notes=p_document->>'notes',expected_on=v_expected_on,updated_at=v_updated WHERE id=v_id;
    END IF;
  END IF;
  IF p_order_id IS NULL THEN
    -- The header INSERT trigger reserved the new draft; child writes use that version.
    PERFORM set_config('hanouti.lock_version',v_edit_version::text,true);
  ELSE v_edit_version:=p_lock_version;
  END IF;
  v_base:=jsonb_build_object('warehouse',v_warehouse,'currency',v_currency,'document_kind',p_kind||'_order');
  IF v_party IS NOT NULL THEN v_base:=v_base||jsonb_build_object(v_party_type,v_party); END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_document->'lines') LOOP
    v_position:=v_position+1;
    IF jsonb_typeof(v_line)<>'object' THEN RAISE EXCEPTION 'Each draft line must be an object' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_line) k WHERE k NOT IN ('product_id','quantity','unit_price','unit_cost','discount_amount','tax_amount'))
      OR (p_kind='sales' AND v_line ? 'unit_cost') OR (p_kind='purchase' AND v_line ? 'unit_price') THEN RAISE EXCEPTION 'Unsupported draft line field' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(v_line->'product_id') IS DISTINCT FROM 'string' OR coalesce(jsonb_typeof(v_line->'quantity'),'missing') NOT IN ('number','string') THEN RAISE EXCEPTION 'Product and decimal quantity required' USING ERRCODE='22023'; END IF;
    v_product_id:=(v_line->>'product_id')::uuid;
    SELECT id,sku,name,full_name,unit_code,sale_price,currency_code INTO v_product FROM erp.products WHERE id=v_product_id AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active product required' USING ERRCODE='22023'; END IF;
    v_context:=v_base||jsonb_build_object('product',v_product_id);
    IF jsonb_typeof(v_line->'quantity')='string' AND (v_line->>'quantity') !~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN RAISE EXCEPTION 'Invalid decimal quantity string' USING ERRCODE='22023'; END IF;
    v_quantity:=(v_line->>'quantity')::numeric;
    PERFORM erp._validate_quantity(p_actor,v_quantity,v_context);
    IF v_quantity<=0 THEN RAISE EXCEPTION 'Order quantities must be positive; use a separately reviewed return workflow' USING ERRCODE='23514'; END IF;
    v_price_key:=CASE WHEN p_kind='sales' THEN 'unit_price' ELSE 'unit_cost' END;
    IF v_line ? v_price_key THEN
      IF jsonb_typeof(v_line->v_price_key) NOT IN ('number','string') OR (jsonb_typeof(v_line->v_price_key)='string' AND (v_line->>v_price_key) !~ '^[+-]?[0-9]+([.][0-9]+)?$') THEN RAISE EXCEPTION 'Price or cost must be a decimal' USING ERRCODE='22023'; END IF;
      v_price:=(v_line->>v_price_key)::numeric;
    ELSIF p_kind='sales' THEN v_price:=v_product.sale_price;
    ELSE RAISE EXCEPTION 'Purchase unit_cost required' USING ERRCODE='22023'; END IF;
    IF (v_line ? 'discount_amount' AND (jsonb_typeof(v_line->'discount_amount') NOT IN ('number','string') OR (jsonb_typeof(v_line->'discount_amount')='string' AND (v_line->>'discount_amount') !~ '^[+-]?[0-9]+([.][0-9]+)?$')))
      OR (v_line ? 'tax_amount' AND (jsonb_typeof(v_line->'tax_amount') NOT IN ('number','string') OR (jsonb_typeof(v_line->'tax_amount')='string' AND (v_line->>'tax_amount') !~ '^[+-]?[0-9]+([.][0-9]+)?$'))) THEN RAISE EXCEPTION 'Discount and tax amounts must be decimals' USING ERRCODE='22023'; END IF;
    v_discount:=coalesce((v_line->>'discount_amount')::numeric,0);
    v_tax:=coalesce((v_line->>'tax_amount')::numeric,0);
    FOREACH v_amount IN ARRAY ARRAY[v_price,v_discount,v_tax] LOOP
      IF v_amount IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) OR v_amount<0 OR v_amount>=100000000000000 OR v_amount<>round(v_amount,4) THEN RAISE EXCEPTION 'Money must fit nonnegative NUMERIC(18,4) exactly' USING ERRCODE='22023'; END IF;
    END LOOP;
    IF v_price=0 AND NOT settings._boolean(p_actor,'pricing.allow_zero_unit_price',v_context) THEN RAISE EXCEPTION 'Zero price or cost is disabled' USING ERRCODE='23514'; END IF;
    IF p_kind='sales' THEN
      IF v_product.currency_code<>v_currency THEN RAISE EXCEPTION 'No currency conversion is configured for catalog sales prices' USING ERRCODE='22023'; END IF;
      IF v_price<>v_product.sale_price THEN
        IF NOT settings._boolean(p_actor,'pricing.allow_manual_price',v_context) THEN RAISE EXCEPTION 'Manual sales pricing is disabled' USING ERRCODE='42501'; END IF;
        PERFORM auth._require_permission(p_actor,'pricing.override','pricing',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
      END IF;
    END IF;
    IF v_discount>v_quantity*v_price THEN RAISE EXCEPTION 'Discount exceeds gross line value' USING ERRCODE='23514'; END IF;
    IF v_discount>0 THEN
      PERFORM auth._require_permission(p_actor,'discount.apply','pricing',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
      v_cap:=settings._number(p_actor,'discount.max_line_percent',v_context||jsonb_build_object('unit','percent'));
      v_threshold:=settings._number(p_actor,'discount.require_approval_above_percent',v_context||jsonb_build_object('unit','percent'));
      IF v_cap<0 OR v_cap>100 OR v_threshold<0 OR v_threshold>100 THEN RAISE EXCEPTION 'Invalid discount limit' USING ERRCODE='22023'; END IF;
      IF v_discount*100>v_quantity*v_price*v_cap THEN RAISE EXCEPTION 'Discount exceeds effective limit' USING ERRCODE='23514'; END IF;
      IF v_discount*100>v_quantity*v_price*v_threshold THEN RAISE EXCEPTION 'Discount approval workflow required' USING ERRCODE='42501'; END IF;
    END IF;
    IF v_tax>0 THEN
      PERFORM auth._require_permission(p_actor,'order.tax.edit','order',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
    END IF;
    IF p_kind='sales' THEN
      INSERT INTO erp.sales_order_items(sales_order_id,line_number,product_id,sku_snapshot,full_name,description,unit_code,quantity,unit_price,discount_amount,tax_amount)
        VALUES(v_id,v_position,v_product_id,v_product.sku,v_product.full_name,v_product.name,v_product.unit_code,v_quantity,v_price,v_discount,v_tax);
    ELSE
      INSERT INTO erp.purchase_order_items(purchase_order_id,line_number,product_id,sku_snapshot,full_name,description,unit_code,quantity,unit_cost,discount_amount,tax_amount)
        VALUES(v_id,v_position,v_product_id,v_product.sku,v_product.full_name,v_product.name,v_product.unit_code,v_quantity,v_price,v_discount,v_tax);
    END IF;
  END LOOP;
  -- Recheck immediately before success: a long-running save may outlast its lock renewal.
  v_edit_lock:=erp._assert_order_edit(p_actor,p_kind,v_id,v_edit_version);
  v_updated:=(v_edit_lock->>'updated_at')::timestamptz;
  PERFORM erp._audit(p_actor,'order.'||p_kind||CASE WHEN p_order_id IS NULL THEN '.create_draft' ELSE '.update_draft' END,
    p_kind||'_order',v_id,jsonb_build_object('line_count',v_position,'reason',p_reason,'updated_at',v_updated));
  PERFORM erp._restore_edit_context(v_previous_context);
  RETURN jsonb_build_object('id',v_id,'status','draft','updated_at',v_updated,'line_count',v_position,'edit_lock',v_edit_lock);
END;
$fn$;
REVOKE ALL ON FUNCTION erp._save_order_draft(uuid, text, jsonb, text, uuid, timestamptz, bigint) FROM PUBLIC;

CREATE FUNCTION erp.save_sales_order_draft(p_actor uuid, p_document jsonb, p_reason text, p_order_id uuid DEFAULT NULL, p_expected_updated_at timestamptz DEFAULT NULL, p_lock_version bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
RETURN erp._save_order_draft(p_actor,'sales',p_document,p_reason,p_order_id,p_expected_updated_at,p_lock_version);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.save_sales_order_draft(uuid, jsonb, text, uuid, timestamptz, bigint) FROM PUBLIC;

CREATE FUNCTION erp.save_purchase_order_draft(p_actor uuid, p_document jsonb, p_reason text, p_order_id uuid DEFAULT NULL, p_expected_updated_at timestamptz DEFAULT NULL, p_lock_version bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
RETURN erp._save_order_draft(p_actor,'purchase',p_document,p_reason,p_order_id,p_expected_updated_at,p_lock_version);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.save_purchase_order_draft(uuid, jsonb, text, uuid, timestamptz, bigint) FROM PUBLIC;

CREATE FUNCTION erp.order_totals(p_actor uuid, p_kind text, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order record; v_totals record;
BEGIN
IF p_kind='sales' THEN
    SELECT id,created_by_user_id,customer_id AS party_id,currency_code,status,updated_at INTO v_order FROM erp.sales_orders WHERE id=p_order_id FOR SHARE;
  ELSIF p_kind='purchase' THEN
    SELECT id,created_by_user_id,supplier_id AS party_id,currency_code,status,updated_at INTO v_order FROM erp.purchase_orders WHERE id=p_order_id FOR SHARE;
  ELSE RAISE EXCEPTION 'Unsupported order kind' USING ERRCODE='22023'; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
  PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.read',p_kind||'_order',v_order.created_by_user_id,
    CASE WHEN v_order.party_id IS NULL THEN NULL WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END,v_order.party_id);
  IF p_kind='sales' THEN
    SELECT count(*) AS lines,coalesce(sum(quantity*unit_price),0) AS gross,coalesce(sum(discount_amount),0) AS discount,
      coalesce(sum(tax_amount),0) AS tax,coalesce(sum(line_total),0) AS total INTO v_totals FROM erp.sales_order_items WHERE sales_order_id=p_order_id;
  ELSE
    SELECT count(*) AS lines,coalesce(sum(quantity*unit_cost),0) AS gross,coalesce(sum(discount_amount),0) AS discount,
      coalesce(sum(tax_amount),0) AS tax,coalesce(sum(line_total),0) AS total INTO v_totals FROM erp.purchase_order_items WHERE purchase_order_id=p_order_id;
  END IF;
  RETURN jsonb_build_object('id',p_order_id,'kind',p_kind,'currency',v_order.currency_code,'status',v_order.status,'updated_at',v_order.updated_at,
    'line_count',v_totals.lines,'gross',v_totals.gross::text,'discount',v_totals.discount::text,'tax',v_totals.tax::text,'total',v_totals.total::text);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.order_totals(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION erp.order_detail(p_actor uuid, p_kind text, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_totals jsonb; v_header jsonb; v_lines jsonb; v_snapshots jsonb;
BEGIN
v_totals:=erp.order_totals(p_actor,p_kind,p_order_id);
  IF p_kind='sales' THEN
    SELECT jsonb_build_object('order_number',order_number,'customer_id',customer_id,'warehouse_id',warehouse_id,'currency_code',currency_code,'notes',notes)
      INTO v_header FROM erp.sales_orders WHERE id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity::text,'unit_price',unit_price::text,'discount_amount',discount_amount::text,'tax_amount',tax_amount::text) ORDER BY line_number),'[]'::jsonb)
      INTO v_lines FROM erp.sales_order_items WHERE sales_order_id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'line_number',line_number,'product_id',product_id,'full_name',full_name) ORDER BY line_number),'[]'::jsonb)
      INTO v_snapshots FROM erp.sales_order_items WHERE sales_order_id=p_order_id;
  ELSE
    SELECT jsonb_build_object('order_number',order_number,'supplier_id',supplier_id,'warehouse_id',warehouse_id,'currency_code',currency_code,'notes',notes,'expected_on',expected_on)
      INTO v_header FROM erp.purchase_orders WHERE id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity::text,'unit_cost',unit_cost::text,'discount_amount',discount_amount::text,'tax_amount',tax_amount::text) ORDER BY line_number),'[]'::jsonb)
      INTO v_lines FROM erp.purchase_order_items WHERE purchase_order_id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'line_number',line_number,'product_id',product_id,'full_name',full_name) ORDER BY line_number),'[]'::jsonb)
      INTO v_snapshots FROM erp.purchase_order_items WHERE purchase_order_id=p_order_id;
  END IF;
  RETURN jsonb_build_object('summary',v_totals,'document',v_header||jsonb_build_object('lines',v_lines),'item_snapshots',v_snapshots);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.order_detail(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION erp.sales_payment_balance(p_actor uuid, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_totals jsonb; v_order record; v_receipts numeric; v_refunds numeric;
BEGIN
v_totals:=erp.order_totals(p_actor,'sales',p_order_id);
  SELECT created_by_user_id,customer_id INTO v_order FROM erp.sales_orders WHERE id=p_order_id;
  PERFORM auth._require_permission(p_actor,'payment.read','payment',v_order.created_by_user_id,
    CASE WHEN v_order.customer_id IS NULL THEN NULL ELSE 'customer' END,v_order.customer_id);
  SELECT coalesce(sum(amount) FILTER(WHERE direction='receipt'),0),coalesce(sum(amount) FILTER(WHERE direction='refund'),0)
    INTO v_receipts,v_refunds FROM erp.payments WHERE sales_order_id=p_order_id AND status='completed';
  RETURN jsonb_build_object('order_id',p_order_id,'currency',v_totals->>'currency','order_total',v_totals->'total',
    'completed_receipts',v_receipts::text,'completed_refunds',v_refunds::text,'net_paid',(v_receipts-v_refunds)::text,
    'balance',((v_totals->>'total')::numeric-v_receipts+v_refunds)::text);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.sales_payment_balance(uuid, uuid) FROM PUBLIC;

COMMIT;
