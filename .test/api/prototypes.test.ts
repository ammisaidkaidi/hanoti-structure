import { readFile } from 'node:fs/promises';
import { describe, expect, expectTypeOf, it } from 'vitest';
import {
  ApiNotImplementedError,
  Erp,
  createProduct,
  notImplemented,
} from '../../hanoti/api/index.js';
import type {
  ApiFunctionArgs,
  ApiPrototypeFunction,
  ApiSession,
  ResultType,
} from '../../hanoti/api/common/index.js';
import { erpPrototypeCatalog } from '../../hanoti/api/erp/catalog.js';
import type { ErpOperationName } from '../../hanoti/api/erp/catalog.js';

type Operation = {
  readonly name: ErpOperationName;
  readonly operation: string;
  readonly declaredSqlRoutine: string | null;
};
const operations = erpPrototypeCatalog.flatMap<Operation>((task) => task.operations);

describe('ERP async prototypes — no HTTP or database implementation', () => {
  it('exports exactly the inventoried task functions without duplicate names', () => {
    expect(erpPrototypeCatalog).toHaveLength(13);
    expect(operations).toHaveLength(79);
    expect(new Set(operations.map((entry) => entry.name)).size).toBe(operations.length);
    const exportedFunctions = Object.entries(Erp)
      .filter(([, value]) => typeof value === 'function')
      .map(([name]) => name);
    expect(exportedFunctions.sort()).toEqual(operations.map((entry) => entry.name).sort());
    expect(erpPrototypeCatalog.every((task) => task.implementation === 'prototype')).toBe(true);
  });

  for (const operation of operations) {
    it(`${operation.name} rejects asynchronously without inspecting or changing the argument`, async () => {
      const fn: ApiPrototypeFunction = Erp[operation.name];
      const arg = new Proxy({} as ApiFunctionArgs<unknown>, {
        get() {
          throw new Error('Prototype must not read request/session/data/result');
        },
        set() {
          throw new Error('Prototype must not mutate arguments or responses');
        },
        ownKeys() {
          throw new Error('Prototype must not enumerate request information');
        },
      });
      const promise = fn(arg);
      expect(promise).toBeInstanceOf(Promise);
      await expect(promise).rejects.toBeInstanceOf(ApiNotImplementedError);
      await expect(promise).rejects.toMatchObject({
        name: 'ApiNotImplementedError',
        code: 'NOT_IMPLEMENTED',
        operation: operation.operation,
        message: `Not implemented: ${operation.operation}`,
      });
    });
  }

  it('keeps generic data/return types while leaving ResultType and session opaque', () => {
    const typed = createProduct<{ sku: string }, { id: string }>;
    expectTypeOf(typed).parameter(0).toEqualTypeOf<ApiFunctionArgs<{ sku: string }>>();
    expectTypeOf(typed).returns.toEqualTypeOf<Promise<{ id: string }>>();
    expectTypeOf<ResultType>().toBeUnknown();
    expectTypeOf<ApiSession>().toBeUnknown();
    expectTypeOf<keyof ApiFunctionArgs>().toEqualTypeOf<
      'req' | 'res' | 'session' | 'db' | 'data' | 'params' | 'result'
    >();
  });

  it('has an explicit throwing helper, not a fabricated success result', () => {
    expect(() => notImplemented('erp.test')).toThrowError(new ApiNotImplementedError('erp.test'));
  });

  it('covers all twelve current ERP tables without inventing invoice tables', async () => {
    const schema = JSON.parse(
      await readFile(new URL('../data/fixtures/schema-manifest.json', import.meta.url), 'utf8'),
    ) as { tables: { schema: string; name: string }[] };
    const expected = schema.tables
      .filter((table) => table.schema === 'erp')
      .map((table) => `${table.schema}.${table.name}`);
    const actual = [...new Set(erpPrototypeCatalog.flatMap<string>((task) => task.tables))];
    expect(actual.sort()).toEqual(expected.sort());
    expect(operations.some((entry) => /invoice|freeze|unfreeze/i.test(entry.name))).toBe(false);
  });

  it('marks all thirteen existing public SQL candidates without calling private SQL helpers', async () => {
    const routines = JSON.parse(
      await readFile(new URL('../data/fixtures/routines-manifest.json', import.meta.url), 'utf8'),
    ) as { name: string; exposed: boolean }[];
    const expected = routines
      .filter((entry) => entry.exposed && entry.name.startsWith('erp.'))
      .map((entry) => entry.name);
    const actual = [
      ...new Set(
        operations
          .map((entry) => entry.declaredSqlRoutine)
          .filter((name): name is string => name !== null),
      ),
    ];
    expect(actual.sort()).toEqual(expected.sort());
    expect(actual).toHaveLength(13);
  });

  it('keeps the prototypes disconnected from SQL clients, routers and database lifecycles', async () => {
    const pkg = JSON.parse(
      await readFile(new URL('../../hanoti/api/package.json', import.meta.url), 'utf8'),
    ) as {
      dependencies: Record<string, string>;
    };
    expect(Object.keys(pkg.dependencies)).toEqual(['@app/data', '@types/express']);
    for (const task of erpPrototypeCatalog) {
      const code = await readFile(
        new URL(`../../hanoti/api/erp/${task.task}.ts`, import.meta.url),
        'utf8',
      );
      expect(code.match(/export async function /g)).toHaveLength(task.operations.length);
      expect(code).not.toMatch(/\b(?:pool|client|dataSource|router)\.|\.listen\(|\.initialize\(/);
      expect(code).not.toMatch(/from ['"](?:pg|typeorm|express|@app\/data)['"]/);
    }
  });
});
