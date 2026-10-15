# Settings and permissions — one database, dedicated schemas

**Unapplied SQL declarations and TypeORM mappings. Nothing has been executed or seeded. Permission checks and all four settings-resolution strategies are now declared in SQL routines; they are not wired into the API. See [ERP_ROUTINES.md](ERP_ROUTINES.md) for implementation limits and required live tests.**

## Confirmed architecture and decisions

- One PostgreSQL database: **hanouti**.
- Business settings: **settings** schema.
- Users, roles, grants, and party memberships: **auth** schema.
- Business parties and documents: **erp** schema.
- Preferences, files, notifications, feature flags, and audit: **app** schema.
- Negative document quantities and negative stock balances remain independent controls.
- Client grants initially mean own invoice drafts/requests, not final issuance.
- Only explicitly overridable `most_specific` definitions may use scoped values to relax a global value. Authorization denials and immutable database constraints still win.

This replaces the earlier separate-database/public-schema layout. The approved setting and action catalogs remain in [SETTINGS_PLAN.md](SETTINGS_PLAN.md); no key/default/grant rows are inserted.

## Declared tables

| Table                          | Purpose                                                                            |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| `settings.setting_definitions` | Key registry, types, default JSON, validation metadata, precedence, overridability |
| `settings.gsettings`           | Global and role-level values; role targets reference `auth.roles`                  |
| `settings.settings`            | User/customer/supplier/product/warehouse values                                    |
| `auth.permissions`             | Action catalog and supported record scopes                                         |
| `auth.role_permissions`        | Explicit allow/deny by role with record scope, validity, revocation, reason        |
| `auth.subject_permissions`     | Direct user/customer/supplier rules with explicit target references                |
| `auth.party_memberships`       | Verified and revocable user-to-customer/supplier authorization links               |

`settings.gsettings` is the SQL name of **GSettings**. `settings.settings` is table `settings` inside schema `settings`. `app.user_preferences` remains display-oriented, and `app.feature_flags` is not an authorization source.

Local and direct cross-schema references are real foreign keys: role targets, permission codes, user attribution, customer/supplier direct rules. Polymorphic `scope_id` and `party_id` still require server-side target validation; one FK cannot select a target table based on a discriminator. No competing `erp.customers.auth_user_id` account mapping is declared.

## Value resolution contract (declared in SQL, unapplied)

Every definition chooses its allowed `scope_precedence`, least to most specific. It starts with global; role, if present, is second. Subsequent supported scopes are user, customer, supplier, product, and warehouse. SQL rejects unknown or duplicate scopes. No universal user-versus-product priority is silently chosen.

An example order to review before seeding a customer/user key is `[global, role, customer, user]`. No example rows have been inserted.

| Strategy         | Intended behavior                                                            |
| ---------------- | ---------------------------------------------------------------------------- |
| `global_only`    | Business-wide value or registered default; no scoped override                |
| `most_specific`  | Most specific applicable value wins and may relax a global restriction       |
| `all_must_allow` | Global/default baseline and applicable explicit restrictions must all permit |
| `minimum_cap`    | Minimum applicable numeric/currency cap                                      |

Definitions default to nonoverridable, global-only, with `[global]`. A scoped strategy must be explicitly enabled. Conflicting role values at the same specificity fail closed. Missing scoped values mean inheritance; false, zero, and JSON null are not interchangeable with absence. Explicit unset values are allowed only by the definition and never imply unlimited credit or unrestricted access.

Evaluate validity intervals, units/currencies, document types, scope existence, and per-key ranges/types. Unsupported context, invalid/disabled definitions, or lookup failures block dependent sensitive actions. Product policies resolve per line using the actual product/warehouse, not an arbitrary line for the entire document.

DDL enforces basic default shapes, enum membership, finite range metadata, uniqueness, date intervals and target shapes. The SQL resolver now validates supported JSON/integer/UUID/currency values, applicable stored values and all four strategies at resolution time. Controlled administrative writes and definition-change reconciliation still need implementation; unsupported validation-rule vocabulary fails closed. Value changes require a nonblank reason; timestamps/version counters are not automatically maintained.

## Authorization contract (declared in SQL, unapplied)

- Deny by default; at least one applicable allow is required. Explicit applicable denies win.
- Record scopes: `self`, `own_party`, `assigned`, `all`. The permission definition must support the requested scope.
- `assigned` stays unavailable until a resource-assignment model is implemented.
- Party-specific direct rules are SQL-constrained to `own_party` and require an active verified membership that can act for that party, a valid time interval, active identity, and matching ownership.
- A caller-provided client_id never proves identity. A party-subject deny does not automatically bar authorized employees from working on that customer's behalf; target-customer business restrictions belong in settings.
- Role assignment, membership approval and delegation need separate authority. A user cannot grant privileges by changing business settings or preferences.
- One nonrevoked direct rule exists per subject/permission. Expiry does not automatically free a unique slot; replacement/revocation and audit must be explicit.
- One setting-value slot exists per key/target; these are not arbitrary overlapping scheduled-version tables.

Direct role/permission-definition references use RESTRICT when removal would invalidate a setting. Nullable user attribution uses SET NULL, preserving records; user-owned app records and explicit party permission bindings use CASCADE. Prefer archive/revocation workflows and review deletion policy before implementation.

## One transaction can span schemas

Because all tables now share hanouti, permission/membership/settings changes and an audit write **can** participate in one PostgreSQL transaction through the same TypeORM manager. This is not automatic: future service code must explicitly use that manager, lock/check required records, enforce policy, and publish/cache invalidations safely.

There are still no invoice/credit-note tables or business-grant seeds. An optional unapplied catalog script declares required permissions and conservative setting defaults. The SQL resolver is declared but not deployed; no application policy engine is wired in. Positive order-line quantity constraints, generated totals, stock direction checks, and other immutable invariants remain unchanged. A setting cannot override a SQL CHECK.

## File order and upgrade warning

The new unapplied baseline uses a single history:

```text
001_schemas.sql
002_auth.sql
003_erp.sql
004_app.sql
005_settings.sql
006_auth_party_permissions.sql
007_authorization_routines.sql
008_settings_routines.sql
009_erp_routines.sql
010_row_guards.sql
011_order_edit_routines.sql
```

All files are under `data/migrations/hanouti/` and target hanouti. Apply only through a reviewed deployment process. If earlier drafts were applied elsewhere, an explicit data transfer/upgrade plan is required; this project conversion does not migrate or drop those databases.
