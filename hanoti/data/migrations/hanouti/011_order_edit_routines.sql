-- UNAPPLIED DECLARATIONS ONLY. Fresh baseline; apply all files before enabling application access.
-- SECURITY DEFINER functions require reviewed owner/runtime privileges.
BEGIN;

CREATE FUNCTION erp._lock_edit_order(p_kind text, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order record;
BEGIN
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
END;
$fn$;
REVOKE ALL ON FUNCTION erp._lock_edit_order(text, uuid) FROM PUBLIC;

CREATE FUNCTION erp._assert_order_edit(p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order jsonb;
BEGIN
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
END;
$fn$;
REVOKE ALL ON FUNCTION erp._assert_order_edit(uuid, text, uuid, bigint) FROM PUBLIC;

CREATE FUNCTION erp.open_order_edit(p_actor uuid, p_kind text, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order jsonb; v_previous jsonb; v_result jsonb; v_version bigint;
BEGIN
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
END;
$fn$;
REVOKE ALL ON FUNCTION erp.open_order_edit(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION erp.renew_order_edit(p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_previous jsonb; v_result jsonb;
BEGIN
PERFORM erp._require_write_context(p_actor,'Renew draft');
  PERFORM erp._assert_order_edit(p_actor,p_kind,p_order_id,p_lock_version);
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,p_lock_version,'renew','Renew draft');
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_at=clock_timestamp() WHERE id=p_order_id;
  ELSE UPDATE erp.purchase_orders SET locked_at=clock_timestamp() WHERE id=p_order_id; END IF;
  v_result:=erp._assert_order_edit(p_actor,p_kind,p_order_id,p_lock_version);
  PERFORM erp._restore_edit_context(v_previous);
  RETURN v_result;
END;
$fn$;
REVOKE ALL ON FUNCTION erp.renew_order_edit(uuid, text, uuid, bigint) FROM PUBLIC;

CREATE FUNCTION erp.close_order_edit(p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint, p_reason text DEFAULT 'Editing finished')
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order jsonb; v_previous jsonb; v_version bigint;
BEGIN
PERFORM erp._require_write_context(p_actor,p_reason);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF v_order->>'locked_by' IS NULL THEN RAISE EXCEPTION 'No editing lock to close' USING ERRCODE='55000'; END IF;
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,p_lock_version,'close',p_reason);
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version;
  ELSE UPDATE erp.purchase_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version; END IF;
  PERFORM erp._restore_edit_context(v_previous);
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'closed',true,'lock_version',v_version::text);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.close_order_edit(uuid, text, uuid, bigint, text) FROM PUBLIC;

CREATE FUNCTION erp.force_close_order_edit(p_actor uuid, p_kind text, p_order_id uuid, p_lock_version bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order jsonb; v_previous jsonb; v_version bigint;
BEGIN
PERFORM erp._require_write_context(p_actor,p_reason);
  v_order:=erp._lock_edit_order(p_kind,p_order_id);
  IF v_order->>'locked_by' IS NULL THEN RAISE EXCEPTION 'No editing lock to close' USING ERRCODE='55000'; END IF;
  v_previous:=erp._set_edit_context(p_actor,p_kind,p_order_id,p_lock_version,'force_close',p_reason);
  IF p_kind='sales' THEN UPDATE erp.sales_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version;
  ELSE UPDATE erp.purchase_orders SET locked_by=NULL,locked_at=NULL WHERE id=p_order_id RETURNING lock_version INTO v_version; END IF;
  PERFORM erp._restore_edit_context(v_previous);
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'closed',true,'lock_version',v_version::text);
END;
$fn$;
REVOKE ALL ON FUNCTION erp.force_close_order_edit(uuid, text, uuid, bigint, text) FROM PUBLIC;

CREATE FUNCTION erp.order_edit_status(p_actor uuid, p_kind text, p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_order record; v_active boolean;
BEGIN
PERFORM erp.order_totals(p_actor,p_kind,p_order_id);
  IF p_kind='sales' THEN SELECT frozen,locked_by,locked_at,lock_version INTO v_order FROM erp.sales_orders WHERE id=p_order_id;
  ELSE SELECT frozen,locked_by,locked_at,lock_version INTO v_order FROM erp.purchase_orders WHERE id=p_order_id; END IF;
  v_active:=NOT v_order.frozen AND v_order.locked_by IS NOT NULL AND v_order.locked_at>clock_timestamp()-interval '5 minutes';
  RETURN jsonb_build_object('order_id',p_order_id,'kind',p_kind,'frozen',v_order.frozen,'is_locked',coalesce(v_active,false),
    'locked_by',CASE WHEN v_active THEN v_order.locked_by END,'locked_at',v_order.locked_at,
    'lock_version',v_order.lock_version::text,'expires_at',v_order.locked_at+interval '5 minutes');
END;
$fn$;
REVOKE ALL ON FUNCTION erp.order_edit_status(uuid, text, uuid) FROM PUBLIC;

-- Trigger order is intentional: metadata/frozen protection before order-specific checks.
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.roles
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.permissions
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.user_roles
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.role_permissions
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.sessions
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.password_reset_tokens
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.email_verification_tokens
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.categories
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.brands
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.products
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.customers
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.suppliers
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.warehouses
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.sales_orders
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.sales_order_items
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.purchase_order_items
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.payments
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON erp.stock_movements
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON app.user_preferences
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON app.files
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON app.notifications
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON app.feature_flags
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON app.audit_events
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON settings.setting_definitions
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON settings.gsettings
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON settings.settings
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.party_memberships
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER a_row_metadata BEFORE INSERT OR UPDATE OR DELETE ON auth.subject_permissions
  FOR EACH ROW EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER b_order_write BEFORE INSERT OR UPDATE OR DELETE ON erp.sales_orders
  FOR EACH ROW EXECUTE FUNCTION erp._order_write_guard();
CREATE TRIGGER b_order_write BEFORE INSERT OR UPDATE OR DELETE ON erp.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION erp._order_write_guard();
CREATE TRIGGER b_order_item_write BEFORE INSERT OR UPDATE OR DELETE ON erp.sales_order_items
  FOR EACH ROW EXECUTE FUNCTION erp._order_item_guard();
CREATE TRIGGER b_order_item_write BEFORE INSERT OR UPDATE OR DELETE ON erp.purchase_order_items
  FOR EACH ROW EXECUTE FUNCTION erp._order_item_guard();

-- TRUNCATE does not fire row triggers; deny it explicitly.
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.users
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.roles
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.permissions
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.user_roles
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.role_permissions
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.sessions
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.password_reset_tokens
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.email_verification_tokens
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.categories
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.brands
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.products
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.customers
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.suppliers
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.warehouses
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.sales_orders
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.sales_order_items
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.purchase_orders
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.purchase_order_items
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.payments
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON erp.stock_movements
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON app.user_preferences
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON app.files
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON app.notifications
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON app.feature_flags
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON app.audit_events
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON settings.setting_definitions
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON settings.gsettings
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON settings.settings
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.party_memberships
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();
CREATE TRIGGER z_no_truncate BEFORE TRUNCATE ON auth.subject_permissions
  FOR EACH STATEMENT EXECUTE FUNCTION auth._row_metadata_guard();

CREATE TRIGGER b_product_full_name BEFORE INSERT OR UPDATE ON erp.products
  FOR EACH ROW EXECUTE FUNCTION erp._product_full_name_guard();

COMMIT;
