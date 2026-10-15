# Hanouti

A pnpm monorepo starter for a Vue 3 frontend and an Express API, with a shared TypeScript/Zod contract and private server-side data assets.

## Requirements

- Node.js **22 LTS recommended** (`.nvmrc`); supported Node ranges: `^20.19.0 || ^22.13.0 || >=24.11.0` (TypeORM runtime requirement).
- pnpm **10.34.7**, pinned in `packageManager`.

If pnpm is not installed:

```sh
npm install --global pnpm@10.34.7
```

Alternatively, with Corepack installed: `corepack enable && corepack prepare pnpm@10.34.7 --activate`.

## Quick start

Run all commands from the **repository root**:

### 1. Install every workspace dependency

```sh
cd hanoti
pnpm install
```

The lockfile is committed for reproducible installs. CI uses `pnpm install --frozen-lockfile`.

### 2. Configure local environment files (optional)

Defaults work out of the box. To customize them:

```sh
cp packages/server/.env.example packages/server/.env
cp packages/browser/.env.example packages/browser/.env
```

PowerShell users can use `Copy-Item` instead of `cp`. These `.env` files are git-ignored.

### 3. Start the complete development stack

```sh
pnpm dev
```

The root `predev` script builds `@app/common` and `@app/data` first, preventing missing-module errors on a clean checkout. Then `concurrently` starts:

| Process | Purpose                                      | Address               |
| ------- | -------------------------------------------- | --------------------- |
| Common  | TypeScript compiler in watch mode            | No HTTP server        |
| Data    | TypeORM package compiler in watch mode       | No HTTP server        |
| Server  | `tsx watch`, including shared compiled files | http://localhost:3000 |
| Browser | Vite with Vue HMR                            | http://localhost:5173 |

Open **http://localhost:5173**. The landing page checks the real API and includes a greeting form that demonstrates the full frontend → shared schema → server → private data asset flow. `Ctrl+C` stops all four processes; an exited process stops the others.

Both servers bind to `0.0.0.0` for containers and hosted previews. Use a firewall or bind to loopback for strictly local work. Vite accepts the trusted `.e2b.app` preview domain. Remove that suffix if not needed, or replace it with your own trusted development domain; do not disable host checking globally.

### 4. Verify the workspace

```sh
pnpm check
```

This runs lint, formatting checks, type checking, schema/API tests, and production builds. You can also run each separately:

```sh
pnpm lint
pnpm format:check
pnpm format
pnpm typecheck
pnpm test
pnpm build
```

## Layout

```text
workspace/
├── .test/                          @app/tests: sibling test/support workspace
│   ├── api/                        API prototype tests and test tsconfig
│   ├── data/                       ORM/SQL tests, fixtures and offline validator
│   ├── packages/common/            Shared-library tests
│   ├── packages/server/            Server/backup tests
│   ├── archive/                    Historical helpers and fragments; do not run
│   ├── logs/                       Historical local output
│   ├── artifacts/                  Downloadable ZIP, excluded from itself
│   ├── vitest.config.ts
│   └── package.json
└── hanoti/                        Application and pnpm workspace root
    ├── docs/architecture/baseline/  Historical code snapshots, not active source
    ├── api/                        @app/api: unwired ERP async prototypes
    │   ├── erp/                    Functions grouped by ERP task
    │   └── common/                 API contracts and reusable helpers
    ├── packages/
    │   ├── common/                 @app/common: shared runtime schemas/types
    │   ├── browser/                @app/browser: Vue, Vite, Tailwind and PostCSS
    │   └── server/                 @app/server: Express, TypeScript and pg
    ├── data/                       @app/data: server-only ORM code and assets
    │   ├── code/
    │   ├── migrations/hanouti/
    │   ├── seeds/
    │   ├── assets/
    │   └── scripts/generate_entities.py
    ├── .github/workflows/ci.yml
    ├── eslint.config.js
    ├── tsconfig.base.json
    ├── pnpm-lock.yaml
    ├── pnpm-workspace.yaml
    └── package.json
```

`pnpm-workspace.yaml` includes `packages/*` and `data`. All packages are private. Both apps depend on `@app/common` using `workspace:*`; the server also declares `@app/data` as a workspace dependency. Internal packages are never fetched from the public registry.

## Shared code and rebuilds

`@app/common` exports compiled ESM and TypeScript declarations from `dist/`. Keep it browser-safe: no Node built-ins, environment secrets, database code, or server assets. Export runtime schemas from `src/index.ts` and derive types with `z.infer`.

Build ordering is explicit: common → data → server → browser. During development, the common compiler updates `dist`, `tsx` watches those changes, and Vite updates the browser through its linked workspace dependency. If running one app directly, build common first (and data before the server):

```sh
pnpm --filter @app/common build
pnpm --filter @app/browser dev
# Or, in another terminal:
pnpm --filter @app/data build
pnpm --filter @app/server dev
```

Use root `pnpm dev` to continuously compile both common and data. Data is never imported into the frontend.

Tailwind CSS **3** is intentional: its classic configuration supplies both the requested `tailwind.config.js` and PostCSS configuration. Tailwind directives are loaded in `src/style.css`, and content scanning includes all Vue/TypeScript source files.

## AutomateGraph

`@app/common` depends on `automategraph` and re-exports its main, isomorphic API and TypeScript types. Both apps can import the engine through the shared package:

```ts
import { GraphExecutionEngine, Next, type GraphDefinition } from '@app/common';
```

Only the main entry point is re-exported. The optional `automategraph/graph-json` entry point and Node-only `automategraph/node/graph-scripts` loader are not included. Keep script loading server-side, and never execute untrusted graph functions or scripts in the API process.

To update this dependency, use pnpm from the repository root rather than creating a separate npm lockfile:

```sh
pnpm --filter @app/common update automategraph
```

## Smart Hybrid Search

`@app/common` also re-exports the main API and TypeScript types from `smart-hybrid-search`. Both applications can use the local search engine:

```ts
import { SearchService, type Product } from '@app/common';

const products: Product[] = []; // Populate with your catalog.
const search = new SearchService(products);
const result = search.search('coffee');
```

The package provides hybrid search, spelling correction, and Arabic/French/English language support. Installing it does not create a search endpoint or connect a product database. Its optional `HttpSearchService` requires a compatible HTTP backend; none is configured by this change. For large or private catalogs, keep the index on the server rather than shipping it to the browser.

Update from the repository root with `pnpm --filter @app/common update smart-hybrid-search`.

## HTTP Negotiation Protocol

`http-negotiation-protocol` is installed in `@app/common`. Upstream exposes separate `/client` and `/server` entry points, not a root entry point. The shared package preserves that runtime boundary:

```ts
// Browser-safe client API (also available from '@app/common').
import { NegotiationClient, ClientAuthManager } from '@app/common/negotiation/client';

// Node-only: import exclusively in server-side code.
import { NegotiationServer, MemoryRequestStore } from '@app/common/negotiation/server';
```

All public client exports are available from the shared root; server exports are deliberately excluded from it. Never import `@app/common/negotiation/server` into browser code. Browser authentication helpers require a secure context (HTTPS or localhost) for Web Crypto.

This change installs and re-exports the library only. No negotiation routes, callbacks, authentication flow, credential storage, or PostgreSQL connection are enabled. The library brings an optional `pg` dependency; installing it does not configure a database. Review the library's authentication design and your application's security requirements before adopting its authentication helpers.

Update from the repository root with `pnpm --filter @app/common update http-negotiation-protocol`.

## API and environment

| Route                 | Behavior                                                       |
| --------------------- | -------------------------------------------------------------- |
| `GET /api/health`     | Liveness, service name, UTC timestamp                          |
| `POST /api/greetings` | Validates `{ "name": "Ada" }` and returns `{ "message": "…" }` |

```sh
curl http://localhost:3000/api/health
curl -X POST http://localhost:3000/api/greetings \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada"}'
```

The browser validates requests **and** responses with shared schemas. It sends relative `/api` requests, and the Vite server proxies them to the API. The browser never calls a hard-coded localhost backend. Fetch requests have an eight-second timeout and display failures in the UI.

| Variable           | Location                           | Default / purpose                                                                       |
| ------------------ | ---------------------------------- | --------------------------------------------------------------------------------------- |
| `NODE_ENV`         | Server environment                 | `development`; set `production` when deployed                                           |
| `HOST`             | Server environment                 | `0.0.0.0`                                                                               |
| `PORT`             | Server environment                 | `3000`                                                                                  |
| `CORS_ORIGINS`     | Server environment                 | `http://localhost:5173`; comma-separated allowlist                                      |
| `DATA_DIR`         | Server environment                 | Optional path overriding the repository `data/` folder; use an absolute deployment path |
| `API_PROXY_TARGET` | Browser `.env` (Vite process only) | `http://127.0.0.1:3000`                                                                 |

The server loads `packages/server/.env` relative to the module, not the shell's working directory. Existing process environment values take precedence. If you change the API port, change `API_PROXY_TARGET` too and restart development. Do not put secrets in any `VITE_*` variables: those are public client values.

CORS controls browser access, **not authentication**. The API adds Helmet security headers, generates request IDs, limits JSON body size, returns safe error messages, validates environment variables, and shuts down gracefully on SIGINT/SIGTERM. `/api/health` is a liveness check, not a database readiness check.

## Data and database lifecycle

`data/` is a managed workspace package, not a service or public directory. The server references its files directly with an absolute path derived from `import.meta.url`. This works from both `packages/server/src` and `packages/server/dist`, without copying private assets into browser bundles.

The included SQL is a **PostgreSQL example**. The `pg` driver is installed in `@app/server`, with `@types/pg` as a development dependency. No connection pool, database credentials, migration CLI, or migration history table has been configured. The API still runs without a database, and nothing executes SQL automatically. Configure the PostgreSQL connection and choose migration tooling before applying migrations. See `data/README.md`.

The project now uses **one PostgreSQL database, `hanouti`**, with four business schemas: `auth`, `erp`, `app`, and `settings`. The old separate-database layout is retired. `data/seeds/000_create_database.sql` declares hanouti provisioning only. Eleven ordered SQL files under `data/migrations/hanouti/` declare all 30 tables and the permission-aware ERP routines in one migration history; no SQL has been executed.

### Schema declarations and TypeORM

| Schema   | Tables | TypeScript namespace                                                   |
| -------- | -----: | ---------------------------------------------------------------------- |
| auth     |     10 | `Auth.User`, `Auth.Role`, ...                                          |
| erp      |     13 | `Erp.Product`, `Erp.Customer`, ...                                     |
| app      |      5 | `App.File`, `App.AuditEvent`, ...                                      |
| settings |      3 | `Settings.SettingDefinition`, `Settings.GSettings`, `Settings.Setting` |

All classes live under `data/code/entities/{schema}/` and are registered in **one DataSource**. Use `DATABASE_URL` targeting `/hanouti`, `createDataSource()`, and explicit `initializeDataSource()` / `destroyDataSource()` helpers. There is no API lifecycle integration or automatic synchronization, migration, or extension installation. Cross-schema operations can use one transaction manager.

Direct references now use cross-schema foreign keys where appropriate. Polymorphic membership/setting targets still require application validation. Existing quantity/stock rules, fiscal fields and 4096-dimensional embeddings are retained. See [data/SCHEMA.md](data/SCHEMA.md) and [data/TYPEORM.md](data/TYPEORM.md).

### Approved settings and permissions

Business settings use `settings.*`; permissions and party memberships use `auth.*`. Negative document quantities and negative stock balances remain separate policies. Client access covers own invoice drafts/requests, not final issuance. Only explicitly overridable most-specific settings may relax global values; authorization denies and fixed integrity constraints still win. No policy/grant seeds or resolver have been enabled. Unapplied SQL functions now declare the approved operational starter and full settings resolver; optional catalog and privilege scripts remain separate. See [data/ERP_ROUTINES.md](data/ERP_ROUTINES.md). See [data/SETTINGS_SCHEMA.md](data/SETTINGS_SCHEMA.md).

### Exclusive draft editing

Sales and purchase drafts store five-minute renewable locks directly on their headers (`locked_by`, `locked_at`, `lock_version`), without a separate lock table. Table triggers enforce header/item ownership and frozen protection. Every table has `updated_at` and `frozen`; only database administrators may freeze/unfreeze. Frozen means read-only, not inactive. Other authorized users may view drafts; supervisors must explicitly force-close and reopen. See [data/EDIT_LOCKS.md](data/EDIT_LOCKS.md) for contracts and unapplied acceptance tests. No browser heartbeat, editing route or SQL execution is wired in.

### Daily database backup

The standalone job now backs up the whole hanouti database once, including all four schemas, at **02:00 UTC** when the supplied timer is installed and enabled:

```text
{DATA_DIR}/migrations/hanouti/{year}/{month}/{day}-HH-mm-ss-SSS.dump
```

Use `DATABASE_URL` with backup-specific credentials. Run `pnpm db:backup` manually after installing PostgreSQL client tools and configuring credentials, or `pnpm db:backup:production` after building. No backup has been run against PostgreSQL and the timer is not enabled here. Private output, archive-list verification, locking, timeouts and no-overwrite publication remain in place; no automatic deletion or encryption is configured. See [data/BACKUPS.md](data/BACKUPS.md).

**Upgrade warning:** this is a replacement of the unapplied draft, not an executable data migration from three existing databases. If you applied any earlier SQL elsewhere, prepare a reviewed upgrade/data-transfer plan. No databases were connected, renamed or dropped.

## Production build and deployment

```sh
pnpm install --frozen-lockfile
pnpm build
# Set NODE_ENV=production in the deployment environment, then:
pnpm start
```

- Browser output: `packages/browser/dist`; serve using a static host/reverse proxy with SPA fallback.
- API output: `packages/server/dist`; `pnpm start` starts the API only.
- Shared output: `packages/common/dist`; required at runtime by the API.
- ORM output: `data/dist`; required when server code imports `@app/data`. Keep its runtime dependencies too.
- Preserve workspace runtime dependencies and the `data/` directory, or configure `DATA_DIR`. Copying only `server/dist` is **not** a complete deployment.
- Route production `/api/*` requests from the browser's origin to the Express service. The Vite development proxy does **not** exist in the production static build or Vite preview.
- Do not use Vite's dev server as a production web server. Terminate TLS at a trusted ingress.

This is an enterprise-oriented **foundation**, not a fully hardened production system. Before launch, choose authentication/authorization, database migrations and backups, rate limiting (with an explicit trusted-proxy policy), monitoring, secrets management, dependency/security scanning, and deployment topology. No authentication or persistent user data is implied by the demo.

## CI

The repository-root workflow at `../.github/workflows/ci.yml` checks out `hanoti/` and `.test/` together from the same commit. It runs from `hanoti/`, installs pinned dependencies and runs `pnpm check`. No separate test repository or artifact provisioning is needed. SQL integration scripts are not executed by this workflow.

## Product full names

Products and sales/purchase items now expose `fullName` (`full_name` in SQL). A product-row trigger composes the label from its components; new items copy the stored label as a snapshot. Whole-list draft saves recreate items and capture fresh snapshots. See [data/FULL_NAMES.md](data/FULL_NAMES.md). Declarations remain unapplied; no database or API connection was added.

## ERP API prototypes

`api/` is the server-side **@app/api** workspace. It contains **79 exported async prototypes in 13 task files**, covering all current ERP tables and cross-order editing. `api/common/` holds the seven-field argument contract (including the caller-supplied database instance), an opaque `ResultType` placeholder and explicit not-implemented helpers. Express request/response types match the existing server; session semantics remain undefined.

Every operation rejects with `ApiNotImplementedError`: no routes, response writes, authorization, business operations or database connections are implemented. The running server does not import this package. `pnpm check` includes its typechecks, rejection/coverage tests and build; `pnpm dev` does not start an extra service. See [api/README.md](api/README.md) for the full inventory and future implementation boundaries.

## Sibling test files and logs

All first-party tests, fixtures, test TypeScript configs, the offline SQL validator, historical logs and one-off helpers now live in **`../.test/`**, beside `hanoti/`. The application's pnpm workspace explicitly includes that sibling folder; `packages/*`, `data` and `api` remain inside Hanouti.

Run installation and root commands from `hanoti/`. Refresh links with `pnpm install --frozen-lockfile`. Root test/typecheck/lint/format commands include the external test workspace explicitly, and test commands fail when that workspace is missing. No dependency installation or checks were run for this move.

**Keep both sibling folders when cloning or copying this repository.** Git is rooted above `hanoti/` and `.test/`. The historical local ZIP predates the rename and is excluded from Git; use this repository for the current layout.

## Architecture baseline

The former workspace-level `architecture-baseline/` folder is now [docs/architecture/baseline/](docs/architecture/baseline/README.md). Its backup and DataSource snapshots are historical reference material, excluded from active builds, linting and formatting. The maintained code stays under `packages/`, `api/` and `data/`.
