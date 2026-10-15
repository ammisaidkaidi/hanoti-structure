from pathlib import Path
import json
root=Path('/home/user/hanouti')
def put(p,s):
 f=root/p; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(s.strip()+'\n')
def package(p,obj):put(p,json.dumps(obj,indent=2))
package('package.json',{'name':'hanouti','version':'0.1.0','private':True,'type':'module','packageManager':'pnpm@10.34.7','engines':{'node':'>=20.19.0','pnpm':'>=10 <11'},'scripts':{'predev':'pnpm --filter @app/common build','dev':'concurrently --kill-others --names common,server,browser --prefix-colors cyan,yellow,green "pnpm --filter @app/common dev" "pnpm --filter @app/server dev" "pnpm --filter @app/browser dev"','build':'pnpm --filter @app/common build && pnpm --filter @app/server build && pnpm --filter @app/browser build','typecheck':'pnpm --filter @app/common build && pnpm -r typecheck','lint':'eslint . --max-warnings 0','format':'prettier --write .','format:check':'prettier --check .','test':'pnpm --filter @app/common build && pnpm -r --if-present test','check':'pnpm lint && pnpm format:check && pnpm typecheck && pnpm test && pnpm build','start':'pnpm --filter @app/server start'},'devDependencies':{'@eslint/js':'^9.39.0','concurrently':'^9.2.1','eslint':'^9.39.0','eslint-config-prettier':'^10.1.8','eslint-plugin-vue':'^10.5.1','globals':'^16.5.0','prettier':'^3.6.2','typescript':'~5.9.3','typescript-eslint':'^8.46.1'}})
put('pnpm-workspace.yaml',"""
packages:
  - 'packages/*'
  - 'data'
onlyBuiltDependencies:
  - esbuild
""")
put('.npmrc','save-exact=true\nstrict-peer-dependencies=true')
put('.nvmrc','22')
put('.gitignore','node_modules/\ndist/\ncoverage/\n*.tsbuildinfo\n.env\n.env.*\n!.env.example\n*.log\n.DS_Store\n.vscode/\n.idea/')
put('.prettierignore','node_modules\ndist\ncoverage\npnpm-lock.yaml')
put('.prettierrc.json','{"singleQuote": true, "trailingComma": "all", "printWidth": 100}')
put('.editorconfig','root = true\n\n[*]\ncharset = utf-8\nindent_style = space\nindent_size = 2\nend_of_line = lf\ninsert_final_newline = true\ntrim_trailing_whitespace = true')
package('tsconfig.base.json',{'compilerOptions':{'target':'ES2022','lib':['ES2022'],'strict':True,'noUncheckedIndexedAccess':True,'exactOptionalPropertyTypes':True,'noImplicitOverride':True,'noFallthroughCasesInSwitch':True,'forceConsistentCasingInFileNames':True,'esModuleInterop':True,'skipLibCheck':True,'verbatimModuleSyntax':True,'resolveJsonModule':True}})
put('eslint.config.js',"""
import js from '@eslint/js';
import ts from 'typescript-eslint';
import vue from 'eslint-plugin-vue';
import globals from 'globals';
import prettier from 'eslint-config-prettier';
export default ts.config(
  { ignores: ['**/dist/**', '**/node_modules/**', '**/coverage/**'] },
  js.configs.recommended,
  ...ts.configs.recommended,
  ...vue.configs['flat/recommended'],
  { languageOptions: { globals: { ...globals.node, ...globals.browser } } },
  { files: ['**/*.vue'], languageOptions: { parserOptions: { parser: ts.parser, extraFileExtensions: ['.vue'] } } },
  { rules: { 'vue/multi-word-component-names': 'off' } },
  prettier,
);
""")
package('packages/common/package.json',{'name':'@app/common','version':'0.1.0','private':True,'type':'module','files':['dist'],'exports':{'.':{'types':'./dist/index.d.ts','import':'./dist/index.js'}},'scripts':{'build':'tsc -p tsconfig.json','dev':'tsc -p tsconfig.json --watch --preserveWatchOutput','typecheck':'tsc -p tsconfig.json --noEmit','test':'vitest run'},'dependencies':{'zod':'^4.1.12'},'devDependencies':{'typescript':'~5.9.3','vitest':'^3.2.4'}})
package('packages/common/tsconfig.json',{'extends':'../../tsconfig.base.json','compilerOptions':{'module':'NodeNext','moduleResolution':'NodeNext','rootDir':'src','outDir':'dist','declaration':True,'declarationMap':True,'sourceMap':True},'include':['src/**/*.ts']})
put('packages/common/src/index.ts',"""
import { z } from 'zod';

// Runtime schemas and inferred types: one contract for both applications.
export const greetingRequestSchema = z.object({
  name: z.string().trim().min(1, 'Please enter your name.').max(80, 'Use 80 characters or fewer.'),
}).strict();
export const greetingResponseSchema = z.object({ message: z.string() });
export const healthResponseSchema = z.object({
  status: z.literal('ok'),
  service: z.literal('hanouti-server'),
  timestamp: z.iso.datetime(),
});
export type GreetingRequest = z.infer<typeof greetingRequestSchema>;
export type GreetingResponse = z.infer<typeof greetingResponseSchema>;
export type HealthResponse = z.infer<typeof healthResponseSchema>;
""")
put('packages/common/tests/schemas.test.ts',"""
import { describe, expect, it } from 'vitest';
import { greetingRequestSchema, healthResponseSchema } from '../src/index.js';
describe('shared contracts', () => {
  it('trims valid names', () => {
    expect(greetingRequestSchema.parse({ name: '  Hanouti  ' })).toEqual({ name: 'Hanouti' });
  });
  it.each(['', '   ', 'x'.repeat(81)])('rejects invalid names', (name) => {
    expect(greetingRequestSchema.safeParse({ name }).success).toBe(false);
  });
  it('rejects unknown request fields', () => {
    expect(greetingRequestSchema.safeParse({ name: 'Ada', admin: true }).success).toBe(false);
  });
  it('validates the health contract', () => {
    expect(healthResponseSchema.safeParse({ status: 'ok', service: 'hanouti-server', timestamp: new Date().toISOString() }).success).toBe(true);
  });
});
""")
package('packages/server/package.json',{'name':'@app/server','version':'0.1.0','private':True,'type':'module','scripts':{'dev':'tsx watch --include "../common/dist/**/*.js" src/index.ts','build':'tsc -p tsconfig.json','start':'node --enable-source-maps dist/index.js','typecheck':'tsc -p tsconfig.json --noEmit && tsc -p tsconfig.test.json','test':'vitest run'},'dependencies':{'@app/common':'workspace:*','@app/data':'workspace:*','cors':'^2.8.5','dotenv':'^17.2.3','express':'^5.1.0','helmet':'^8.1.0','zod':'^4.1.12'},'devDependencies':{'@types/cors':'^2.8.19','@types/express':'^5.0.3','@types/node':'^22.18.12','@types/supertest':'^6.0.3','supertest':'^7.1.4','tsx':'^4.20.6','typescript':'~5.9.3','vitest':'^3.2.4'}})
package('packages/server/tsconfig.json',{'extends':'../../tsconfig.base.json','compilerOptions':{'module':'NodeNext','moduleResolution':'NodeNext','types':['node'],'rootDir':'src','outDir':'dist','sourceMap':True},'include':['src/**/*.ts']})
package('packages/server/tsconfig.test.json',{'extends':'./tsconfig.json','compilerOptions':{'rootDir':'.','noEmit':True},'include':['src/**/*.ts','tests/**/*.ts']})
put('packages/server/.env.example','NODE_ENV=development\nHOST=0.0.0.0\nPORT=3000\nCORS_ORIGINS=http://localhost:5173\n# Optional absolute path; defaults to the workspace data directory.\n# DATA_DIR=/absolute/path/to/hanouti/data')
put('packages/server/src/config.ts',"""
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
  throw new Error(`Invalid server environment: ${JSON.stringify(parsed.error.flatten().fieldErrors)}`);
}
export const config = parsed.data;
export const dataDirectory = config.DATA_DIR
  ? resolve(config.DATA_DIR)
  : fileURLToPath(new URL('../../../data/', import.meta.url));
export const allowedOrigins = config.CORS_ORIGINS.split(',').map((origin) => origin.trim()).filter(Boolean);
""")
put('packages/server/src/app.ts',"""
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import express, { type ErrorRequestHandler } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { z } from 'zod';
import { greetingRequestSchema, type GreetingResponse, type HealthResponse } from '@app/common';
import { allowedOrigins, dataDirectory } from './config.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {
    res.locals.requestId = randomUUID();
    res.setHeader('X-Request-Id', String(res.locals.requestId));
    next();
  });
  app.use(helmet());
  app.use(cors({
    origin: (origin, callback) => callback(null, !origin || allowedOrigins.includes(origin)),
  }));
  app.use(express.json({ limit: '32kb' }));

  app.get('/api/health', (_req, res) => {
    const body: HealthResponse = { status: 'ok', service: 'hanouti-server', timestamp: new Date().toISOString() };
    res.json(body);
  });
  app.post('/api/greetings', async (req, res) => {
    const parsed = greetingRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: 'Validation failed', issues: parsed.error.flatten(), requestId: res.locals.requestId });
      return;
    }
    // Direct server-only access. data/ is never mounted as a public static directory.
    const asset = JSON.parse(await readFile(join(dataDirectory, 'assets/welcome.json'), 'utf8')) as unknown;
    const { prefix } = z.object({ prefix: z.string() }).parse(asset);
    const body: GreetingResponse = { message: `${prefix}, ${parsed.data.name}. Your workspace is ready.` };
    res.json(body);
  });
  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found', requestId: res.locals.requestId });
  });
  const handleError: ErrorRequestHandler = (error: unknown, _req, res, _next) => {
    const status = typeof error === 'object' && error !== null && 'status' in error ? error.status : undefined;
    if (status === 400 || status === 413 || status === 415) {
      res.status(status).json({ error: status === 413 ? 'Request too large' : status === 415 ? 'Unsupported encoding' : 'Malformed request', requestId: res.locals.requestId });
      return;
    }
    console.error(JSON.stringify({ level: 'error', requestId: res.locals.requestId, message: error instanceof Error ? error.message : 'Unknown error' }));
    res.status(500).json({ error: 'Internal server error', requestId: res.locals.requestId });
  };
  app.use(handleError);
  return app;
}
""")
put('packages/server/src/index.ts',"""
import { createApp } from './app.js';
import { config } from './config.js';
const server = createApp().listen(config.PORT, config.HOST, () => {
  console.info(JSON.stringify({ level: 'info', message: 'Hanouti API listening', host: config.HOST, port: config.PORT }));
});
server.on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.info(JSON.stringify({ level: 'info', message: 'Shutting down', signal }));
  const timeout = setTimeout(() => process.exit(1), 10_000);
  timeout.unref();
  server.close((error) => {
    clearTimeout(timeout);
    process.exit(error ? 1 : 0);
  });
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
""")
put('packages/server/tests/app.test.ts',"""
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { greetingResponseSchema, healthResponseSchema } from '@app/common';
import { createApp } from '../src/app.js';
const app = createApp();
describe('API', () => {
  it('returns a typed health response and security headers', async () => {
    const res = await request(app).get('/api/health').expect(200);
    expect(healthResponseSchema.safeParse(res.body).success).toBe(true);
    expect(res.headers['x-request-id']).toBeTruthy();
    expect(res.headers['x-content-type-options']).toBe('nosniff');
  });
  it('reads a server-side data asset and returns a greeting', async () => {
    const res = await request(app).post('/api/greetings').send({ name: ' Ada ' }).expect(200);
    expect(greetingResponseSchema.parse(res.body).message).toBe('Welcome aboard, Ada. Your workspace is ready.');
  });
  it('rejects invalid input', async () => {
    await request(app).post('/api/greetings').send({ name: ' ' }).expect(400);
  });
  it('handles malformed JSON', async () => {
    await request(app).post('/api/greetings').set('Content-Type', 'application/json').send('{').expect(400);
  });
  it('limits JSON payloads', async () => {
    await request(app).post('/api/greetings').send({ name: 'x'.repeat(40000) }).expect(413);
  });
  it('does not expose database assets', async () => {
    await request(app).get('/data/assets/welcome.json').expect(404);
  });
  it('allows only configured browser origins', async () => {
    const allowed = await request(app).get('/api/health').set('Origin', 'http://localhost:5173');
    const denied = await request(app).get('/api/health').set('Origin', 'https://untrusted.example');
    expect(allowed.headers['access-control-allow-origin']).toBe('http://localhost:5173');
    expect(denied.headers['access-control-allow-origin']).toBeUndefined();
  });
});
""")
package('data/package.json',{'name':'@app/data','version':'0.1.0','private':True,'description':'Server-only SQL migrations, seeds and runtime assets','files':['migrations','seeds','assets','README.md']})
put('data/assets/welcome.json','{"prefix": "Welcome aboard"}')
put('data/migrations/001_create_app_settings.sql',"""
-- PostgreSQL example; apply with a migration tool you choose, not on server startup.
BEGIN;
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMIT;
""")
put('data/seeds/001_development_settings.sql',"""
-- Development seed. Apply after migrations; safe to rerun.
INSERT INTO app_settings (key, value)
VALUES ('workspace', '{"name":"Hanouti"}'::jsonb)
ON CONFLICT (key) DO NOTHING;
""")
put('data/README.md',"""
# Server-only data

- `migrations/`: ordered, immutable SQL schema changes.
- `seeds/`: explicit, environment-specific seed data.
- `assets/`: runtime files read by the server. Never put secrets here.

The SQL examples target PostgreSQL. No database driver, migration runner, or database connection is configured. The API runs without a database. Choose a migration tool (for example node-pg-migrate) and database credentials before applying these SQL files. Track applied versions and test rollbacks in staging. Do not run seeds automatically in production.

`@app/data` is a private workspace package and a server-only dependency. The server reads `assets/welcome.json` using an absolute path resolved from `import.meta.url`, so both `src/` and `dist/` work. `DATA_DIR` can override the location. Keep the `data/` directory when deploying; never serve this directory as static content or import it into the browser.
""")
package('packages/browser/package.json',{'name':'@app/browser','version':'0.1.0','private':True,'type':'module','scripts':{'dev':'vite --host 0.0.0.0','build':'vue-tsc --noEmit && vite build','preview':'vite preview --host 0.0.0.0','typecheck':'vue-tsc --noEmit'},'dependencies':{'@app/common':'workspace:*','vue':'^3.5.24'},'devDependencies':{'@types/node':'^22.18.12','@vitejs/plugin-vue':'^6.0.1','autoprefixer':'^10.4.22','postcss':'^8.5.6','tailwindcss':'^3.4.18','typescript':'~5.9.3','vite':'^7.3.7','vue-tsc':'^3.1.1'}})
package('packages/browser/tsconfig.json',{'extends':'../../tsconfig.base.json','compilerOptions':{'lib':['ES2022','DOM','DOM.Iterable'],'module':'ESNext','moduleResolution':'Bundler','noEmit':True,'isolatedModules':True,'types':['vite/client','node']},'include':['src/**/*.ts','src/**/*.vue','vite.config.ts']})
put('packages/browser/vite.config.ts',"""
import { defineConfig, loadEnv } from 'vite';
import vue from '@vitejs/plugin-vue';
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [vue()],
    server: {
      host: '0.0.0.0',
      port: 5173,
      strictPort: true,
      // Trusted hosted-preview suffix; never use allowedHosts: true.
      allowedHosts: ['.e2b.app'],
      proxy: { '/api': { target: env.API_PROXY_TARGET || 'http://127.0.0.1:3000', changeOrigin: true } },
    },
    preview: { host: '0.0.0.0', allowedHosts: ['.e2b.app'] },
  };
});
""")
put('packages/browser/tailwind.config.js',"""
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: { ink: '#14241e', canvas: '#f6f7f3', leaf: '#267b51' },
      fontFamily: { sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
};
""")
put('packages/browser/postcss.config.js',"export default { plugins: { tailwindcss: {}, autoprefixer: {} } };")
put('packages/browser/.env.example','# Server-side Vite proxy target, not exposed in the browser bundle.\nAPI_PROXY_TARGET=http://127.0.0.1:3000')
put('packages/browser/index.html','<!doctype html>\n<html lang="en"><head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" /><meta name="theme-color" content="#14241e" /><meta name="description" content="Hanouti full-stack workspace starter" /><title>Hanouti · Workspace</title><link rel="icon" type="image/svg+xml" href="/favicon.svg" /></head><body><div id="app"></div><script type="module" src="/src/main.ts"></script></body></html>')
put('packages/browser/public/favicon.svg','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><rect width="40" height="40" rx="12" fill="#14241e"/><path d="M12 10v20m16-20v20M12 20h16" stroke="#b8e9b1" stroke-width="4"/></svg>')
put('packages/browser/src/vite-env.d.ts','/// <reference types="vite/client" />')
put('packages/browser/src/main.ts',"import { createApp } from 'vue';\nimport App from './App.vue';\nimport './style.css';\ncreateApp(App).mount('#app');")
put('packages/browser/src/style.css',"""
@tailwind base;
@tailwind components;
@tailwind utilities;
@layer base {
  body { @apply m-0 bg-canvas text-ink antialiased; }
  button, input, a { @apply focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-leaf focus-visible:ring-offset-4; }
  ::selection { background: #ccebc5; }
}
""")
put('packages/browser/src/api.ts',"""
import { greetingRequestSchema, greetingResponseSchema, healthResponseSchema, type GreetingRequest } from '@app/common';
async function request(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(path, { ...init, signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error(`API request failed (${response.status}). Please try again.`);
  return response.json() as Promise<unknown>;
}
export async function getHealth() {
  return healthResponseSchema.parse(await request('/api/health'));
}
export async function sendGreeting(input: GreetingRequest) {
  return greetingResponseSchema.parse(await request('/api/greetings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(greetingRequestSchema.parse(input)),
  }));
}
""")
put('packages/browser/src/App.vue',"""
<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { greetingRequestSchema } from '@app/common';
import { getHealth, sendGreeting } from './api';

const health = ref<'checking' | 'online' | 'offline'>('checking');
const checkedAt = ref('');
const name = ref('');
const busy = ref(false);
const message = ref('');
const error = ref('');
const packages = [
  { code: '01', name: 'Common', path: 'packages/common', description: 'One source of truth. Shared types and runtime validation across the stack.', tags: ['TypeScript', 'Zod'], symbol: '◇' },
  { code: '02', name: 'Browser', path: 'packages/browser', description: 'A fast, reactive interface with type-safe API calls and utility-first styling.', tags: ['Vue 3', 'Vite', 'Tailwind CSS'], symbol: '▣' },
  { code: '03', name: 'Server', path: 'packages/server', description: 'A focused API with validated requests, security headers and hot reloading.', tags: ['Express', 'Node.js', 'tsx'], symbol: '⌘' },
  { code: '04', name: 'Data', path: 'data', description: 'A dedicated home for SQL migrations, development seeds and private assets.', tags: ['SQL assets', 'Server-only'], symbol: '▤' },
];
async function checkHealth() {
  health.value = 'checking';
  try {
    const response = await getHealth();
    health.value = 'online';
    checkedAt.value = new Date(response.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch { health.value = 'offline'; }
}
async function submit() {
  message.value = '';
  error.value = '';
  const parsed = greetingRequestSchema.safeParse({ name: name.value });
  if (!parsed.success) { error.value = parsed.error.issues[0]?.message ?? 'Check your name.'; return; }
  busy.value = true;
  try { message.value = (await sendGreeting(parsed.data)).message; }
  catch (cause) { error.value = cause instanceof Error ? cause.message : 'Unable to reach the API.'; }
  finally { busy.value = false; }
}
onMounted(checkHealth);
</script>

<template>
  <div class="min-h-screen lg:grid lg:grid-cols-[232px_1fr]">
    <aside class="flex flex-col bg-ink px-7 py-7 text-white lg:sticky lg:top-0 lg:h-screen">
      <a href="#overview" class="flex items-center gap-3 text-xl font-semibold tracking-tight" aria-label="Hanouti home">
        <span class="flex h-9 w-9 items-center justify-center rounded-xl bg-[#b8e9b1] font-mono text-xl text-ink">h.</span> hanouti<span class="text-[#b8e9b1]">.</span>
      </a>
      <div class="mt-12 hidden text-[10px] font-semibold uppercase tracking-[0.2em] text-white/40 lg:block">Your workspace</div>
      <nav class="mt-5 flex gap-2 lg:flex-col" aria-label="Workspace navigation">
        <a href="#overview" class="rounded-lg bg-white/10 px-4 py-3 text-sm font-medium text-[#c9edc3]">◫ <span class="ml-2">Overview</span></a>
        <a href="#architecture" class="rounded-lg px-4 py-3 text-sm text-white/60 transition hover:bg-white/5 hover:text-white">◇ <span class="ml-2">Architecture</span></a>
        <a href="#playground" class="rounded-lg px-4 py-3 text-sm text-white/60 transition hover:bg-white/5 hover:text-white">⌁ <span class="ml-2">API playground</span></a>
      </nav>
      <div class="mt-auto hidden border-t border-white/10 pt-6 lg:block">
        <p class="font-mono text-xs text-[#c9edc3]">pnpm workspace</p>
        <p class="mt-2 text-xs leading-6 text-white/40">Four packages.<br />One connected foundation.</p>
        <div class="mt-5 flex items-center justify-between text-[10px] uppercase tracking-widest text-white/30"><span>Starter edition</span><span>v0.1.0</span></div>
      </div>
    </aside>

    <div class="min-w-0">
      <header class="flex items-center justify-between border-b border-black/[0.07] px-6 py-5 lg:px-12">
        <div class="text-xs text-gray-500">Workspace <span class="mx-3 text-gray-300">/</span> <span class="text-ink">Overview</span></div>
        <span class="rounded-full border border-black/10 bg-white px-3 py-1 font-mono text-[10px] text-gray-500">FULL-STACK STARTER</span>
      </header>
      <main id="overview" class="mx-auto max-w-[1320px] px-6 py-10 lg:px-12 lg:py-12">
        <div class="flex flex-wrap items-start justify-between gap-5">
          <div><p class="text-[10px] font-semibold uppercase tracking-[0.22em] text-leaf">A foundation for what’s next</p><h1 class="mt-3 text-4xl font-medium tracking-[-0.045em] sm:text-5xl">Make yourself at home.</h1><p class="mt-4 max-w-xl text-sm leading-7 text-gray-500">Your full-stack workspace, connected from day one.<br class="hidden sm:block" /> Less setup. More room to build something great.</p></div>
          <button :disabled="health === 'checking'" class="flex items-center gap-2 rounded-full border border-black/10 bg-white px-4 py-2.5 text-xs disabled:opacity-60" title="Refresh API health" @click="checkHealth"><span class="h-1.5 w-1.5 rounded-full" :class="health === 'online' ? 'bg-leaf' : health === 'offline' ? 'bg-amber-500' : 'animate-pulse bg-gray-400'"></span>{{ health === 'online' ? 'API connected' : health === 'offline' ? 'API offline · Retry' : 'Connecting…' }}<span class="ml-1 text-gray-400">↻</span></button>
        </div>

        <section class="relative mt-9 overflow-hidden rounded-2xl bg-[#e7eddf] p-7 sm:p-8" aria-label="Quick start">
          <div class="pointer-events-none absolute -right-6 -top-14 h-64 w-64 rounded-full border-[35px] border-[#d5dfca]/60" aria-hidden="true"></div>
          <div class="relative flex flex-wrap items-center justify-between gap-6">
            <div><span class="rounded-md bg-white/60 px-2 py-1 text-[9px] font-bold uppercase tracking-widest text-leaf">Ready when you are</span><h2 class="mt-4 text-2xl font-medium tracking-tight">One command. The whole stack.</h2><p class="mt-2 text-xs leading-6 text-gray-600">Run from the repository root to start all three development watchers.</p></div>
            <div class="min-w-[235px] rounded-xl bg-ink px-6 py-5 text-white shadow-lg"><div class="mb-3 flex gap-1.5" aria-hidden="true"><i class="h-1.5 w-1.5 rounded-full bg-white/20"></i><i class="h-1.5 w-1.5 rounded-full bg-white/20"></i><i class="h-1.5 w-1.5 rounded-full bg-white/20"></i></div><code class="text-sm"><span class="mr-3 text-[#a4d99b]">$</span>pnpm dev</code></div>
          </div>
        </section>

        <section id="architecture" class="scroll-mt-8 pt-10">
          <div class="mb-5 flex items-center justify-between"><h2 class="text-lg font-medium tracking-tight">Built to work together</h2><span class="font-mono text-[10px] uppercase tracking-widest text-gray-400">04 workspace packages</span></div>
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <article v-for="pkg in packages" :key="pkg.name" class="rounded-xl border border-black/[0.08] bg-white p-5 transition hover:border-leaf/30">
              <div class="flex items-center justify-between"><span class="flex h-10 w-10 items-center justify-center rounded-lg bg-canvas text-2xl text-leaf" aria-hidden="true">{{ pkg.symbol }}</span><span class="font-mono text-[10px] text-gray-300">{{ pkg.code }}</span></div>
              <h3 class="mt-5 text-base font-semibold">{{ pkg.name }}</h3><p class="mt-1 font-mono text-[10px] text-leaf">{{ pkg.path }}</p><p class="mt-4 min-h-[66px] text-xs leading-[1.8] text-gray-500">{{ pkg.description }}</p>
              <div class="mt-5 flex flex-wrap gap-1.5"><span v-for="tag in pkg.tags" :key="tag" class="rounded border border-black/5 bg-canvas px-2 py-1 text-[9px] text-gray-500">{{ tag }}</span></div>
            </article>
          </div>
        </section>

        <section id="playground" class="mt-8 grid scroll-mt-8 overflow-hidden rounded-xl border border-black/[0.08] bg-white md:grid-cols-[1fr_1.1fr]">
          <div class="p-6 sm:p-7"><div class="flex items-center gap-2"><span class="h-1.5 w-1.5 rounded-full bg-leaf"></span><p class="text-[10px] font-semibold uppercase tracking-widest text-leaf">End-to-end, by design</p></div><h2 class="mt-3 text-xl font-medium tracking-tight">Say hello to your API.</h2><p class="mt-3 max-w-sm text-xs leading-6 text-gray-500">A real request from Vue to Express. Validated with your shared Zod schema, with a greeting from a server-side data asset.</p><p class="mt-5 font-mono text-[10px] text-gray-400"><span class="mr-2 text-leaf">POST</span> /api/greetings</p></div>
          <form class="flex flex-col justify-center border-t border-black/[0.06] bg-[#fbfcf9] p-6 sm:p-7 md:border-l md:border-t-0" @submit.prevent="submit">
            <label for="name" class="mb-2 text-xs font-medium">What should we call you?</label><div class="flex flex-wrap gap-2"><input id="name" v-model="name" autocomplete="given-name" placeholder="Your name" maxlength="80" :aria-invalid="!!error" aria-describedby="greeting-result" class="min-w-0 flex-1 rounded-lg border border-black/15 bg-white px-4 py-3 text-sm placeholder:text-gray-400" /><button type="submit" :disabled="busy" class="rounded-lg bg-ink px-5 py-3 text-xs font-medium text-white transition hover:bg-leaf disabled:opacity-50">{{ busy ? 'Sending…' : 'Send greeting' }} <span class="ml-2" aria-hidden="true">↗</span></button></div>
            <p id="greeting-result" role="status" class="mt-3 min-h-8 text-xs leading-5" :class="error ? 'text-red-700' : message ? 'text-leaf' : 'text-gray-400'">{{ error || message || 'Shared types. Runtime validation. A connected stack.' }}</p>
          </form>
        </section>
        <footer class="mt-8 flex flex-wrap items-center justify-between gap-3 border-t border-black/[0.07] pt-5 text-[10px] text-gray-400"><span>Hanouti <span class="mx-2">/</span> A little structure. A lot of possibility.</span><span>{{ health === 'online' ? `API checked at ${checkedAt}` : 'Start the server to connect the API' }}</span></footer>
      </main>
    </div>
  </div>
</template>
""")
put('.github/workflows/ci.yml',"""
name: CI
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm check
""")
