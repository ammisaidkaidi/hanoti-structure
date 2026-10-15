import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import routines from './fixtures/routines-manifest.json' with { type: 'json' };

const read = (path: string) => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');

describe('unapplied ERP routine declarations (static checks, not database behavior tests)', () => {
  it('exposes only the fifteen reviewed entry points', () => {
    expect(
      routines
        .filter((entry) => entry.exposed)
        .map((entry) => entry.name)
        .sort(),
    ).toEqual([
      'auth.has_permission',
      'erp.adjust_stock',
      'erp.close_order_edit',
      'erp.force_close_order_edit',
      'erp.open_order_edit',
      'erp.order_detail',
      'erp.order_edit_status',
      'erp.order_totals',
      'erp.renew_order_edit',
      'erp.sales_payment_balance',
      'erp.save_purchase_order_draft',
      'erp.save_sales_order_draft',
      'erp.stock_balance',
      'erp.transfer_stock',
      'settings.resolve',
    ]);
    expect(routines).toHaveLength(38);
  });
  for (const file of [...new Set(routines.map((entry) => entry.file))]) {
    it(`${file}: fixes search_path and revokes PUBLIC on every routine`, async () => {
      const text = await read(`hanouti/data/migrations/hanouti/${file}`);
      const entries = routines.filter((entry) => entry.file === file);
      expect(text.match(/^CREATE FUNCTION /gm)).toHaveLength(entries.length);
      expect(text.match(/^LANGUAGE plpgsql VOLATILE SECURITY DEFINER$/gm)).toHaveLength(
        entries.length,
      );
      expect(text.match(/^SET search_path = pg_catalog, pg_temp$/gm)).toHaveLength(entries.length);
      for (const entry of entries) {
        expect(text).toContain(`CREATE FUNCTION ${entry.name}(`);
        expect(text).toContain(`REVOKE ALL ON FUNCTION ${entry.signature} FROM PUBLIC;`);
      }
      expect(text).not.toMatch(/^GRANT /m);
      expect(text.match(/^BEGIN;$/gm)).toHaveLength(1);
      expect(text.match(/^COMMIT;$/gm)).toHaveLength(1);
    });
  }
  it('keeps permission catalog setup separate from business grants', async () => {
    const text = await read('hanoti/data/seeds/010_erp_routine_catalog.sql');
    expect(text).toContain('INSERT INTO auth.permissions');
    expect(text).toContain('INSERT INTO settings.setting_definitions');
    expect(text).not.toMatch(
      /INSERT INTO auth\.(?:users|roles|user_roles|role_permissions|subject_permissions)\b/,
    );
    expect(text).toContain("'stock.require_adjustment_approval'");
    expect(text).toContain("'stock.require_transfer_approval'");
    expect(text).toContain('ON CONFLICT (key) DO NOTHING');
  });
  it('limits backend EXECUTE grants to the reviewed functions, never internal helpers', async () => {
    const text = await read('hanoti/data/seeds/020_erp_routine_privileges.sql');
    const grants = [...text.matchAll(/^GRANT EXECUTE ON FUNCTION (.+) TO hanouti_backend;$/gm)].map(
      (match) => match[1],
    );
    expect(grants.sort()).toEqual(
      routines
        .filter((entry) => entry.exposed)
        .map((entry) => entry.signature)
        .sort(),
    );
    expect(text).toContain('CREATE ROLE hanouti_routine_owner NOLOGIN NOSUPERUSER');
    expect(text).toContain('CREATE ROLE hanouti_backend NOLOGIN NOSUPERUSER');
    expect(text).not.toMatch(/GRANT (?:SELECT|INSERT|UPDATE|DELETE|ALL) [^;]* TO hanouti_backend;/);
  });
  it('includes unapplied integration assertions without wiring them into Node test scripts', async () => {
    const text = await read('.test/data/sql/erp_routines.integration.sql');
    expect(text).toContain('ROLLBACK;');
    expect(text).toContain('Expected membership denial');
    expect(text).toContain('Expected role conflict');
    expect(text).toContain('Expected approval block');
    expect(text).toContain('Expected key conflict');
    expect(text).toContain('Expected edit conflict');
    expect(text).toContain('Expected currency mismatch');
  });
});
