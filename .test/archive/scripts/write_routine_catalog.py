from pathlib import Path
import json
root=Path('/home/user/hanouti/data')
permissions=[]
for kind in ('sales','purchase'):
 for action in ('read','create_draft','update_draft'):
  permissions.append((f'order.{kind}.{action}',f'{kind}_order',['self','own_party','all']))
for action in ('read','adjust','transfer'):permissions.append((f'stock.{action}','stock',['all']))
permissions += [('pricing.override','pricing',['self','own_party','all']),('discount.apply','pricing',['self','own_party','all']),('order.tax.edit','order',['self','own_party','all']),('payment.read','payment',['self','own_party','all'])]
for action in ('read','update_global','update_role','update_scoped'):permissions.append((f'settings.{action}','settings',['all']))
def sql(x):return "'"+str(x).replace("'","''")+"'"
s='''-- OPTIONAL UNAPPLIED CATALOG ONLY. Apply after 001..009 if approved.
-- No users, auth.roles assignments, role_permissions or subject_permissions are inserted.
-- Inserts missing definitions only; existing administrator configuration is never overwritten.
-- Review conflicting existing definitions before deployment. Absence/invalid policy fails closed.
BEGIN;
INSERT INTO auth.permissions(code,description,resource_type,supported_scopes,risk_level,is_delegable) VALUES
'''
s+=',\n'.join('('+','.join([sql(code),sql('ERP routine: '+code),sql(resource),"ARRAY["+','.join(sql(x) for x in scopes)+"]::text[]",sql('normal' if code.endswith('.read') else 'sensitive'),'false'])+')' for code,resource,scopes in permissions)
s+='\nON CONFLICT (code) DO NOTHING;\n\n'
settings=[
 ('quantity.allow_fractional','boolean',True,None,None,None,'Allow fractional quantities subject to precision.'),
 ('quantity.decimal_places','integer',3,0,3,None,'Quantity scale; cannot exceed NUMERIC(18,3).'),
 ('stock.allow_negative_balance','boolean',False,None,None,None,'Permit resulting on-hand below zero only if available-quantity policy also permits.'),
 ('stock.require_available_quantity','boolean',True,None,None,None,'Reject resulting negative stock even if negative-balance policy permits it.'),
 ('stock.require_adjustment_approval','boolean',True,None,None,None,'When true, direct adjustment is blocked until an approval workflow exists.'),
 ('stock.require_transfer_approval','boolean',True,None,None,None,'When true at either warehouse, direct transfer is blocked until an approval workflow exists.'),
 ('pricing.allow_zero_unit_price','boolean',False,None,None,None,'Allow zero draft sale price or purchase cost; negative values never allowed.'),
 ('pricing.allow_manual_price','boolean',False,None,None,None,'Allow manual sale price only with pricing.override permission.'),
 ('discount.max_line_percent','decimal',0,0,100,'percent','Maximum permitted draft line discount percentage.'),
 ('discount.require_approval_above_percent','decimal',0,0,100,'percent','Discounts above this percentage are blocked until approval workflow exists.'),
]
s+='INSERT INTO settings.setting_definitions(key,category,description,value_type,default_value,minimum_value,maximum_value,unit,change_permission_code) VALUES\n'
s+=',\n'.join('('+','.join([sql(key),sql(key.split('.')[0]),sql(desc),sql(typ),sql(json.dumps(val))+'::jsonb','NULL' if lo is None else str(lo),'NULL' if hi is None else str(hi),'NULL' if unit is None else sql(unit),"'settings.update_global'"])+')' for key,typ,val,lo,hi,unit,desc in settings)
s+='\nON CONFLICT (key) DO NOTHING;\nCOMMIT;\n'
(root/'seeds/010_erp_routine_catalog.sql').write_text(s)
