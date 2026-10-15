# TypeORM — one hanouti database, schema namespaces

The server-only `@app/data` package uses TypeORM 1.1.2 and exposes **30 entity classes in four schema namespaces**. One PostgreSQL DataSource registers all of them. No import opens a connection or executes DDL.

## Layout and imports

```text
data/code/
├── entities/
│   ├── auth/       10 classes → auth.*
│   ├── erp/        13 classes → erp.*
│   ├── app/         5 classes → app.*
│   └── settings/    3 classes → settings.*
├── helpers/
│   ├── connections.ts
│   ├── repositories.ts
│   └── values.ts
├── data-sources.ts
├── entity-registry.ts
├── types.ts
└── index.ts
```

```ts
import { Auth, Erp, App, Settings } from '@app/data';
const user: Auth.User = new Auth.User();
const product: Erp.Product = new Erp.Product();
const customer: Erp.Customer = new Erp.Customer();
const file: App.File = new App.File();
const globalRule: Settings.GSettings = new Settings.GSettings();
const scopedRule: Settings.Setting = new Settings.Setting();
```

These are ESM namespace exports, usable as values and TypeScript types. The old `Auth.Public`, `Erp.Public`, `App.Public`, and `App.Settings` nesting is removed. Property names are camelCase; database columns remain explicitly mapped snake_case.

| Namespace  | Classes                                                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `Auth`     | User, Role, Permission, UserRole, RolePermission, Session, PasswordResetToken, EmailVerificationToken, PartyMembership, SubjectPermission     |
| `Erp`      | Category, Brand, Product, Customer, Supplier, Warehouse, SalesOrder, SalesOrderItem, PurchaseOrder, PurchaseOrderItem, Payment, StockMovement |
| `App`      | UserPreference, File, Notification, FeatureFlag, AuditEvent                                                                                   |
| `Settings` | SettingDefinition, GSettings, Setting                                                                                                         |

`allEntities` is the single registry. `entitiesBySchema` and the four schema arrays are also exported for inspection, not for constructing separate databases. Never import these entities into the browser or re-export them through `@app/common`.

## One explicit DataSource

```ts
import {
  createDataSource,
  readDatabaseConfiguration,
  initializeDataSource,
  destroyDataSource,
} from '@app/data';

// Caller decides how to load secrets or dotenv. Factory does not load .env itself.
const source = createDataSource(readDatabaseConfiguration(process.env));
// The source is still uninitialized here.

// Explicit future opt-in; this example is not wired into server startup:
try {
  await initializeDataSource(source);
  // Authorized operations go here.
} finally {
  await destroyDataSource(source);
}
```

Configuration uses **`DATABASE_URL=postgresql://user:encoded-password@host:5432/hanouti`**. URLs for `/auth`, `/erp`, or `/app` are rejected. Old `AUTH_DATABASE_URL`, `ERP_DATABASE_URL`, `APP_DATABASE_URL`, `createDataSources`, and plural lifecycle helpers are removed intentionally.

You may instead call `createDataSource({ url, ssl?, poolSize?, connectTimeoutMs? })`. Defaults are one pool of 10 connections and a 10-second connection timeout. The parser allows PostgreSQL schemes and TLS query options `sslmode`, `sslrootcert`, `sslcert`, `sslkey`; other URL options are rejected to prevent connection-target overrides. Configure timeouts with the factory option.

For remote production servers, use verified TLS and trusted certificates. Choose either URL TLS options (for example `sslmode=verify-full`) or an explicit `ssl` object, not both. Do not log configuration objects or raw driver failures, which may contain private details. Use application credentials separate from provisioning and backup credentials.

The factory keeps these settings disabled:

```ts
synchronize: false
migrationsRun: false
migrations: []
dropSchema: false
installExtensions: false
logging: false
parseInt8: false
invalidWhereValuesBehavior: { null: 'throw', undefined: 'throw' }
```

Individual entities also disable synchronization. Provision `hanouti`, the four schemas, and pgvector separately through the reviewed SQL process. SQL files are not TypeORM MigrationInterface classes and are not automatically registered as migrations. Do not call `synchronize()` or `dropDatabase()` against the deployed application.

## Shared connection policy

`@app/data/connection-policy` is a lightweight, **server-only** entry point shared by the TypeORM factory and the backup module. It exports `databaseName`, `parseDatabaseUrl(value, consumer)`, and the `ConnectionConsumer` type (`typeorm` or `libpq`). It performs no environment reads, file access or connections, and imports neither TypeORM nor the entity registry. Do not re-export it from `@app/common` or import it in the browser.

The module owns the database identity, common URL checks and consumer-specific query-key allowlists. Driver configuration stays in the existing adapters: TypeORM owns pool/timeout/explicit-SSL options; backups own libpq environment conversion, credential decoding and inherited-environment sanitization. Existing helpers and public error messages remain unchanged. The returned URL contains credentials: never log it. Query values retain existing behavior; this is not a new TLS-value validator.

One explicitly approved correction accompanies this refactor: unsupported query keys such as `toString`, `constructor`, `__proto__` and `hasOwnProperty` are rejected. The previous backup lookup accidentally accepted inherited object properties. Documented connection options are unchanged.

Offline tests cover shared URL cases, consumer differences, backup rejection before filesystem/tool activity, and importing the compiled subpath in a fresh Node process with database-runtime imports blocked. Build `@app/data` before running these tests directly, as with other compiled workspace imports.

## Connection helpers

`initializeDataSource(source)` and `destroyDataSource(source)` serialize lifecycle transitions for the same source. Concurrent initialization opens only once; shutdown waits for pending startup and is safe after startup failure. The caller owns connection lifetime. None of this is added to the API startup/shutdown path automatically.

## Cross-schema repositories and transactions

All schemas belong to the same database, so one PostgreSQL transaction can cover them atomically when the **same transaction manager** is used:

```ts
import { Auth, Erp, Settings, getRepository, withTransaction } from '@app/data';

await withTransaction(
  source,
  async (manager) => {
    const users = getRepository(manager, Auth.User);
    const customers = getRepository(manager, Erp.Customer);
    const settings = getRepository(manager, Settings.Setting);
    // Reads/writes through these repositories participate in the same transaction.
    // Apply permissions, scope checks, business validation and audit policy before writes.
  },
  'SERIALIZABLE',
);
```

Do not use global repositories inside a transaction callback. Serialization retries are not automatic. Repository access does not grant authorization; permission checks and settings resolution are now declared as unapplied SQL routines; repository calls do not automatically invoke them. See [ERP_ROUTINES.md](ERP_ROUTINES.md). Unknown entities, uninitialized sources, and released transaction managers are rejected by the helper.

`getPagination(page, pageSize)` produces bounded `skip`/`take` options; page sizes are 1–100. Always supply a stable order and ownership filters. Undefined/null find filters throw instead of being silently ignored; use TypeORM's `IsNull()` for an intentional SQL-null query.

## Foreign keys and schema authority

Entities map all column types, defaults, nullability, primary/unique keys, checks, index names, and direct foreign keys, including new cross-schema references. Scalar-ID `@ForeignKey` mappings avoid eager/lazy relation loading and automatic ORM cascades. Cross-schema joins may be written explicitly using the shared DataSource.

SQL remains authoritative. Expression/sorted indexes are SQL-managed; generated names for unnamed constraints may differ in metadata. Never replace the reviewed DDL with schema-sync or automatic schema-diff output.

Polymorphic membership and scoped-setting target IDs, and generic audit entity IDs, remain application-validated: one normal FK cannot reference several possible tables. Being in one database does not make these pointers self-validating. Direct customer/supplier permission target IDs do have cross-schema FKs. See [README.md](README.md) for deletion policies.

## Types and sensitive fields

- `numeric` money/quantities and `bigint` use **strings** to preserve precision. Use deliberate decimal arithmetic, not floating-point coercion.
- `timestamptz` maps to Date; calendar-only dates map to strings.
- Generated line totals are read-only with ORM insert/update disabled.
- Timestamp/version fields preserve SQL defaults but are not implicit ORM update/version decorators. Future application writes must maintain timestamps and optimistic-concurrency checks.
- Password hashes, token digests, NIN, NIF, NIS, legacy tax identifiers, and embeddings use `select: false`. Explicitly select them only after authorization; this is not encryption or a DTO security boundary.
- Product/customer embeddings remain nullable vectors of exactly 4096 dimensions. `assertVector4096(value)` checks dense, finite float32-compatible values; it does not generate embeddings or grant access to private data.
- AuditEvent now exposes `sourceSchema`, matching `app.audit_events.source_schema`; valid sources include all four business schemas.

For NOT NULL JSONB columns that permit JSON null, pass the static `jsonbNull` function in a query-builder/insert/update payload, for example `value: jsonbNull`. It emits `'null'::jsonb`; JavaScript `null` would otherwise become SQL NULL. Do not build raw SQL expressions from user input.

## Build, tests, regeneration

```sh
pnpm install
pnpm --filter @app/data build
pnpm --filter @app/data test
pnpm check
```

Offline tests compare metadata for every table with `../.test/data/fixtures/schema-manifest.json`, verify SHA-256 hashes of all eleven SQL files, and exercise factory/lifecycle/transaction helpers without database access. These are not live PostgreSQL integration tests.

The optional generator reads `data/migrations/hanouti/*.sql`, writes classes/barrels/registries and the manifest, and never connects:

```sh
python -m venv .venv
. .venv/bin/activate  # Adapt activation for your operating system.
python -m pip install pglast==8.6
python data/scripts/generate_entities.py
pnpm format
pnpm check
```

Python is unnecessary for normal Node installation/build/testing. Review SQL before regenerating and generated changes before deployment. Legacy examples and dated backup files are not generator inputs. This revision resets the **unapplied baseline only**; it does not migrate existing data or drop old databases.

## Header locks and frozen rows

`Erp.SalesOrder` and `Erp.PurchaseOrder` expose `lockedBy`, `lockedAt` and `lockVersion` (a bigint decimal string). Every entity exposes `updatedAt` and `frozen`. SQL triggers, not ORM lifecycle hooks, maintain timestamps and guard frozen rows and order/item writes. There is no separate lock entity or secret token.

Use protected SQL entry points, not direct repository writes, for application draft operations. Raw writes lack the required actor/lock context and the backend receives no table privileges. Heartbeats preserve the business timestamp; item mutations advance the parent timestamp. Preserve exact PostgreSQL timestamp strings for optimistic saves rather than round-tripping through JavaScript Date. Only database administrators manage frozen flags. See [EDIT_LOCKS.md](EDIT_LOCKS.md); no connection or heartbeat is automatically started.

## Product fullName

`Erp.Product`, `Erp.SalesOrderItem` and `Erp.PurchaseOrderItem` expose `fullName: string`, mapped to non-null `full_name TEXT`. SQL triggers compose product names and capture item snapshots; imports and ORM hooks do not perform that work. See [FULL_NAMES.md](FULL_NAMES.md) for catalog-update and full-list-save semantics.
