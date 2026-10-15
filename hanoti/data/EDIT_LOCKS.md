# Header locks, timestamps and frozen rows

**Unapplied baseline only.** No PostgreSQL connection or SQL execution was performed. Offline parsing and TypeORM/static tests do not validate live privileges, trigger semantics or concurrency. No API, automatic heartbeat, connection lifecycle or freeze-management endpoint is installed.

## Storage and scope

There are **30 tables**, not 31. The separate editing-lock table/entity has been removed. Both `erp.sales_orders` and `erp.purchase_orders` contain:

| SQL column     | TypeORM property | Meaning                                                                            |
| -------------- | ---------------- | ---------------------------------------------------------------------------------- |
| `locked_by`    | `lockedBy`       | Nullable FK to `auth.users`; only this actor may edit                              |
| `locked_at`    | `lockedAt`       | Server time of acquisition or latest successful renewal                            |
| `lock_version` | `lockVersion`    | Nonnegative bigint fencing counter; represented as a decimal **string** in JS/JSON |
| `updated_at`   | `updatedAt`      | Optimistic business-content timestamp                                              |
| `frozen`       | `frozen`         | Read-only flag, not an activity/status flag                                        |

All 30 tables have non-null `updated_at` and `frozen`, with `frozen` defaulting to false. Thirty generic row triggers maintain timestamps and enforce frozen protection. Four additional row triggers protect the two order headers and their item tables. Thirty statement triggers reject TRUNCATE, which would otherwise bypass row protection. The helper declarations are in `010_row_guards.sql`; all triggers are attached at the end of `011_order_edit_routines.sql`, after their dependencies exist.

Locks apply to the existing **sales and purchase drafts**, not to a new invoice model. Existing authorization and full settings resolution remain in place. Client permissions are still rights to their own drafts/requests, not issued invoices.

## Five-minute exclusive editing

An acquired lock is live while `locked_at > clock_timestamp() - interval '5 minutes'`. A renewal starts another five-minute interval using server time. Expiry is evaluated after obtaining the header row lock, not from transaction-start time. No cleanup job is needed for expiry.

- Creating a draft reserves it for its creator, starting at version `1`.
- An active lock prevents another open, even by the same actor or a supervisor.
- Opening a free/expired draft increments the version; renewal preserves it.
- Closing or force-closing clears the editor/time and increments the version.
- Freezing **or unfreezing an order header** clears ownership and increments the version. Unfreezing never restores a former editor.
- Other authorized users may read. Reads and status polling never renew the lock.
- A supervisor must explicitly **force-close, then open**. Force-close alone does not grant editing authority or reserve the draft for that supervisor.

The version is **not a secret token**, a password or proof of a physical browser tab. The actor and version must both match. Two tabs authenticated as the same actor and deliberately sharing the current version share that authority; the exact `updated_at` check still fences overlapping full-document saves. Never replace a stale submitted version with the current database version during an automatic retry.

## Function contract

| Function                                                                  | Required authority / result                                                                            |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `erp.open_order_edit(actor, kind, order_id)`                              | Applicable `order.<kind>.update_draft`; returns the new lock and current document timestamp            |
| `erp.renew_order_edit(actor, kind, order_id, lock_version)`               | Same edit permission and live owned version; expired locks cannot be revived by renewal                |
| `erp.close_order_edit(actor, kind, order_id, lock_version, reason?)`      | Active actor and matching owned version; can release an expired, unreplaced lock                       |
| `erp.force_close_order_edit(actor, kind, order_id, lock_version, reason)` | Applicable `order.<kind>.force_close_edit`; explicit observed version and nonblank reason              |
| `erp.order_edit_status(actor, kind, order_id)`                            | Ordinary applicable order-read permission; reports frozen/active state, version and editor when active |

`kind` is `sales` or `purchase`. Protected writers are:

```sql
-- New draft: omit the last three optional arguments.
erp.save_sales_order_draft(actor, document, reason)
erp.save_purchase_order_draft(actor, document, reason)

-- Existing draft: all three are required.
erp.save_sales_order_draft(actor, document, reason,
  order_id, expected_updated_at, lock_version)
erp.save_purchase_order_draft(actor, document, reason,
  order_id, expected_updated_at, lock_version)
```

A successful save returns `id`, `status`, `updated_at`, `line_count` and `edit_lock`. The latter contains `order_id`, `kind`, `locked_by`, `locked_at`, `lock_version`, `expires_at` and `updated_at`. Preserve timestamp strings exactly: JavaScript Date truncates PostgreSQL microseconds. Send bigint versions as decimal strings.

Creation, including initial items, continues to require **create_draft**, not an additional update_draft grant. The protected creation context allows only initial item INSERTs and the corresponding parent timestamp changes under that create permission. Later saves, acquisitions and renewals require update_draft. Closing one's own current version does not require retaining edit permission.

Full-list saves delete and recreate items transactionally. A frozen line therefore prevents replacement even if its submitted content looks unchanged. Writers return the **actual final parent timestamp**, after all child triggers, and recheck lock expiry before reporting success. A failure rolls back all changes and audits.

## What table-level guards enforce

With triggers enabled, privileged direct DML does not bypass the lock/frozen gates:

- Header INSERT needs a trusted active actor, create permission and an actor-owned draft; the database supplies lock metadata.
- Header business UPDATE/DELETE needs current editor ownership, matching version, live expiry, draft state and applicable permission. Identity, ownership, parties, warehouse, currency and lifecycle cannot be rewritten through the draft path.
- Header deletion additionally requires `order.<kind>.delete_draft`; no backend delete entry point or permission assignment was added. Existing RESTRICT foreign keys still apply.
- Item INSERT/UPDATE/DELETE locks the parent, checks the parent is unfrozen, checks the editing context and applicable permission, and advances the parent timestamp. Reassigning an item to another order is rejected.
- Lock transitions are separate operations; business edits cannot be combined with them. An expired renewal cannot silently become a fresh open.
- Existing downstream-bound drafts cannot be replaced through the writers; ordinary direct business changes are also checked against downstream records by the parent guard.
- Item and header mutations and explicit lock transitions generate metadata-only audit events. Heartbeats do not create audit spam. Natural expiry is recorded when a subsequent acquisition detects it.

The generic timestamp trigger assigns server time on INSERT and strictly advances it on ordinary UPDATE. Lock-only header changes preserve `updated_at`, so a heartbeat does not invalidate an otherwise current save. Child changes and administrative frozen transitions do advance it. A line frozen/unfrozen by an administrator also invalidates the parent's saved timestamp.

These guards are **not a replacement for the full business validation in the save functions**. The backend remains function-only; do not grant repository/table writes as a substitute for those functions. Privileged manual DML must still respect settings, numeric/snapshot validation and operator procedures.

### Trusted actor context

The shared PostgreSQL login is not the end user's identity. Public routines bind the authenticated actor and target to transaction-local `hanouti.actor_id`, `hanouti.order_kind`, `hanouti.order_id`, `hanouti.lock_version`, `hanouti.lock_action` and `hanouti.change_reason`, and restore previous values on success. On an exception, PostgreSQL rolls the statement/subtransaction changes back, including local context changes.

Missing/mismatched context fails closed for ordinary order/item writes. Private context helpers are **not** granted to the backend. GUC values are not independent authentication: a database principal with direct table rights can deliberately set them. Only a trusted backend may supply actor UUIDs, derived from authentication rather than request bodies. Never expose arbitrary SQL, actor selection, or context-helper access to end users. The `create` context is reserved for the protected new-draft transaction, not a shortcut for editing existing drafts.

## Frozen means read-only, not inactive

A frozen row rejects UPDATE and DELETE, including no-op updates. It remains readable and usable subject to its existing status, active flags and authorization. Frozen orders additionally block every item mutation, including attempts to freeze/unfreeze a child. Other relationships do not automatically become inactive or recursively frozen.

Consequences worth reviewing operationally:

- A frozen active user can still authenticate/authorize according to existing rules. Freeze is not suspension.
- A frozen permission or setting still contributes to evaluation; it cannot be changed until unfrozen.
- Freezing a session can prevent its revocation UPDATE or cleanup DELETE. Freezing roles, memberships or related rows may block cascades. Unfreeze first under a reviewed administrative process.
- A frozen product/customer can still be referenced if its ordinary active status permits that use.
- Frozen audit rows remain readable; new audit events can still be inserted.
- FK cascades that would modify a frozen row are rejected. Header identity/ownership guards can also reject cascades that would rewrite an order; review administrative identity deletion separately.

### Database-administrator-only management

There is no application freeze permission and no supervisor freeze bypass. `_database_admin` checks **session_user**, not the SECURITY DEFINER execution identity. An authenticated table owner/usable owner-role member or a member of the dedicated `hanouti_data_admin` database role may change frozen. Superusers retain their inherent administrative control.

The optional privilege template creates `hanouti_data_admin` as NOLOGIN/non-superuser and grants only schema usage, SELECT on primary-key/frozen/timestamp columns and UPDATE on `frozen` for each table. It assigns no membership. Grant it only to a separate reviewed administrative login, **never** the backend login. The routine-owner role owns functions, not tables, and must not be granted to runtime logins either.

Use standalone changes, for example as an authorized database administrator:

```sql
UPDATE erp.sales_orders SET frozen = true WHERE id = $1 AND NOT frozen;
UPDATE erp.sales_orders SET frozen = false WHERE id = $1 AND frozen;
```

Unfreeze and business changes cannot be combined in one UPDATE. Business changes require a later statement and, for drafts, a new valid editing lock. To change a frozen child of a frozen order, unfreeze the parent first, then the child. Freeze-transition audits identify the database login, table/key and resulting flag, not copies of sensitive row contents. Stored generated columns are excluded from flag-only comparisons because their values are computed after BEFORE triggers.

## Deployment and concurrency boundaries

This is a **fresh, unapplied baseline**, not an upgrade migration. Review/apply all eleven numbered files before enabling access, then separately review the optional catalog and privilege template. A deployed older design needs a deliberate upgrade that migrates lock state, removes obsolete UUID-token writer overloads/private helpers and drops the old lease table only after dependent code is replaced. Merely adding the new functions is unsafe. Never enable application traffic while only part of the baseline is installed.

Keep the backend login non-superuser, without table/column privileges, data-admin/routine-owner membership, schema CREATE or trigger-disabling capabilities. A hostile database administrator can disable triggers or change functions; this design does not claim otherwise. TRUNCATE is explicitly rejected while triggers are enabled; controlled maintenance/migrations must be reviewed separately.

Use short **READ COMMITTED** transactions and parent-before-child lock ordering. Public routines obtain the parent first. A raw child UPDATE/DELETE may already hold a child tuple lock when its BEFORE trigger requests the parent; trusted manual operations must explicitly lock the parent first to avoid inverse-order deadlocks. PostgreSQL deadlock aborts protect atomicity, but callers must handle retries safely.

The five-minute logical expiry cannot evict a transaction holding a physical PostgreSQL lock. Configure finite `lock_timeout`, `statement_timeout` and `idle_in_transaction_session_timeout` on the actual backend login/pool. Do not leave a transaction open while a person edits. Renew separately (for example every minute), and return to read-only mode after renewal failure. That heartbeat is a future application responsibility, not implemented here.

## Validation and remaining acceptance

Offline checks cover declaration grammar, the 30 entity mappings, trigger coverage, counter/timestamp gates and the 15-entry-point execute allowlist. `../.test/data/sql/erp_routines_edit_locks.integration.sql` is **unexecuted** and includes create-only drafts, read-only viewing, supervisor exclusion, direct INSERT context/parent timestamps, frozen rows/children, stale saves, forced close/reopen and expiry. Its expiry simulation temporarily disables one trigger in a disposable database only; it is not a production bypass.

Before deployment, run the fixtures in a fresh isolated PostgreSQL database with pgvector and separately test:

1. Two concurrent opens, owner save versus force-close, expiry while waiting, and stale requests after re-acquisition.
2. Heartbeat/save overlap without spurious timestamp conflicts; raw child DML versus whole-document replacement.
3. Actual non-admin backend and separate metadata-admin logins, including attempts to set frozen inside SECURITY DEFINER calls. **SET ROLE from a superuser does not emulate a non-admin session_user.**
4. Generated-column line freezing; frozen-parent/child combinations; cascade failures, TRUNCATE rejection and administrative unfreeze recovery.
5. Runtime helper/table/obsolete-overload denial, context restoration after success/error, audit rollback, timeouts and deadlock retries.

No live behavior, ACL, performance or concurrency result is claimed by the offline checks.
