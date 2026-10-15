# Hanouti data — one database, four schemas

**Current design:** one PostgreSQL database named **`hanouti`**, with business schemas **`auth`**, **`erp`**, **`app`**, and **`settings`**. The earlier three-database draft has been replaced. No SQL has been executed against PostgreSQL.

| Schema     | Tables | Purpose                                                             |
| ---------- | -----: | ------------------------------------------------------------------- |
| `auth`     |     10 | Users, roles, sessions, permissions, party memberships              |
| `erp`      |     13 | Products, customers, suppliers, warehouses, sales, purchases, stock |
| `app`      |      5 | Preferences, files, notifications, feature flags, audit             |
| `settings` |      3 | Definitions, global/role values, scoped values                      |

`public` is used for the pgvector extension type, not application tables.

## Layout

```text
data/
├── code/
│   ├── entities/{auth,erp,app,settings}/
│   ├── helpers/
│   ├── connection-policy.ts            Shared server-only URL policy
│   ├── data-sources.ts                 One DataSource factory
│   └── index.ts
├── migrations/hanouti/
│   ├── 001_schemas.sql                 Four schemas + pgvector declaration
│   ├── 002_auth.sql                    Core identities and role permissions
│   ├── 003_erp.sql                     ERP tables, references to auth
│   ├── 004_app.sql                     Application tables, references to auth
│   ├── 005_settings.sql                Dedicated settings schema tables
│   ├── 006_auth_party_permissions.sql  Memberships/direct rules, ERP references
│   ├── 007_authorization_routines.sql  Permission checks
│   ├── 008_settings_routines.sql       Complete settings resolver
│   ├── 009_erp_routines.sql            Permission-aware operational starter
│   ├── 010_row_guards.sql        Universal metadata/frozen and order guards
│   └── 011_order_edit_routines.sql     Open, renew, close and supervisor force-close
├── seeds/000_create_database.sql       Provision hanouti only
├── seeds/010_erp_routine_catalog.sql   Optional catalog; no business grants
├── seeds/020_erp_routine_privileges.sql Optional restricted PostgreSQL roles
├── examples/legacy/                    Unused old app_settings example and seed
├── assets/welcome.json
└── scripts/generate_entities.py
```

The initial files are an **unapplied baseline**, not a migration of data from old databases. If earlier drafts were applied elsewhere, stop and prepare a separate reviewed data-migration/upgrade plan. Never rerun revised initial files over existing populated tables or delete the old databases based on this project conversion.

## Provisioning and application order

The optional `seeds/000_create_database.sql` is a **psql** provisioning script. It creates `hanouti` only if absent and leaves an existing database untouched. It requires a role with `CREATEDB`, connected to an existing maintenance database such as `postgres`:

```sh
psql "${ADMIN_DATABASE_URL:?Set the maintenance database URL}" -X -v ON_ERROR_STOP=1 \
  -f data/seeds/000_create_database.sql
```

This is a documented future operation, not an executed action. Do not use a transaction or `psql -1` for database creation. The script contains `\gexec`, so it is not directly compatible with `pg.query()`.

All eleven numbered migration files target the **same hanouti database**, in the order shown above, with **one migration history**. Their declaration transactions are separate; use your chosen migration runner to track success and coordinate deployments. pgvector must be installed on the host before applying `001_schemas.sql`; the provisioning role must be allowed to enable it. Do not run these files against databases named auth, erp, or app.

Every business table has an explicit schema qualifier. Folder names do not change a connection's database or search path. Only explicitly tracked `.sql` migrations belong in the runner; dated `.dump` backup files and the legacy examples do not.

## Cross-schema relationships

Real foreign keys now connect direct references: user attribution, user preferences/notifications, role settings, definition permission codes, and direct customer/supplier permission targets. Existing domain-local foreign keys retain their actions. Nullable attribution references use `SET NULL`; user-owned preferences/notifications and party-bound permission rules use `CASCADE`; setting role/permission definitions use `RESTRICT` to avoid breaking their required scope/key semantics.

Polymorphic `auth.party_memberships.party_id` and `settings.settings.scope_id` cannot use one ordinary foreign key against several tables. They remain explicitly application-validated. Likewise, generic audit entity IDs are descriptive references, not universal foreign keys. Unapplied permission, settings-resolution and operational SQL functions now implement these checks for calls made through the routines; no backend route or automatic connection wiring has been added. See [ERP_ROUTINES.md](ERP_ROUTINES.md).

## TypeORM

Import schema namespaces from the server-only workspace package:

```ts
import { Auth, Erp, App, Settings, createDataSource, readDatabaseConfiguration } from '@app/data';
const source = createDataSource(readDatabaseConfiguration(process.env));
// No connection opened. Example classes:
const product = new Erp.Product();
const rule = new Settings.GSettings();
```

Use **`DATABASE_URL`** targeting `/hanouti`. Old per-database URL variables and multi-DataSource helpers are intentionally removed. All 30 entities share one source, allowing cross-schema joins and transactions through one transaction manager. Synchronization, automatic migrations, and automatic extension installation remain disabled. The API still runs without a database; initialization remains explicit. See [TYPEORM.md](TYPEORM.md).

## Backups and private assets

The daily job now creates **one whole-database archive**, including all schemas, at:

```text
{DATA_DIR}/migrations/hanouti/{year}/{month}/{day}-HH-mm-ss-SSS.dump
```

The systemd template defaults to 02:00 UTC and `DATA_DIR=/data`. It is not enabled automatically. No retention deletion or encryption is configured. See [BACKUPS.md](BACKUPS.md) for installation, monitoring and restore checks.

`assets/` stays private. The API reads `welcome.json` directly from the data directory; never mount data or backup paths as public static content. Runtime deployment must include compiled `data/dist`, workspace dependencies, and required assets.

## Other documentation

- [SCHEMA.md](SCHEMA.md): all 30 table declarations and domain assumptions.
- [SETTINGS_SCHEMA.md](SETTINGS_SCHEMA.md): approved settings/permission behavior.
- [SETTINGS_PLAN.md](SETTINGS_PLAN.md): proposed setting and permission keys, not seeded.
- [ALGERIAN_PARTIES.md](ALGERIAN_PARTIES.md): customer/supplier fields and legal-source notes.

## Permission-aware operations

[ERP_ROUTINES.md](ERP_ROUTINES.md) documents the 38 unapplied functions (15 backend entry points), trusted-actor model, optional catalog/privilege scripts, draft editing, stock replay/concurrency rules and remaining live acceptance tests. No SQL or fixture has been executed.

[EDIT_LOCKS.md](EDIT_LOCKS.md) describes five-minute exclusive draft editing, read-only viewing, version fencing and explicit supervisor close/reopen, universal updated_at/frozen fields, and database-admin-only freeze management. The frontend heartbeat and backend routes are not wired in.

[FULL_NAMES.md](FULL_NAMES.md) describes product `fullName` recomposition and stored sales/purchase item snapshots, including read-only metadata from `order_detail`.

Project tests, fixtures, SQL assertions and the offline SQL validator live under [`../.test/data/`](../../.test/data/), outside this production package. See [the centralized testing guide](../../.test/README.md).
