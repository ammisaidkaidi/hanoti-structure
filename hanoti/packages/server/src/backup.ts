import { spawn } from 'node:child_process';
import { link, mkdir, open, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import { databaseName, parseDatabaseUrl } from '@app/data/connection-policy';

// Retain the existing export for callers of this module.
export { databaseName } from '@app/data/connection-policy';
export type BackupTool = 'pg_dump' | 'pg_restore';
export type ToolRunner = (
  tool: BackupTool,
  args: string[],
  env: NodeJS.ProcessEnv,
  timeoutMs: number,
) => Promise<void>;

// UTC timestamps, independent of the machine's local timezone.
export function backupRelativePath(date: Date): string {
  const iso = date.toISOString();
  return join(
    databaseName,
    iso.slice(0, 4),
    iso.slice(5, 7),
    `${iso.slice(8, 23).replace(/[T:.]/g, '-')}.dump`,
  );
}

export function connectionEnvironment(connectionString: string): NodeJS.ProcessEnv {
  try {
    const url = parseDatabaseUrl(connectionString, 'libpq');
    const env: NodeJS.ProcessEnv = {};
    // Avoid accidental overrides from inherited libpq settings. Keep PATH for the tools.
    for (const [key, value] of Object.entries(process.env)) {
      if (!key.startsWith('PG') && key !== 'DATABASE_URL' && !key.endsWith('_DATABASE_URL'))
        env[key] = value;
    }
    env.PGHOST = url.hostname.replace(/^\[|\]$/g, '');
    env.PGPORT = url.port || '5432';
    env.PGDATABASE = databaseName;
    env.PGCONNECT_TIMEOUT = '15';
    env.PGAPPNAME = 'hanouti-backup';
    if (url.username) env.PGUSER = decodeURIComponent(url.username);
    if (url.password) env.PGPASSWORD = decodeURIComponent(url.password);
    // Map has no inherited option names; keep the adapter lookup safe independently.
    const options = new Map([
      ['sslmode', 'PGSSLMODE'],
      ['sslrootcert', 'PGSSLROOTCERT'],
      ['sslcert', 'PGSSLCERT'],
      ['sslkey', 'PGSSLKEY'],
      ['connect_timeout', 'PGCONNECT_TIMEOUT'],
    ]);
    for (const [key, value] of url.searchParams) {
      const variable = options.get(key);
      if (!variable) throw new Error();
      env[variable] = value;
    }
    return env;
  } catch {
    // Never include connection strings or parser errors containing credentials.
    throw new Error(
      'Invalid DATABASE_URL: expected a PostgreSQL URL targeting database hanouti; see backup documentation.',
    );
  }
}

export const runTool: ToolRunner = (tool, args, env, timeoutMs) =>
  new Promise((resolve, reject) => {
    const child = spawn(tool, args, {
      env,
      shell: false,
      stdio: ['ignore', 'ignore', 'pipe'],
      timeout: timeoutMs,
      killSignal: 'SIGKILL',
    });
    // Do not forward potentially sensitive tool output into centralized logs.
    child.stderr.resume();
    child.once('error', () =>
      reject(
        new Error(`${tool} could not start; check PostgreSQL client installation and permissions.`),
      ),
    );
    child.once('close', (code, signal) => {
      if (code === 0) resolve();
      else
        reject(
          new Error(
            `${tool} failed (exit ${String(code)}, signal ${signal ?? 'none'}); check credentials, permissions, disk space, tool version and timeout.`,
          ),
        );
    });
  });

export interface BackupOptions {
  root: string;
  connectionString: string;
  timeoutMs?: number;
  now?: () => Date;
  runner?: ToolRunner;
  log?: (entry: Record<string, unknown>) => void;
}

export async function backupDatabase(options: BackupOptions): Promise<string> {
  const runner = options.runner ?? runTool;
  const now = options.now ?? (() => new Date());
  const log = options.log ?? (() => undefined);
  const timeoutMs = options.timeoutMs ?? 30 * 60 * 1000;
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 24 * 60 * 60 * 1000) {
    throw new Error('BACKUP_TIMEOUT_MS must be an integer from 1000 to 86400000.');
  }
  const env = connectionEnvironment(options.connectionString);
  await mkdir(options.root, { recursive: true, mode: 0o700 });
  const lock = join(options.root, '.backup.lock');
  try {
    await mkdir(lock, { mode: 0o700 });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'EEXIST') {
      throw new Error(
        'Backup lock exists. Another backup may be running; investigate before removing .backup.lock.',
        { cause: error },
      );
    }
    throw error;
  }
  let partial: string | undefined;
  let ownsPartial = false;
  try {
    await writeFile(
      join(lock, 'owner.json'),
      JSON.stringify({ pid: process.pid, startedAt: now().toISOString(), database: databaseName }),
      { mode: 0o600 },
    );
    const destination = join(options.root, backupRelativePath(now()));
    partial = `${destination}.partial`;
    await mkdir(dirname(destination), { recursive: true, mode: 0o700 });
    const handle = await open(partial, 'wx', 0o600);
    ownsPartial = true;
    await handle.close();
    log({ level: 'info', event: 'backup.started', database: databaseName });
    // No --schema or table filter: one consistent whole-database snapshot includes all schemas.
    await runner(
      'pg_dump',
      ['--format=custom', '--no-password', '--file', partial],
      env,
      timeoutMs,
    );
    if ((await stat(partial)).size === 0) throw new Error('pg_dump produced an empty archive.');
    await runner('pg_restore', ['--list', partial], env, timeoutMs);
    const archive = await open(partial, 'r+');
    try {
      await archive.sync();
    } finally {
      await archive.close();
    }
    // Atomic publication without overwriting another dump; same-directory hard link.
    await link(partial, destination);
    log({ level: 'info', event: 'backup.completed', database: databaseName, path: destination });
    return destination;
  } catch (error) {
    log({
      level: 'error',
      event: 'backup.failed',
      database: databaseName,
      message: error instanceof Error ? error.message : 'Unknown backup failure',
    });
    throw error;
  } finally {
    try {
      if (ownsPartial && partial) await rm(partial, { force: true });
    } finally {
      await rm(lock, { recursive: true, force: true });
    }
  }
}
