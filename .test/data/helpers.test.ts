import { describe, expect, it, vi } from 'vitest';
import type { DataSource, EntityManager } from 'typeorm';
import {
  Auth,
  Erp,
  App,
  Settings,
  allEntities,
  assertVector4096,
  createDataSource,
  destroyDataSource,
  getPagination,
  getRepository,
  initializeDataSource,
  jsonbNull,
  readDatabaseConfiguration,
  withTransaction,
} from '../../hanoti/data/code/index.js';
const configuration = { url: 'postgresql://test:unused@localhost/hanouti' };
function fakeSource(initialized = false, failInitialize = false) {
  const source = {
    isInitialized: initialized,
    initialize: vi.fn(async () => {
      if (failInitialize) throw new Error('Simulated unavailable database');
      source.isInitialized = true;
      return source;
    }),
    destroy: vi.fn(async () => {
      source.isInitialized = false;
    }),
  };
  return source;
}

describe('single-database factory', () => {
  it('registers all four schemas in one uninitialized source, with automatic DDL disabled', () => {
    const source = createDataSource(configuration);
    expect(source.isInitialized).toBe(false);
    expect(source.options).toMatchObject({
      type: 'postgres',
      applicationName: 'hanouti',
      synchronize: false,
      migrationsRun: false,
      dropSchema: false,
      installExtensions: false,
      logging: false,
      parseInt8: false,
    });
    expect(source.options.migrations).toEqual([]);
    expect(source.options.entities).toHaveLength(30);
    for (const entity of [Auth.User, Erp.Product, App.File, Settings.Setting]) {
      expect(source.options.entities).toContain(entity);
    }
    expect(allEntities).toHaveLength(30);
  });
  it('requires DATABASE_URL targeting hanouti, without leaking credentials', () => {
    expect(readDatabaseConfiguration({ DATABASE_URL: configuration.url })).toEqual(configuration);
    expect(() =>
      readDatabaseConfiguration({ AUTH_DATABASE_URL: 'postgresql://localhost/auth' }),
    ).toThrow('DATABASE_URL');
    expect(() => createDataSource({ url: 'postgresql://user:secret@localhost/erp' })).toThrow(
      'hanouti',
    );
    try {
      createDataSource({ url: 'postgresql://user:secret@localhost/erp' });
    } catch (error) {
      expect(String(error)).not.toContain('secret');
    }
  });
  it('preserves the factory error message and keeps parser causes private', () => {
    const message =
      'Invalid DATABASE_URL: expected a PostgreSQL URL targeting hanouti, with only documented TLS query options.';
    for (const url of [
      'postgresql://user:DO_NOT_LOG@localhost/other',
      `${configuration.url}?connect_timeout=7`,
    ]) {
      expect(() => createDataSource({ url })).toThrow(message);
      expect(() => readDatabaseConfiguration({ DATABASE_URL: url })).toThrow(message);
    }
    try {
      createDataSource({ url: 'postgresql://user:DO_NOT_LOG@localhost/other' });
    } catch (error) {
      expect((error as Error).cause).toBeUndefined();
    }
  });
  it('retains factory-specific pool, timeout and explicit TLS configuration', () => {
    const ssl = { rejectUnauthorized: true };
    const source = createDataSource({ ...configuration, ssl, connectTimeoutMs: 2345, poolSize: 3 });
    expect(source.options).toMatchObject({ ssl, connectTimeoutMS: 2345, poolSize: 3 });
    expect(source.isInitialized).toBe(false);
    const defaults = createDataSource(configuration);
    expect(defaults.options).toMatchObject({ connectTimeoutMS: 10000, poolSize: 10 });
  });
  it('rejects TLS ambiguity, target overrides, and invalid pool limits', () => {
    expect(() =>
      createDataSource({
        url: `${configuration.url}?sslmode=require`,
        ssl: { rejectUnauthorized: true },
      }),
    ).toThrow('not both');
    expect(() => createDataSource({ url: `${configuration.url}?database=erp` })).toThrow('Invalid');
    expect(() => createDataSource({ ...configuration, poolSize: 0 })).toThrow('poolSize');
  });
});
describe('explicit lifecycle (mocked)', () => {
  it('deduplicates concurrent startup and shutdown', async () => {
    const fake = fakeSource();
    const source = fake as unknown as DataSource;
    await Promise.all([initializeDataSource(source), initializeDataSource(source)]);
    expect(fake.initialize).toHaveBeenCalledTimes(1);
    await Promise.all([destroyDataSource(source), destroyDataSource(source)]);
    expect(fake.destroy).toHaveBeenCalledTimes(1);
  });
  it('allows cleanup after initialization failure', async () => {
    const fake = fakeSource(false, true);
    const source = fake as unknown as DataSource;
    await expect(initializeDataSource(source)).rejects.toThrow('unavailable');
    await destroyDataSource(source);
    expect(fake.destroy).not.toHaveBeenCalled();
  });
  it('serializes shutdown behind a pending start', async () => {
    const fake = fakeSource();
    const source = fake as unknown as DataSource;
    await Promise.all([initializeDataSource(source), destroyDataSource(source)]);
    expect(fake.initialize).toHaveBeenCalledTimes(1);
    expect(fake.destroy).toHaveBeenCalledTimes(1);
    expect(fake.isInitialized).toBe(false);
  });
});
describe('repositories and cross-schema transactions', () => {
  it('refuses operations before explicit initialization', async () => {
    const source = createDataSource(configuration);
    expect(() => getRepository(source, Erp.Product)).toThrow('Initialize');
    await expect(withTransaction(source, async () => 'never')).rejects.toThrow('Initialize');
  });
  it('uses the same manager for entities from different schemas', async () => {
    const getRepo = vi.fn((entity: unknown) => ({ entity }));
    const manager = {
      dataSource: {
        isInitialized: true,
        hasMetadata: (entity: unknown) => (allEntities as readonly unknown[]).includes(entity),
      },
      getRepository: getRepo,
    } as unknown as EntityManager;
    const transaction = vi.fn(async (_isolation, operation) => operation(manager));
    const source = { isInitialized: true, transaction } as unknown as DataSource;
    await withTransaction(
      source,
      async (scoped) => {
        expect(getRepository(scoped, Auth.User)).toEqual({ entity: Auth.User });
        expect(getRepository(scoped, Erp.Customer)).toEqual({ entity: Erp.Customer });
        expect(getRepository(scoped, Settings.Setting)).toEqual({ entity: Settings.Setting });
      },
      'SERIALIZABLE',
    );
    expect(transaction).toHaveBeenCalledWith('SERIALIZABLE', expect.any(Function));
    expect(() => getRepository(manager, class Unknown {})).toThrow('does not belong');
    await expect(
      withTransaction(source, async () => {
        throw new Error('rollback');
      }),
    ).rejects.toThrow('rollback');
  });
});
describe('value helpers', () => {
  it('bounds pagination', () => {
    expect(getPagination(2, 20)).toEqual({ page: 2, pageSize: 20, skip: 20, take: 20 });
    expect(() => getPagination(0)).toThrow();
    expect(() => getPagination(1, 101)).toThrow();
    expect(() => getPagination(Number.MAX_SAFE_INTEGER, 100)).toThrow();
  });
  it('validates dense, finite float32 vectors', () => {
    expect(() => assertVector4096(Array(4096).fill(0))).not.toThrow();
    expect(() => assertVector4096([1, 2])).toThrow();
    expect(() => assertVector4096(Array(4096))).toThrow();
    expect(() => assertVector4096(Array(4096).fill(NaN))).toThrow();
    expect(() => assertVector4096(Array(4096).fill(1e100))).toThrow();
  });
  it('distinguishes JSON null from SQL NULL', () => {
    expect(jsonbNull()).toBe("'null'::jsonb");
  });
});
