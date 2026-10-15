import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { DataSource } from 'typeorm';
import { describe, expect, it } from 'vitest';
import {
  Auth,
  Erp,
  App,
  Settings,
  createDataSource,
  schemaNames,
} from '../../hanoti/data/code/index.js';
import manifest from './fixtures/schema-manifest.json' with { type: 'json' };

// Building metadata validates TypeORM mappings but never calls initialize or opens a pool.
class OfflineDataSource extends DataSource {
  async prepareMetadata() {
    await this.buildMetadatas();
  }
}

describe('SQL-to-TypeORM parity without database access', () => {
  it('keeps the checked SQL declarations in sync with the generated mapping manifest', async () => {
    for (const [path, hash] of Object.entries(manifest.files)) {
      const sql = await readFile(new URL(`../../hanoti/data/${path}`, import.meta.url));
      expect(
        createHash('sha256').update(sql).digest('hex'),
        `Regenerate mappings after reviewing ${path}`,
      ).toBe(hash);
    }
  });

  it('exposes database and schema namespaces', () => {
    expect(new Auth.User()).toBeInstanceOf(Auth.User);
    expect(new Erp.Product()).toBeInstanceOf(Erp.Product);
    expect(new Settings.GSettings()).toBeInstanceOf(Settings.GSettings);
    expect(new App.File()).toBeInstanceOf(App.File);
  });

  for (const schema of schemaNames) {
    it(`maps every ${schema} table, column, key, constraint and index`, async () => {
      const original = createDataSource({
        url: 'postgresql://test:unused@localhost/hanouti',
      });
      const source = new OfflineDataSource(original.options);
      await source.prepareMetadata();
      const tables = manifest.tables.filter((table) => table.schema === schema);
      expect(source.isInitialized).toBe(false);
      expect(source.entityMetadatas).toHaveLength(30);
      expect(source.entityMetadatas.filter((meta) => meta.schema === schema)).toHaveLength(
        tables.length,
      );
      for (const table of tables) {
        const meta = source.entityMetadatas.find(
          (item) => item.tableName === table.name && item.schema === table.schema,
        );
        expect(meta, table.name).toBeDefined();
        if (!meta) throw new Error(`Missing ${table.name}`);
        expect(meta.name).toBe(table.className);
        expect(meta.synchronize).toBe(false);
        expect(meta.columns).toHaveLength(table.columns.length);
        for (const expected of table.columns) {
          const column = meta.columns.find((item) => item.databaseName === expected.name);
          expect(column, `${table.name}.${expected.name}`).toBeDefined();
          if (!column) throw new Error(`Missing ${expected.name}`);
          expect(column.propertyName).toBe(expected.property);
          expect(column.type).toBe(expected.type);
          expect(column.isNullable).toBe(expected.nullable);
          expect(column.isPrimary).toBe(expected.primary);
          expect(column.isArray).toBe(expected.array);
          expect(column.isSelect).toBe(!expected.hidden);
          if (expected.length !== null) expect(column.length).toBe(String(expected.length));
          if (expected.precision !== null) expect(column.precision).toBe(expected.precision);
          if (expected.scale !== null) expect(column.scale).toBe(expected.scale);
          if (expected.default !== null) {
            expect(typeof column.default).toBe('function');
            expect((column.default as () => string)()).toBe(expected.default);
          }
          if (expected.generated) {
            expect(column.asExpression).toBe(expected.generated);
            expect(column.generatedType).toBe('STORED');
            expect(column.isInsert).toBe(false);
            expect(column.isUpdate).toBe(false);
          }
        }
        expect(meta.checks.map((item) => item.expression).sort()).toEqual(
          table.checks.map((item) => item.expression).sort(),
        );
        expect(
          meta.uniques
            .map((item) => item.columns.map((column) => column.databaseName).join(','))
            .sort(),
        ).toEqual(table.uniqueColumns.map((columns) => columns.join(',')).sort());
        expect(meta.indices.map((item) => item.name).sort()).toEqual(
          table.indexes.map((item) => item.name).sort(),
        );
        expect(meta.foreignKeys).toHaveLength(table.foreignKeys.length);
        for (const expected of table.foreignKeys) {
          const match = meta.foreignKeys.find(
            (key) =>
              key.columns.map((column) => column.databaseName).join(',') ===
              expected.columns.join(','),
          );
          expect(match?.referencedEntityMetadata.tableName).toBe(expected.target);
          expect(match?.referencedEntityMetadata.schema).toBe(expected.schema);
          expect(match?.referencedColumns.map((column) => column.databaseName)).toEqual(
            expected.referencedColumns,
          );
          expect(match?.onDelete).toBe(expected.onDelete);
        }
      }
    });
  }
});
