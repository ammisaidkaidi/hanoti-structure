import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import manifest from './fixtures/schema-manifest.json' with { type: 'json' };

const read = (path: string) => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');

describe('product fullName and item snapshot declarations (offline only)', () => {
  it('maps full_name to fullName as non-null TEXT on products and both item tables', () => {
    for (const name of ['products', 'sales_order_items', 'purchase_order_items']) {
      const table = manifest.tables.find((entry) => entry.schema === 'erp' && entry.name === name)!;
      expect(table.columns.find((entry) => entry.name === 'full_name')).toMatchObject({
        property: 'fullName',
        type: 'text',
        nullable: false,
        generated: null,
      });
      expect(table.checks.some((entry) => entry.expression === "btrim(full_name) <> ''")).toBe(
        true,
      );
      expect(table.columns.some((entry) => entry.name === 'description')).toBe(true);
    }
  });
  it('composes the label in the specified order with trimmed, optional components', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/010_row_guards.sql');
    const body = sql.split('CREATE FUNCTION erp._product_full_name_guard()')[1]!;
    const components = [
      'NEW.abbreviation',
      'NEW.name',
      'NEW.attributes',
      'NEW.material',
      'NEW.dimensions',
      'NEW.color',
      'v_brand',
      'NEW.series',
      'NEW.made_in',
      'NEW.quality',
      'NEW.reference',
    ];
    const expression = body.split("NEW.full_name:=concat_ws(' ',")[1]!;
    const positions = components.map((component) => expression.indexOf(component));
    expect(positions.every((position) => position >= 0)).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(body).toContain("'/'||nullif(btrim(NEW.series),'')");
    expect(body).toContain('SELECT name INTO v_brand FROM erp.brands');
    expect(body).toContain('NEW.full_name:=OLD.full_name');
    expect(await read('hanoti/data/migrations/hanouti/011_order_edit_routines.sql')).toContain(
      'CREATE TRIGGER b_product_full_name BEFORE INSERT OR UPDATE ON erp.products',
    );
  });
  it('copies the authoritative product value and prevents rewriting existing snapshots', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/010_row_guards.sql');
    expect(sql).toContain(
      'SELECT full_name INTO NEW.full_name FROM erp.products WHERE id=NEW.product_id FOR SHARE',
    );
    expect(sql).toContain('NEW.product_id IS DISTINCT FROM OLD.product_id');
    expect(sql).toContain('NEW.full_name IS DISTINCT FROM OLD.full_name');
    expect(sql).toContain('Item full_name is a product snapshot; replace the item to refresh it');
    const writers = await read('hanoti/data/migrations/hanouti/009_erp_routines.sql');
    expect(writers).toContain('v_product_id,v_product.sku,v_product.full_name,v_product.name');
    expect(writers).toContain('WHERE id=v_product_id AND is_active FOR SHARE');
  });
  it('returns separate read-only metadata without altering editable document inputs', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/009_erp_routines.sql');
    expect(sql).toContain("'item_snapshots',v_snapshots");
    expect(sql.match(/'full_name',full_name/g)).toHaveLength(2);
    expect(sql).toContain(
      "k NOT IN ('product_id','quantity','unit_price','unit_cost','discount_amount','tax_amount')",
    );
    const privileges = await read('hanoti/data/seeds/020_erp_routine_privileges.sql');
    expect(privileges).toContain('GRANT SELECT (id,name) ON erp.brands TO hanouti_routine_owner');
    expect(privileges).toContain(
      'ALTER FUNCTION erp._product_full_name_guard() OWNER TO hanouti_routine_owner',
    );
    expect(privileges).not.toContain(
      'GRANT EXECUTE ON FUNCTION erp._product_full_name_guard() TO hanouti_backend',
    );
  });
  it('includes unexecuted coverage for long names, freezing, snapshots and replacement saves', async () => {
    const sql = await read('.test/data/sql/erp_routines_full_names.integration.sql');
    for (const scenario of [
      "repeat('x',700)",
      'Expected frozen product rejection',
      'Expected snapshot rewrite rejection',
      'item_snapshots',
      'Recreate items with latest product name',
      'Shared brand rename alone',
    ])
      expect(sql).toContain(scenario);
    expect(sql).toContain('ROLLBACK;');
  });
});
