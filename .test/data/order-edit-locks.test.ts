import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { Erp } from '../../hanoti/data/code/index.js';
import manifest from './fixtures/schema-manifest.json' with { type: 'json' };

const read = (path: string) => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');

describe('header locks and universal row protection (offline declarations only)', () => {
  it('maps all thirty tables with timestamps and non-null frozen flags', () => {
    expect(manifest.tables).toHaveLength(30);
    expect(manifest.tables.some((table) => table.name === 'order_edit_locks')).toBe(false);
    for (const table of manifest.tables) {
      expect(table.columns.find((column) => column.name === 'frozen')).toMatchObject({
        type: 'boolean',
        nullable: false,
        default: 'FALSE',
      });
      expect(table.columns.find((column) => column.name === 'updated_at')).toMatchObject({
        type: 'timestamptz',
        nullable: false,
      });
    }
  });
  it('places the editor, renewal time and bigint fence on both headers', () => {
    expect(new Erp.SalesOrder()).toBeInstanceOf(Erp.SalesOrder);
    expect(new Erp.PurchaseOrder()).toBeInstanceOf(Erp.PurchaseOrder);
    for (const name of ['sales_orders', 'purchase_orders']) {
      const table = manifest.tables.find((entry) => entry.name === name)!;
      expect(table.columns.find((entry) => entry.name === 'lock_version')).toMatchObject({
        type: 'bigint',
        nullable: false,
      });
      expect(table.columns.find((entry) => entry.name === 'locked_at')).toMatchObject({
        type: 'timestamptz',
        nullable: true,
      });
      expect(
        table.foreignKeys.some(
          (entry) => entry.target === 'users' && entry.columns.includes('locked_by'),
        ),
      ).toBe(true);
    }
  });
  it('attaches metadata, truncate and order/item guards to actual tables', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/011_order_edit_routines.sql');
    expect(sql.match(/CREATE TRIGGER a_row_metadata /g)).toHaveLength(30);
    expect(sql.match(/CREATE TRIGGER z_no_truncate /g)).toHaveLength(30);
    expect(sql.match(/CREATE TRIGGER b_order_write /g)).toHaveLength(2);
    expect(sql.match(/CREATE TRIGGER b_order_item_write /g)).toHaveLength(2);
    for (const table of manifest.tables) {
      expect(sql).toContain(`BEFORE INSERT OR UPDATE OR DELETE ON ${table.schema}.${table.name}`);
    }
  });
  it('requires current ownership before replacement and returns the final timestamp', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/009_erp_routines.sql');
    expect(sql).toContain('p_lock_version bigint DEFAULT NULL');
    expect(sql.indexOf('erp._assert_order_edit(p_actor,p_kind,v_id,p_lock_version)')).toBeLessThan(
      sql.indexOf('DELETE FROM erp.sales_order_items'),
    );
    expect(sql).toContain('erp._assert_order_edit(p_actor,p_kind,v_id,v_edit_version)');
    expect(sql).toContain("v_updated:=(v_edit_lock->>'updated_at')::timestamptz");
    expect(sql).toContain('erp._restore_edit_context(v_previous_context)');
    expect(sql).toContain("'edit_lock',v_edit_lock");
  });
  it('uses wall-clock expiry, explicit actions, and no supervisor ownership bypass', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/010_row_guards.sql');
    expect(sql).toContain("OLD.locked_at<=v_now-interval '5 minutes'");
    expect(sql).toContain('v_version IS DISTINCT FROM OLD.lock_version');
    expect(sql).toContain("v_action='force_close'");
    expect(sql).toContain("'.force_close_edit'");
    expect(sql).toContain('NEW.lock_version:=OLD.lock_version+1');
    expect(sql).toContain('NEW.locked_at:=v_now');
    expect(sql).not.toContain('statement_timestamp()');
    const routines = await read('hanoti/data/migrations/hanouti/011_order_edit_routines.sql');
    const body = routines
      .split('CREATE FUNCTION erp.force_close_order_edit(')[1]!
      .split('$fn$;')[0]!;
    expect(body).toContain('SET locked_by=NULL,locked_at=NULL');
    expect(body).not.toContain('erp.open_order_edit(');
  });
  it('bases freezing on the database login, not the security-definer owner', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/010_row_guards.sql');
    expect(sql).toContain("pg_has_role(session_user,c.relowner,'USAGE')");
    expect(sql).toContain("r.rolname='hanouti_data_admin'");
    expect(sql).toContain('Freeze or unfreeze separately from other row changes');
    expect(sql).toContain("attgenerated<>''");
    expect(sql).toContain('Frozen row is read-only');
    expect(sql).toContain("IF TG_OP='TRUNCATE' THEN");
    expect(sql).toContain("current_setting('hanouti.lock_action',true)='metadata'");
    expect(sql).toContain("erp._set_edit_context(NULL,v_kind,v_id,NULL,'metadata'");
    const grants = await read('hanoti/data/seeds/020_erp_routine_privileges.sql');
    expect(grants).not.toMatch(/GRANT hanouti_data_admin TO hanouti_backend/);
    expect(grants.match(/UPDATE \(frozen\) ON /g)).toHaveLength(30);
  });
  it('guards child DML, propagates timestamps and protects frozen parents', async () => {
    const sql = await read('hanoti/data/migrations/hanouti/010_row_guards.sql');
    expect(sql).toContain('v_order:=erp._lock_edit_order(v_kind,v_id)');
    expect(sql).toContain('Frozen order protects all its items');
    expect(sql).toContain('An item cannot be moved to another order');
    expect(sql).toContain('erp._assert_order_edit(v_actor,v_kind,v_id,v_version)');
    expect(sql).toContain('UPDATE erp.sales_orders SET updated_at=clock_timestamp()');
    expect(sql).toContain('NEW.updated_at:=OLD.updated_at');
    expect(sql).toContain("current_setting('hanouti.lock_action',true)='create'");
  });
  it('includes unapplied scenarios without implying live validation', async () => {
    const sql = await read('.test/data/sql/erp_routines_edit_locks.integration.sql');
    for (const scenario of [
      'Expected supervisor write refusal',
      'Expected same-user second-session refusal',
      'Expected missing context rejection',
      'Expected frozen parent rejection',
      'Expected frozen line rejection',
      'Expected expired renewal rejection',
      'Expected mixed unfreeze rejection',
      'Expected stale timestamp rejection',
      'Create-only draft',
    ])
      expect(sql).toContain(scenario);
    expect(sql).toContain('ROLLBACK;');
  });
});
