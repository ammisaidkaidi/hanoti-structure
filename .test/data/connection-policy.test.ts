import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { databaseName, parseDatabaseUrl } from '../../hanoti/data/code/connection-policy.js';
import type { ConnectionConsumer } from '../../hanoti/data/code/connection-policy.js';

const consumers: ConnectionConsumer[] = ['typeorm', 'libpq'];
// Independent literals: these expectations are not derived from the implementation.
const accepted = [
  'postgres://localhost/hanouti',
  'postgresql://user:p%40ss@db.example:5433/hanouti',
  'postgresql://[::1]/hanouti',
  'postgresql://localhost/%68anouti',
  'postgresql://localhost/hanouti?sslmode=verify-full&sslrootcert=%2Fcerts%2Fca.pem',
  'postgresql://localhost/hanouti?sslcert=%2Fcert.pem&sslkey=%2Fkey.pem',
  // Refactor only: do not silently tighten existing empty/duplicate TLS option semantics.
  'postgresql://localhost/hanouti?sslmode=',
  'postgresql://localhost/hanouti?sslmode=require&sslmode=verify-full',
];
const rejected = [
  '',
  'not a URL',
  'https://localhost/hanouti',
  'postgresql:///hanouti',
  'postgresql://localhost',
  'postgresql://localhost/auth',
  'postgresql://localhost/erp',
  'postgresql://localhost/app',
  'postgresql://localhost/hanouti/',
  'postgresql://localhost/hanouti/extra',
  'postgresql://localhost/%ZZ',
  'postgresql://localhost/hanouti#fragment',
  'postgresql://localhost/hanouti?database=erp',
  'postgresql://localhost/hanouti?host=other.example',
  'postgresql://localhost/hanouti?options=-csearch_path%3Dpublic',
  'postgresql://localhost/hanouti?SSLMode=require',
  // Explicitly approved fix: inherited object properties are never valid query keys.
  'postgresql://localhost/hanouti?toString=test',
  'postgresql://localhost/hanouti?constructor=test',
  'postgresql://localhost/hanouti?__proto__=test',
  'postgresql://localhost/hanouti?hasOwnProperty=test',
  'postgresql://localhost/hanouti?%74oString=test',
];

for (const consumer of consumers) {
  describe(`${consumer} connection policy`, () => {
    it.each(accepted)('accepts %s', (url) => {
      expect(parseDatabaseUrl(url, consumer)).toBeInstanceOf(URL);
    });
    it.each(rejected)('rejects %s', (url) => {
      expect(() => parseDatabaseUrl(url, consumer)).toThrow('Invalid PostgreSQL connection URL.');
    });
    it('does not expose credentials in error messages or causes', () => {
      const input = 'postgresql://user:DO_NOT_LOG@localhost/other';
      let caught: unknown;
      try {
        parseDatabaseUrl(input, consumer);
      } catch (error) {
        caught = error;
      }
      expect(caught).toBeInstanceOf(Error);
      const error = caught as Error;
      expect(error.message).toBe('Invalid PostgreSQL connection URL.');
      expect(error.cause).toBeUndefined();
      expect(String(error)).not.toContain('DO_NOT_LOG');
    });
  });
}

it('keeps the database name and parsed URL fields available without decoding credentials', () => {
  const url = parseDatabaseUrl('postgresql://backup:p%40ss@[::1]:5433/hanouti', 'libpq');
  expect(databaseName).toBe('hanouti');
  expect(url.hostname).toBe('[::1]');
  expect(url.port).toBe('5433');
  expect(url.username).toBe('backup');
  expect(url.password).toBe('p%40ss');
  expect(url.pathname).toBe('/hanouti');
});
it('allows connect_timeout only for the libpq consumer', () => {
  const url = 'postgresql://localhost/hanouti?connect_timeout=7';
  expect(parseDatabaseUrl(url, 'libpq').searchParams.get('connect_timeout')).toBe('7');
  expect(() => parseDatabaseUrl(url, 'typeorm')).toThrow('Invalid PostgreSQL connection URL.');
});
it('imports the compiled package subpath without TypeORM, pg or entity loading', () => {
  const output = execFileSync(
    process.execPath,
    [
      '--import',
      fileURLToPath(new URL('./fixtures/block-database-imports.mjs', import.meta.url)),
      '--input-type=module',
      '--eval',
      `import { databaseName, parseDatabaseUrl } from '@app/data/connection-policy';
       console.log(JSON.stringify({ databaseName, host: parseDatabaseUrl('postgresql://localhost/hanouti', 'typeorm').hostname }));`,
    ],
    { cwd: fileURLToPath(new URL('../../hanoti/data/', import.meta.url)), encoding: 'utf8' },
  );
  expect(JSON.parse(output)).toEqual({ databaseName: 'hanouti', host: 'localhost' });
});
