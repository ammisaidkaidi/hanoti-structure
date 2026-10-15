import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdtemp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  backupDatabase,
  backupRelativePath,
  connectionEnvironment,
  databaseName,
  type ToolRunner,
} from '../../../hanoti/packages/server/src/backup.js';
const connectionString = 'postgresql://backup:secret@localhost:5432/hanouti';
const now = () => new Date('2026-10-14T02:03:04.005Z');
const directories: string[] = [];
async function temporaryRoot() {
  const temporaryDirectory = fileURLToPath(new URL('../../.tmp/', import.meta.url));
  await mkdir(temporaryDirectory, { recursive: true });
  const root = await mkdtemp(join(temporaryDirectory, 'hanouti-backup-'));
  directories.push(root);
  return root;
}
const successfulTool: ToolRunner = async (tool, args) => {
  if (tool === 'pg_dump') await writeFile(args[3]!, 'test archive');
};
afterEach(async () => {
  vi.unstubAllEnvs();
  await Promise.all(
    directories.splice(0).map((root) => rm(root, { recursive: true, force: true })),
  );
});

describe('whole hanouti database backup', () => {
  it('uses UTC hanouti/year/month/day-time.dump paths', () => {
    expect(backupRelativePath(now())).toBe(join('hanouti', '2026', '10', '14-02-03-04-005.dump'));
    expect(backupRelativePath(new Date('2026-01-01T00:00:00+02:00'))).toBe(
      join('hanouti', '2025', '12', '31-22-00-00-000.dump'),
    );
  });
  it('passes credentials through the environment, not process arguments', () => {
    const env = connectionEnvironment(
      'postgresql://backup:p%40ss@localhost/hanouti?sslmode=verify-full',
    );
    expect(env.PGPASSWORD).toBe('p@ss');
    expect(env.PGDATABASE).toBe('hanouti');
    expect(env.PGSSLMODE).toBe('verify-full');
    expect(env.DATABASE_URL).toBeUndefined();
  });
  it('retains the databaseName export and libpq-only timeout and credential decoding', () => {
    expect(databaseName).toBe('hanouti');
    const env = connectionEnvironment(
      'postgresql://back%75p:p%40ss@[::1]:5433/hanouti?connect_timeout=7&sslcert=%2Fcert.pem&sslkey=%2Fkey.pem',
    );
    expect(env).toMatchObject({
      PGDATABASE: 'hanouti',
      PGHOST: '::1',
      PGPORT: '5433',
      PGUSER: 'backup',
      PGPASSWORD: 'p@ss',
      PGCONNECT_TIMEOUT: '7',
      PGSSLCERT: '/cert.pem',
      PGSSLKEY: '/key.pem',
      PGAPPNAME: 'hanouti-backup',
    });
    expect(connectionEnvironment(connectionString).PGCONNECT_TIMEOUT).toBe('15');
  });
  it('strips inherited PostgreSQL settings and database URLs while retaining PATH', () => {
    vi.stubEnv('PGHOST', 'unexpected-host');
    vi.stubEnv('PGOPTIONS', '-c search_path=other');
    vi.stubEnv('PGPASSWORD', 'DO_NOT_INHERIT');
    vi.stubEnv('DATABASE_URL', 'DO_NOT_INHERIT');
    vi.stubEnv('AUTH_DATABASE_URL', 'DO_NOT_INHERIT');
    const env = connectionEnvironment('postgresql://localhost/hanouti');
    expect(env.PGHOST).toBe('localhost');
    expect(env.PGOPTIONS).toBeUndefined();
    expect(env.PGPASSWORD).toBeUndefined();
    expect(env.DATABASE_URL).toBeUndefined();
    expect(env.AUTH_DATABASE_URL).toBeUndefined();
    expect(env.PATH).toBe(process.env.PATH);
  });
  it('preserves the backup error message without leaking URL parser or decoding errors', () => {
    for (const url of [
      'postgresql://backup:DO_NOT_LOG@localhost/wrong',
      'postgresql://backup:%ZZ@localhost/hanouti',
    ]) {
      let caught: unknown;
      try {
        connectionEnvironment(url);
      } catch (error) {
        caught = error;
      }
      expect(caught).toBeInstanceOf(Error);
      expect((caught as Error).message).toBe(
        'Invalid DATABASE_URL: expected a PostgreSQL URL targeting database hanouti; see backup documentation.',
      );
      expect((caught as Error).cause).toBeUndefined();
    }
  });
  it.each(['toString', 'constructor', '__proto__', 'hasOwnProperty', '%74oString'])(
    'rejects unsupported inherited query key %s before filesystem or tool work',
    async (key) => {
      const root = await temporaryRoot();
      const runner = vi.fn(successfulTool);
      const url = `postgresql://backup:DO_NOT_LOG@localhost/hanouti?${key}=test`;
      const message =
        'Invalid DATABASE_URL: expected a PostgreSQL URL targeting database hanouti; see backup documentation.';
      expect(() => connectionEnvironment(url)).toThrow(message);
      await expect(backupDatabase({ root, connectionString: url, runner })).rejects.toThrow(
        message,
      );
      expect(runner).not.toHaveBeenCalled();
      expect(await readdir(root)).toEqual([]);
    },
  );
  it('rejects old separate database targets without leaking passwords', () => {
    for (const name of ['auth', 'erp', 'app']) {
      expect(() => connectionEnvironment(`postgresql://backup:secret@localhost/${name}`)).toThrow(
        'DATABASE_URL',
      );
    }
    try {
      connectionEnvironment('postgresql://backup:secret@localhost/wrong');
    } catch (error) {
      expect(String(error)).not.toContain('secret');
    }
  });
  it('makes ONE whole-database archive with no schema filters and private permissions', async () => {
    const root = await temporaryRoot();
    const runner = vi.fn(successfulTool);
    const path = await backupDatabase({ root, connectionString, now, runner });
    expect(path).toBe(join(root, backupRelativePath(now())));
    expect(runner).toHaveBeenCalledTimes(2);
    const dump = runner.mock.calls[0]!;
    expect(dump[0]).toBe('pg_dump');
    expect(dump[1]).toEqual(['--format=custom', '--no-password', '--file', `${path}.partial`]);
    expect(dump[2].PGDATABASE).toBe('hanouti');
    expect(await readFile(path, 'utf8')).toBe('test archive');
    expect((await stat(path)).mode & 0o777).toBe(0o600);
    await expect(stat(`${path}.partial`)).rejects.toMatchObject({ code: 'ENOENT' });
    await expect(stat(join(root, '.backup.lock'))).rejects.toMatchObject({ code: 'ENOENT' });
  });
  it('removes failed partial output and releases the lock', async () => {
    const root = await temporaryRoot();
    const runner: ToolRunner = async () => {
      throw new Error('simulated failure');
    };
    await expect(backupDatabase({ root, connectionString, now, runner })).rejects.toThrow(
      'simulated failure',
    );
    expect(await readdir(join(root, 'hanouti', '2026', '10'))).toEqual([]);
    await expect(stat(join(root, '.backup.lock'))).rejects.toMatchObject({ code: 'ENOENT' });
  });
  it('does not publish archives rejected by pg_restore', async () => {
    const root = await temporaryRoot();
    const runner: ToolRunner = async (tool, args, env, timeout) => {
      if (tool === 'pg_restore') throw new Error('invalid archive');
      await successfulTool(tool, args, env, timeout);
    };
    await expect(backupDatabase({ root, connectionString, now, runner })).rejects.toThrow(
      'invalid archive',
    );
    expect(await readdir(join(root, 'hanouti', '2026', '10'))).toEqual([]);
  });
  it('refuses overlapping runs without deleting another job’s lock', async () => {
    const root = await temporaryRoot();
    await mkdir(join(root, '.backup.lock'));
    const runner = vi.fn(successfulTool);
    await expect(backupDatabase({ root, connectionString, now, runner })).rejects.toThrow(
      'Backup lock exists',
    );
    expect(runner).not.toHaveBeenCalled();
    expect((await stat(join(root, '.backup.lock'))).isDirectory()).toBe(true);
  });
  it('does not overwrite an existing archive', async () => {
    const root = await temporaryRoot();
    const path = await backupDatabase({ root, connectionString, now, runner: successfulTool });
    await expect(
      backupDatabase({ root, connectionString, now, runner: successfulTool }),
    ).rejects.toMatchObject({ code: 'EEXIST' });
    expect(await readFile(path, 'utf8')).toBe('test archive');
  });
  it('rejects invalid configuration before invoking tools', async () => {
    const root = await temporaryRoot();
    const runner = vi.fn(successfulTool);
    await expect(backupDatabase({ root, connectionString: '', runner })).rejects.toThrow(
      'DATABASE_URL',
    );
    await expect(backupDatabase({ root, connectionString, timeoutMs: 0, runner })).rejects.toThrow(
      'BACKUP_TIMEOUT_MS',
    );
    expect(runner).not.toHaveBeenCalled();
  });
});
