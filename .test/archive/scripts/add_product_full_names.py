from pathlib import Path
import json,re
r=Path('/home/user/hanouti/data')
def replace(s,old,new,n=1):
 assert s.count(old)==n,(old,s.count(old),n)
 return s.replace(old,new)
p=r/'migrations/hanouti/003_erp.sql';s=p.read_text()
s=replace(s,'-- [Brand] /[Serie] [MadeIn] [Quality] [Ref]. No generated label is declared.', '-- [Brand] /[Serie] [MadeIn] [Quality] [Ref]. full_name is maintained by a database trigger.')
a=s.index('CREATE TABLE erp.products (');b=s.index('CREATE TABLE erp.customers (',a)
piece=s[a:b];piece=replace(piece,"  name VARCHAR(240) NOT NULL CHECK (btrim(name) <> ''),", "  name VARCHAR(240) NOT NULL CHECK (btrim(name) <> ''),\n  -- Database-maintained composed label; components remain authoritative.\n  full_name TEXT NOT NULL CHECK (btrim(full_name) <> ''),")
s=s[:a]+piece+s[b:]
s=replace(s,"  sku_snapshot VARCHAR(80) NOT NULL CHECK (btrim(sku_snapshot) <> ''),", "  sku_snapshot VARCHAR(80) NOT NULL CHECK (btrim(sku_snapshot) <> ''),\n  -- Product full_name captured on insertion or product replacement; never a live label.\n  full_name TEXT NOT NULL CHECK (btrim(full_name) <> ''),",2);p.write_text(s)
p=r/'migrations/hanouti/010_row_guards.sql';s=p.read_text()
needle='  -- Parent timestamp changes even for direct item DML; the parent lock is held through commit.'
s=replace(s,needle,"""  -- Copy the stored product label, not a caller-supplied value. Keep existing snapshots unchanged.
  IF TG_OP='INSERT' OR (TG_OP='UPDATE' AND NEW.product_id IS DISTINCT FROM OLD.product_id) THEN
    SELECT full_name INTO NEW.full_name FROM erp.products WHERE id=NEW.product_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Product unavailable for item snapshot' USING ERRCODE='23503'; END IF;
  ELSIF TG_OP='UPDATE' AND NEW.full_name IS DISTINCT FROM OLD.full_name THEN
    RAISE EXCEPTION 'Item full_name is a product snapshot; replace the item to refresh it' USING ERRCODE='22023';
  END IF;
"""+needle)
newfn="""-- Recompute on ordinary product-row INSERT/UPDATE; a frozen-flag transition is metadata only.
-- A rename of the separately stored brand does not itself update product rows.
CREATE FUNCTION erp._product_full_name_guard()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_brand text;
BEGIN
  IF TG_OP='UPDATE' AND NEW.frozen IS DISTINCT FROM OLD.frozen THEN
    NEW.full_name:=OLD.full_name;
    RETURN NEW;
  END IF;
  IF NEW.brand_id IS NOT NULL THEN
    SELECT name INTO v_brand FROM erp.brands WHERE id=NEW.brand_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Product brand unavailable' USING ERRCODE='23503'; END IF;
  END IF;
  NEW.full_name:=concat_ws(' ',
    nullif(btrim(NEW.abbreviation),''), nullif(btrim(NEW.name),''),
    nullif(btrim(NEW.attributes),''), nullif(btrim(NEW.material),''),
    nullif(btrim(NEW.dimensions),''), nullif(btrim(NEW.color),''),
    nullif(btrim(v_brand),''), '/'||nullif(btrim(NEW.series),''),
    nullif(btrim(NEW.made_in),''), nullif(btrim(NEW.quality),''), nullif(btrim(NEW.reference),'')
  );
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION erp._product_full_name_guard() FROM PUBLIC;

"""
s=replace(s,'COMMIT;',newfn+'COMMIT;');p.write_text(s)
p=r/'migrations/hanouti/011_order_edit_routines.sql';s=p.read_text();s=replace(s,'COMMIT;',"CREATE TRIGGER b_product_full_name BEFORE INSERT OR UPDATE ON erp.products\n  FOR EACH ROW EXECUTE FUNCTION erp._product_full_name_guard();\n\nCOMMIT;");p.write_text(s)
p=r/'migrations/hanouti/009_erp_routines.sql';s=p.read_text()
s=replace(s,'SELECT id,sku,name,unit_code,sale_price,currency_code INTO v_product FROM erp.products WHERE id=v_product_id AND is_active;', 'SELECT id,sku,name,full_name,unit_code,sale_price,currency_code INTO v_product FROM erp.products WHERE id=v_product_id AND is_active FOR SHARE;')
s=replace(s,'product_id,sku_snapshot,description,unit_code,quantity,','product_id,sku_snapshot,full_name,description,unit_code,quantity,',2)
s=replace(s,'v_product_id,v_product.sku,v_product.name,v_product.unit_code,','v_product_id,v_product.sku,v_product.full_name,v_product.name,v_product.unit_code,',2)
s=replace(s,'v_totals jsonb; v_header jsonb; v_lines jsonb;','v_totals jsonb; v_header jsonb; v_lines jsonb; v_snapshots jsonb;')
for kind in ['sales','purchase']:
 needle=f"      INTO v_lines FROM erp.{kind}_order_items WHERE {kind}_order_id=p_order_id;"
 s=replace(s,needle,needle+f"\n    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'line_number',line_number,'product_id',product_id,'full_name',full_name) ORDER BY line_number),'[]'::jsonb)\n      INTO v_snapshots FROM erp.{kind}_order_items WHERE {kind}_order_id=p_order_id;")
s=replace(s,"RETURN jsonb_build_object('summary',v_totals,'document',v_header||jsonb_build_object('lines',v_lines));", "RETURN jsonb_build_object('summary',v_totals,'document',v_header||jsonb_build_object('lines',v_lines),'item_snapshots',v_snapshots);");p.write_text(s)
p=r/'tests/fixtures/routines-manifest.json';m=json.loads(p.read_text());m.append({'name':'erp._product_full_name_guard','signature':'erp._product_full_name_guard()','file':'010_row_guards.sql','exposed':False});p.write_text(json.dumps(m,indent=2)+'\n')
p=r/'seeds/020_erp_routine_privileges.sql';s=p.read_text();s=replace(s,'GRANT SELECT (id,sku,name,unit_code,sale_price,currency_code,kind,is_active)', 'GRANT SELECT (id,sku,name,full_name,unit_code,sale_price,currency_code,kind,is_active)');s=replace(s,'GRANT SELECT ON erp.warehouses,', 'GRANT SELECT (id,name) ON erp.brands TO hanouti_routine_owner;\nGRANT SELECT ON erp.warehouses,');s=replace(s,'REVOKE CREATE ON SCHEMA', 'ALTER FUNCTION erp._product_full_name_guard() OWNER TO hanouti_routine_owner;\nREVOKE CREATE ON SCHEMA');p.write_text(s)
p=r/'tests/sql/erp_routines_privileges.sql';s=p.read_text();s=re.sub(r'\$list\$.*?\$list\$', lambda _: '$list$'+json.dumps([{k:x[k] for k in ('signature','exposed')} for x in m])+'$list$',s);p.write_text(s)
p=r/'tests/routines.test.ts';p.write_text(replace(p.read_text(),'toHaveLength(37)','toHaveLength(38)'))
# Correct the obsolete UUID cast in the already-existing documentation example.
p=r/'ERP_ROUTINES.md';s=p.read_text().replace('$5::timestamptz, $6::uuid','$5::timestamptz, $6::bigint').replace('37 functions in total: 15 entry points and 22 internal/trigger helpers','38 functions in total: 15 entry points and 23 internal/trigger helpers');p.write_text(s)
p=r/'README.md';p.write_text(p.read_text().replace('37 unapplied functions','38 unapplied functions'))
print('Added full_name columns, product recomposition trigger, item snapshots and read metadata. No SQL execution.')
