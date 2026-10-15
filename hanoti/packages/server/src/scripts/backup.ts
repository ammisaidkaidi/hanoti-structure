import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';
import dotenv from 'dotenv';
import { backupDatabase } from '../backup.js';

// Resolves correctly from both src/scripts/ and dist/scripts/.
dotenv.config({ path: fileURLToPath(new URL('../../.env', import.meta.url)), quiet: true });
const dataDirectory = process.env.DATA_DIR
  ? resolve(process.env.DATA_DIR)
  : fileURLToPath(new URL('../../../../data/', import.meta.url));

try {
  await backupDatabase({
    root: join(dataDirectory, 'migrations'),
    connectionString: process.env.DATABASE_URL ?? '',
    timeoutMs: Number(process.env.BACKUP_TIMEOUT_MS ?? 1800000),
    log: (entry) => console.log(JSON.stringify({ timestamp: new Date().toISOString(), ...entry })),
  });
} catch (error) {
  console.error(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'error',
      event: 'backup.job_failed',
      message: error instanceof Error ? error.message : 'Unknown backup failure',
    }),
  );
  process.exitCode = 1;
}
