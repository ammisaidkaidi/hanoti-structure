import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import dotenv from 'dotenv';
import { z } from 'zod';

// Both src/ and dist/ sit one level below the package root.
dotenv.config({ path: fileURLToPath(new URL('../.env', import.meta.url)), quiet: true });
const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  CORS_ORIGINS: z.string().default('http://localhost:5173'),
  DATA_DIR: z.string().min(1).optional(),
});
const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  throw new Error(
    `Invalid server environment: ${JSON.stringify(parsed.error.flatten().fieldErrors)}`,
  );
}
export const config = parsed.data;
export const dataDirectory = config.DATA_DIR
  ? resolve(config.DATA_DIR)
  : fileURLToPath(new URL('../../../data/', import.meta.url));
export const allowedOrigins = config.CORS_ORIGINS.split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
