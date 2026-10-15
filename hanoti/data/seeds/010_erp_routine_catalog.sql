-- OPTIONAL UNAPPLIED CATALOG ONLY. Apply after 001..011 if approved.
-- No users, auth.roles assignments, role_permissions or subject_permissions are inserted.
-- Inserts missing definitions only; existing administrator configuration is never overwritten.
-- Review conflicting existing definitions before deployment. Absence/invalid policy fails closed.
BEGIN;
INSERT INTO auth.permissions(code,description,resource_type,supported_scopes,risk_level,is_delegable) VALUES
('order.sales.read','ERP routine: order.sales.read','sales_order',ARRAY['self','own_party','all']::text[],'normal',false),
('order.sales.create_draft','ERP routine: order.sales.create_draft','sales_order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('order.sales.update_draft','ERP routine: order.sales.update_draft','sales_order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('order.purchase.read','ERP routine: order.purchase.read','purchase_order',ARRAY['self','own_party','all']::text[],'normal',false),
('order.purchase.create_draft','ERP routine: order.purchase.create_draft','purchase_order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('order.purchase.update_draft','ERP routine: order.purchase.update_draft','purchase_order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('stock.read','ERP routine: stock.read','stock',ARRAY['all']::text[],'normal',false),
('stock.adjust','ERP routine: stock.adjust','stock',ARRAY['all']::text[],'sensitive',false),
('stock.transfer','ERP routine: stock.transfer','stock',ARRAY['all']::text[],'sensitive',false),
('pricing.override','ERP routine: pricing.override','pricing',ARRAY['self','own_party','all']::text[],'sensitive',false),
('discount.apply','ERP routine: discount.apply','pricing',ARRAY['self','own_party','all']::text[],'sensitive',false),
('order.tax.edit','ERP routine: order.tax.edit','order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('payment.read','ERP routine: payment.read','payment',ARRAY['self','own_party','all']::text[],'normal',false),
('settings.read','ERP routine: settings.read','settings',ARRAY['all']::text[],'normal',false),
('settings.update_global','ERP routine: settings.update_global','settings',ARRAY['all']::text[],'sensitive',false),
('settings.update_role','ERP routine: settings.update_role','settings',ARRAY['all']::text[],'sensitive',false),
('settings.update_scoped','ERP routine: settings.update_scoped','settings',ARRAY['all']::text[],'sensitive',false)
ON CONFLICT (code) DO NOTHING;

-- Explicit direct-header deletion authority is separate from editing; no grants are assigned.
INSERT INTO auth.permissions(code,description,resource_type,supported_scopes,risk_level,is_delegable) VALUES
('order.sales.delete_draft','Delete an empty, unfrozen, actor-locked sales draft','sales_order',ARRAY['self','own_party','all']::text[],'sensitive',false),
('order.purchase.delete_draft','Delete an empty, unfrozen, actor-locked purchase draft','purchase_order',ARRAY['self','own_party','all']::text[],'sensitive',false)
ON CONFLICT (code) DO NOTHING;

-- Supervisors may close another editing session, but reopening still needs update_draft.
INSERT INTO auth.permissions(code,description,resource_type,supported_scopes,risk_level,is_delegable) VALUES
('order.sales.force_close_edit','Force-close a sales draft editing session','sales_order',ARRAY['all']::text[],'sensitive',false),
('order.purchase.force_close_edit','Force-close a purchase draft editing session','purchase_order',ARRAY['all']::text[],'sensitive',false)
ON CONFLICT (code) DO NOTHING;

INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,minimum_value,maximum_value,unit,change_permission_code) VALUES
('quantity.allow_fractional','quantity','Allow fractional quantities subject to precision.','boolean','true'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('quantity.decimal_places','quantity','Quantity scale; cannot exceed NUMERIC(18,3).','integer','3'::jsonb,0,3,NULL,'settings.update_global'),
('stock.allow_negative_balance','stock','Permit resulting on-hand below zero only if available-quantity policy also permits.','boolean','false'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('stock.require_available_quantity','stock','Reject resulting negative stock even if negative-balance policy permits it.','boolean','true'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('stock.require_adjustment_approval','stock','When true, direct adjustment is blocked until an approval workflow exists.','boolean','true'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('stock.require_transfer_approval','stock','When true at either warehouse, direct transfer is blocked until an approval workflow exists.','boolean','true'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('pricing.allow_zero_unit_price','pricing','Allow zero draft sale price or purchase cost; negative values never allowed.','boolean','false'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('pricing.allow_manual_price','pricing','Allow manual sale price only with pricing.override permission.','boolean','false'::jsonb,NULL,NULL,NULL,'settings.update_global'),
('discount.max_line_percent','discount','Maximum permitted draft line discount percentage.','decimal','0'::jsonb,0,100,'percent','settings.update_global'),
('discount.require_approval_above_percent','discount','Discounts above this percentage are blocked until approval workflow exists.','decimal','0'::jsonb,0,100,'percent','settings.update_global')
ON CONFLICT (key) DO NOTHING;
COMMIT;
