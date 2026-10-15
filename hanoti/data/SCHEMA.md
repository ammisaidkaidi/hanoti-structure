# Proposed database table declarations

**Status: draft declarations only. Nothing has been applied to a database.**

This proposes a **single-business retail** baseline for Hanouti. It is not a multi-tenant model, a complete accounting system, or an approved legal-invoicing design. Review the business fields, document lifecycles, currency/tax rules, and retention requirements before accepting these initial migrations.

## TypeORM mapping

All 30 domain tables also have server-only TypeORM classes under `data/code/entities/`. SQL remains authoritative; no DDL or connection is performed by importing the ORM package. See [TYPEORM.md](TYPEORM.md) for namespaces, helper functions, precision/privacy behavior, and offline parity checks.

## One database, four schema boundaries

The PostgreSQL database is **hanouti**. All numbered declarations under `migrations/hanouti/` form one migration history. They declare **30 tables**:

| Schema     | Files                                            | Tables |
| ---------- | ------------------------------------------------ | -----: |
| `auth`     | `002_auth.sql`, `006_auth_party_permissions.sql` |     10 |
| `erp`      | `003_erp.sql`                                    |     12 |
| `app`      | `004_app.sql`                                    |      5 |
| `settings` | `005_settings.sql`                               |      3 |

`001_schemas.sql` creates all four namespaces and declares pgvector in public. These are not separate databases, and business tables no longer live in public. No SQL or data migration has been executed.

The SQL targets PostgreSQL **14+** and uses built-in `gen_random_uuid()`. pgvector is required for `erp.products.embedding` and `erp.customers.embedding`; its `public.vector` type does not require a fifth business schema. Initial declaration files contain DDL only, no default-setting rows, permission grants, accounts, or business seed rows. The separate `seeds/000_create_database.sql` provisioning script creates only hanouti and cannot run inside a transaction.

## Auth schema — 10 tables

| Table                       | Purpose                                                                         |
| --------------------------- | ------------------------------------------------------------------------------- |
| `users`                     | Identity, case-insensitive unique email, optional password hash, account status |
| `roles`                     | Named role definitions                                                          |
| `permissions`               | Named permission definitions                                                    |
| `user_roles`                | Many-to-many role assignments with granting-user attribution                    |
| `role_permissions`          | Many-to-many permission assignments                                             |
| `sessions`                  | Hashed opaque session tokens, expiry/revocation, client metadata                |
| `password_reset_tokens`     | Hashed, expiring, single-use reset-token records                                |
| `email_verification_tokens` | Hashed verification-token records bound to an email address                     |

Additional tables in `006_auth_party_permissions.sql`:

| Table                      | Purpose                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| `auth.subject_permissions` | Direct allow/deny rules for user/customer/supplier subjects with record scope and validity |
| `auth.party_memberships`   | Verified, revocable links from auth users to ERP parties in the same database              |

`permissions` now declares resource type, supported scopes, risk and delegation metadata. `role_permissions` declares explicit effect, record scope, expiry/revocation, attribution and change reason. These declarations do not evaluate permissions. See [SETTINGS_SCHEMA.md](SETTINGS_SCHEMA.md).

Local foreign keys link assignments and token records to their parent records. Role and permission codes are unique. Session and verification token digests have uniqueness and format checks; expiry must follow creation. Token consumption, session authentication/revocation and cleanup remain unimplemented. Files 007–009 separately declare active-user and record-aware permission checks for the operational routines; they are not automatically applied to arbitrary table access.

Store a password KDF result such as Argon2id in `password_hash`, never plaintext. A nullable hash allows external authentication but does not implement it. SHA-256 token digests are suitable for high-entropy random tokens, not user-chosen passwords. No admin account or roles are created. Existing HTTP-negotiation authentication helpers are **not automatically mapped** to these tables; review their credential requirements before integrating them, without weakening password storage.

## ERP schema — 12 tables

| Table                  | Purpose                                                                       |
| ---------------------- | ----------------------------------------------------------------------------- |
| `categories`           | Hierarchical catalog categories                                               |
| `brands`               | Case-insensitive unique brand names                                           |
| `products`             | SKU/barcode, descriptions, units, sale price, reorder level, metadata         |
| `customers`            | Customer/contact details; account links live in auth party memberships        |
| `suppliers`            | Supplier/contact details                                                      |
| `warehouses`           | Stock locations                                                               |
| `sales_orders`         | Sales documents, customer snapshot, lifecycle, currency                       |
| `sales_order_items`    | Product/unit/price snapshots, quantities, discounts, tax, computed line total |
| `purchase_orders`      | Purchasing documents, supplier snapshot, destination, lifecycle               |
| `purchase_order_items` | Ordered products, quantities, cost/tax snapshots, computed line total         |
| `payments`             | Sales receipts/refunds, payment state, provider reference, idempotency key    |
| `stock_movements`      | Signed stock ledger per product and warehouse, source lines, idempotency key  |

### Algerian customer and supplier profiles

Both `customers` and `suppliers` include optional job/professional details (`job_title`, `job_info`, `business_activity`, `activity_code`), natural/legal-person identity fields, contact-person/fax details, and separate `nif`, `nis`, `rc`, `nin`, and `article_imposition` fields. Optional professional registration and share-capital/currency pairs are also declared.

These additions use text-based identifiers and format checks, not authoritative registry authentication. They are nullable to support incomplete records and differing party/transaction requirements. Existing customer embeddings and professional/fiscal fields are preserved. Customer-account authorization now uses `auth.party_memberships` rather than the former `customers.auth_user_id` draft column. `tax_identifier` remains a legacy/foreign-reference field; use `nif` for the Algerian fiscal identifier.

See [ALGERIAN_PARTIES.md](ALGERIAN_PARTIES.md) for field mappings, official references, verification limits, and privacy safeguards. These declarations are not a legal-compliance guarantee, and NIN/fiscal identifiers should not be included in customer embeddings.

### Product fields

The `products` declaration stores your product components independently:

| Component | Column         | Declaration                                                            |
| --------- | -------------- | ---------------------------------------------------------------------- |
| ABR       | `abbreviation` | Optional text                                                          |
| Name      | `name`         | Required text, up to 240 characters (existing field)                   |
| Attr      | `attributes`   | Optional text, not JSON                                                |
| Material  | `material`     | Optional text                                                          |
| Dims      | `dimensions`   | Optional text, e.g. `20 × 40 mm`, not JSON                             |
| Color     | `color`        | Optional text                                                          |
| Brand     | `brand_id`     | Existing optional foreign key to `brands.id`; label from `brands.name` |
| Serie     | `series`       | Optional text                                                          |
| MadeIn    | `made_in`      | Optional country-of-origin text; no ISO-code restriction               |
| Quality   | `quality`      | Optional text                                                          |
| Ref       | `reference`    | Optional text, distinct from the existing unique SKU                   |

New text fields permit `NULL` when unknown but reject blank/whitespace-only values. `reference` is not assumed to be unique. The original SKU, barcode, pricing, stock, category, and metadata declarations are preserved. `products.full_name` is a database-maintained TEXT label composed from these components; `/` is added before a present series and is not part of the stored series component. Sales and purchase items capture it in their own `full_name` TEXT column. All three map to TypeORM `fullName`. See [FULL_NAMES.md](FULL_NAMES.md) for snapshot, brand-refresh and whole-list replacement semantics.

### Product and customer embeddings

Both `erp.products` and `erp.customers` declare `embedding public.vector(4096)`. These columns are nullable with no generated/default value. Non-NULL vectors must have exactly **4,096 dimensions**. No embedding model, generation worker, backfill, or search integration is configured; choose a compatible model and use consistent model/version semantics when writing and querying embeddings.

Install pgvector on the PostgreSQL host (or enable support on your managed service) before applying the ERP declaration. The executing provisioning role needs permission to create the extension. The declaration expects the vector type in `public`; if pgvector was previously installed into another schema, `IF NOT EXISTS` does not relocate it—review the extension namespace and type references first. Restore targets also need compatible pgvector support.

No vector index is declared: the standard pgvector HNSW/IVFFlat `vector` index dimension limit is **2,000**, below the requested 4,096. Storage and exact distance queries can use these columns, but indexed approximate search will require a separately designed, supported representation or indexing strategy.

Design choices:

- UUID primary keys, exact numeric money (`NUMERIC(18,4)`) and quantities (`NUMERIC(18,3)`); no floating-point money. Special numeric NaN values are rejected.
- Currency is required, not inferred from location. Three-letter uppercase codes are syntactically checked; supported ISO currencies and allowed currency precision still need application validation.
- Line-level `discount_amount` and `tax_amount` are explicit monetary snapshots, not percentages. The generated `line_total` rounds `quantity × unit price/cost − discount + tax` to four decimals. Currency-specific rounding and legal tax calculation remain business decisions.
- Header totals are not duplicated: derive order totals from their line totals. Payment currency must match its sales order through a composite foreign key. Payment amounts, refunds, and order settlement require transactional application validation.
- Product IDs on linked stock movements must match the referenced order-line product. Positive/negative movement direction is checked; adjustment reasons are required.
- On-hand stock is derived from the sum of `quantity_delta` per product/warehouse. No duplicated balance table or automatic stock-posting trigger is included.
- Transactional rows use restrictive foreign-key deletion behavior. Archive catalog/contact records instead of deleting referenced history. Preserving or deleting financial records is still a policy decision, not guaranteed by these table definitions.

Rules that need future implementation include permitted status transitions, nonempty confirmed orders, immutable posted documents, stock reservation/nonnegative stock under concurrency, service-product exclusion from stock, category-cycle prevention, warehouse/source matching, purchase receipt limits, paired and balanced transfers, payment reconciliation, supplier settlement, and audit publication. General-ledger accounting, legal invoice numbering, tax jurisdiction rules, lot/serial tracking, and unit conversions are outside this baseline.

## App and settings schemas — 5 + 3 tables

| Table                          | Purpose                                                                             |
| ------------------------------ | ----------------------------------------------------------------------------------- |
| `settings.setting_definitions` | Typed business-setting registry, validation metadata, precedence and overridability |
| `settings.gsettings`           | Global and role-level business-setting values                                       |
| `settings.settings`            | User/customer/supplier/product/warehouse-scoped values                              |
| `user_preferences`             | Per-auth-user locale, timezone, theme, extensible JSON preferences                  |
| `files`                        | Private file/object metadata, storage locator, checksum, lifecycle                  |
| `notifications`                | Per-user in-app notifications with read/archive timestamps                          |
| `feature_flags`                | Named feature configuration and enabled state                                       |
| `audit_events`                 | Cross-domain event metadata and actor/entity/request attribution                    |

JSON object checks apply to structured object fields. Notification indexes support user history and unread queries. Files store **metadata only**, not uploaded bytes. Storage keys must be validated before use; table declarations do not implement upload safety, malware scanning, access checks, or path traversal prevention. Settings and event payloads are not a secret vault; keep credentials, bearer tokens, and unnecessary personal information out of them.

Audit events are intended to be append-only, but this is **not enforced** without a separate privilege/immutability design. Audit writes can share a transaction with operations in `auth`, `erp`, and `settings` when future service code explicitly uses the same transaction manager. External delivery still requires an event/outbox strategy.

## Cross-schema references and runtime behavior

All tables share hanouti. Direct links to auth users, roles, permission definitions and explicit ERP party targets now have real cross-schema foreign keys. Existing domain-local deletion actions remain intact. Nullable attribution links use SET NULL; user-owned preferences/notifications and party-specific direct permissions use CASCADE; setting references to roles and permission codes use RESTRICT.

`auth.party_memberships.party_id`, `settings.settings.scope_id`, and generic audit entity IDs remain application-validated polymorphic references. They do not gain a universal foreign key simply because the database is unified. `app.audit_events.source_schema` identifies auth/erp/app/settings, replacing the obsolete source-database field.

`created_at`/`updated_at` defaults set insertion timestamps only. Future writes must maintain update timestamps and optimistic version checks. There are no new triggers or API connection initialization. Files 007–011 now declare permission checks, settings resolution and a restricted operational starter; optional catalog and PostgreSQL privilege templates are separate and unapplied. See [ERP_ROUTINES.md](ERP_ROUTINES.md). One transaction can now span schemas when the same database connection/TypeORM transaction manager is used.

See [SETTINGS_SCHEMA.md](SETTINGS_SCHEMA.md) for the settings and authorization contract. The old standalone `app_settings` example and its seed have been moved to `examples/legacy/` and are not part of the 30-table baseline.

The daily backup now creates one whole-database hanouti archive including all four schemas. Dated `.dump` files under the migration directory are never SQL migrations. Earlier deployed database versions need a reviewed data-migration plan; this conversion changed only the unapplied project.

Draft locks live on both order headers in `003`; guards and editing operations are declared in `010`–`011`. All 30 tables have `updated_at` and `frozen`; frozen means read-only, not inactive, with database-admin-only flag changes. Frozen orders protect their items too. See [EDIT_LOCKS.md](EDIT_LOCKS.md). Supervisors must explicitly force-close and reopen, never bypass ownership.
