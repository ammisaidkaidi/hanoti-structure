# Permission-aware ERP routines

**Status: declared, not deployed.** No PostgreSQL connection, SQL execution, real backup, privilege deployment, or database integration test was performed. These routines need isolated PostgreSQL acceptance testing before production use. All 30 tables now have updated_at/frozen. Sales and purchase headers hold their locks directly; no separate lease table remains.

## Approved scope

- One database `hanouti`, schemas `auth`, `erp`, `app`, `settings`.
- Only the **trusted backend** calls these routines and supplies the authenticated actor UUID. End users do not have database logins or direct SQL access.
- Permission-aware stock/order/payment reads, sales and purchase draft creation/editing, adjustments and transfers, with transactional audit records.
- Complete resolution of the four approved settings strategies; no settings-administration writes or automatic policy/grant assignments.
- **Approval required means blocked.** There is no approval-request table, no second approver parameter, and no bypass merely because a caller has an approval permission.
- No invoice issuance, order confirmation/fulfilment, purchase receipt posting, payment recording/refunds, automatic numbering, tax calculation, costing or returns workflow.

These are PostgreSQL **functions**, deliberately not procedures with transaction control. Writes and audit records participate in the caller's transaction; none commits independently.

## Files and future deployment order

| File                                                | Purpose                                                                                         |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `migrations/hanouti/007_authorization_routines.sql` | Active actor, verified party membership, allow/deny evaluation                                  |
| `migrations/hanouti/008_settings_routines.sql`      | Context/value validation and all four resolution strategies                                     |
| `migrations/hanouti/009_erp_routines.sql`           | Stock, draft, totals, payment-balance and internal audit functions                              |
| `migrations/hanouti/010_row_guards.sql`             | Universal row metadata/frozen guards and header/item write checks                               |
| `migrations/hanouti/011_order_edit_routines.sql`    | Five-minute renewal, version fencing and trigger attachment and supervisor close/reopen         |
| `seeds/010_erp_routine_catalog.sql`                 | Optional permission catalog and ten conservative setting definitions; **no access assignments** |
| `seeds/020_erp_routine_privileges.sql`              | Optional restricted PostgreSQL owner/backend-role template; review before use                   |
| `../.test/data/sql/erp_routines.integration.sql`    | Unexecuted behavior assertions for a new disposable database; rolls back fixtures               |
| `../.test/data/sql/erp_routines_privileges.sql`     | Unexecuted privilege assertions after the role template is applied in a disposable database     |

Apply the original declarations `001`–`006` first, then `007`–`011`. The two seed/template scripts are separate, explicit operator actions, not part of an automatic migration runner. Existing catalog rows are never overwritten by the optional catalog script. Review pre-existing definitions and permission resource types/scopes for compatibility rather than assuming `ON CONFLICT DO NOTHING` reconciles them.

Do not enable backend access until ownership, privileges and all behavior tests are reviewed. Do not deploy SECURITY DEFINER functions owned by a superuser as the application design.

## Public entry points

| Function                                                                                                         | Business permission / behavior                                                                                             |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `auth.has_permission(actor, code, resource_type, owner?, party_type?, party_id?) → boolean`                      | Advisory authorization evaluation for the trusted backend; never substitutes for resource checks inside mutating functions |
| `settings.resolve(actor, key, context?) → jsonb`                                                                 | Requires all-scope `settings.read`; returns effective value, definition version and contributing row versions              |
| `erp.stock_balance(actor, product, warehouse) → numeric`                                                         | `stock.read`; current ledger sum, not reserved/available-to-promise stock                                                  |
| `erp.adjust_stock(actor, product, warehouse, delta, key, reason) → uuid`                                         | `stock.adjust`; signed, nonzero adjustment; refuses policy requiring approval                                              |
| `erp.transfer_stock(actor, product, from_warehouse, to_warehouse, quantity, key, reason) → uuid`                 | `stock.transfer`; positive quantity, two different warehouses, balanced atomic movement pair; returns transfer group ID    |
| `erp.save_sales_order_draft(actor, document, reason, order_id?, expected_updated_at?, lock_version?) → jsonb`    | `order.sales.create_draft` or `order.sales.update_draft`                                                                   |
| `erp.save_purchase_order_draft(actor, document, reason, order_id?, expected_updated_at?, lock_version?) → jsonb` | `order.purchase.create_draft` or `order.purchase.update_draft`                                                             |
| `erp.order_totals(actor, kind, order_id) → jsonb`                                                                | `order.sales.read` / `order.purchase.read`; kind is `sales` or `purchase`                                                  |
| `erp.order_detail(actor, kind, order_id) → jsonb`                                                                | Same record-aware read permission; returns a sanitized editable document plus summary                                      |
| `erp.sales_payment_balance(actor, order_id) → jsonb`                                                             | Requires both sales-order read and `payment.read`; completed receipts minus completed refunds only                         |

There are **38 functions in total: 15 entry points and 23 internal/trigger helpers**. The five editing-session entry points (`open_order_edit`, `renew_order_edit`, `close_order_edit`, `force_close_order_edit`, `order_edit_status`) are detailed in [EDIT_LOCKS.md](EDIT_LOCKS.md). Underscore-prefixed helpers are implementation details; the backend role is not granted execution on them.

### Parameterized calls from a future authenticated backend

These are examples, not executed commands. Bind parameters through the PostgreSQL driver; never interpolate IDs, JSON or reasons into SQL text.

```sql
SELECT erp.stock_balance($1::uuid, $2::uuid, $3::uuid);
SELECT erp.save_sales_order_draft($1::uuid, $2::jsonb, $3::text);
SELECT erp.save_sales_order_draft($1::uuid, $2::jsonb, $3::text, $4::uuid, $5::timestamptz, $6::bigint);
SELECT erp.transfer_stock($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::numeric, $6::text, $7::text);
SELECT erp.sales_payment_balance($1::uuid, $2::uuid);
SELECT settings.resolve($1::uuid, $2::text, $3::jsonb);
```

The first parameter is always the backend-derived authenticated user ID. For each stock movement, persist a stable request key before retrying; do not generate a new key on every network retry. Do not replace these calls with direct repository writes when relying on their permissions or stock protections.

### Draft document shape

Example sales draft payload (data only, not an executed call):

```json
{
  "order_number": "SO-2026-0001",
  "customer_id": "<existing customer UUID>",
  "warehouse_id": "<existing warehouse UUID>",
  "currency_code": "DZD",
  "notes": "Draft only",
  "lines": [
    {
      "product_id": "<existing product UUID>",
      "quantity": "2.000",
      "unit_price": "100.0000",
      "discount_amount": "0.0000",
      "tax_amount": "0.0000"
    }
  ]
}
```

For purchases, replace `customer_id` with required `supplier_id` and `unit_price` with required `unit_cost`; optional `expected_on` is an ISO calendar date. Sales may omit/null the customer for staff-authorized walk-ins; own-party permission cannot authorize a missing customer. Both routines require an active warehouse and active referenced products/parties. Unknown keys and fields belonging to the other order kind are rejected.

- Use **decimal strings** for quantities and money when calling from JavaScript. JSON numbers are accepted too, but the caller must preserve precision before submission. Output order quantities and monetary values are decimal strings; `stock_balance` uses PostgreSQL numeric. Settings inspection preserves native JSON value types, so inspect large numeric setting values with a lossless JSON strategy.
- A new draft omits `order_id`, `expected_updated_at` and `lock_version`, and atomically acquires a header lock. An edit supplies all three, using the exact returned timestamp plus the current owned lock version (bigint decimal string). Other users—including supervisors—must not edit until the lock is released or force-closed and they explicitly reopen it. Use the timestamp string unchanged rather than converting it through JavaScript Date, which loses PostgreSQL microseconds.
- A frozen header or line prevents a replacement save. Heartbeats do not advance the business timestamp; item changes do. Only database administrators may change frozen. See [EDIT_LOCKS.md](EDIT_LOCKS.md).
- An edit replaces **all lines** and may change notes and a purchase expected date. Order number, party, warehouse and currency remain fixed. Creation attribution stays with the original creator. Returned line IDs are not promised stable across edits.
- Drafts may be empty, up to 1,000 lines. Reasons are required (max 2,000 characters); notes max 4,000. Downstream payments or stock links block replacement, even if the header still says draft.
- Sales price defaults to the product catalog price. A different price needs both `pricing.allow_manual_price=true` and `pricing.override`. Catalog currency must match; no currency conversion is invented.
- Purchase cost is explicitly supplied, not inferred from the product's sales price. Purchase currency is independent of catalog sale currency.
- Zero price/cost requires its setting; negative price/cost is always rejected. Nonzero discounts require `discount.apply`, the line percentage cap, and no unresolved approval requirement. A mandatory operation reason covers the draft edit; no discount approval workflow is implied.
- Nonzero tax snapshots require `order.tax.edit`. These are manually entered draft amounts, **not calculated or certified tax**. Legal rounding and issuance remain out of scope.
- Quantity is strictly positive for order lines. Zero/negative invoice-quantity settings cannot override existing order SQL constraints. Stock-out ledger deltas remain negative by design.
- Item `full_name` snapshots come from the product, never the request. `order_detail` exposes them separately in read-only `item_snapshots`; editable `document.lines` stays unchanged. Whole-list replacement captures fresh snapshots. See [FULL_NAMES.md](FULL_NAMES.md).
- Party snapshots include only the party name. No automatic copying of NIN, NIF, NIS, job information or embeddings occurs.

Draft creation uses unique order numbers, not an idempotency replay protocol. A duplicate number raises a conflict; reconcile an uncertain network outcome before retrying creation blindly.

## Authorization and actor trust

The functions do **not** authenticate arbitrary UUIDs. The backend must authenticate the session, verify its validity/revocation, derive the actor server-side and never copy an actor ID from an untrusted request body. A compromised backend database credential can impersonate actors under this trust model; SQL permission evaluation does not eliminate that fact.

Authorization requires an active `auth.users` record, a matching permission resource type, at least one applicable allow, and no applicable deny. Revoked, future and expired grants do not apply. There is no implicit administrator bypass.

- `self`: the actual stored creator/owner, derived by the operation, not a caller-provided ownership claim.
- `own_party`: an active verified membership, `can_act_on_behalf=true`, valid interval, no revocation, active party, matching party ID.
- `all`: cross-record access as explicitly granted.
- `assigned`: unsupported until an assignment model exists. An otherwise relevant unresolved assigned rule makes evaluation fail closed, including when another rule would allow.
- A grant using a scope not supported by its permission definition fails closed.
- Party-subject rules apply only through the matching verified membership. A customer-party deny is not automatically a restriction on employees who are not acting as that party; customer business restrictions belong in settings.
- Client permissions must be granted with `own_party`, not `all` or broad creator-based permissions. No role/user assignments are included in the catalog script, and none of these functions issues an invoice.

`auth.has_permission` accepts resource context for trusted-backend inspection. Its boolean result is **not a capability token**: mutation/read routines derive ownership from their own records and perform their own checks.

Authorization and validity are evaluated during the database statement, using `statement_timestamp()` for validity intervals. Concurrent administrative revocation does not promise cancellation of already-running operations. Coordinate urgent revocations and use short transactions; this is not a linearizable global authorization system.

## Full settings resolution contract

All four approved strategies are declared:

1. **global_only:** active global row, otherwise the registered default.
2. **most_specific:** follow the definition's least-to-most-specific order; the latest applicable scope wins. Only explicitly overridable definitions may use it.
3. **all_must_allow:** global/default baseline AND every applicable explicit restriction.
4. **minimum_cap:** the minimum baseline/scoped numeric value, or monetary amount in the **same requested currency**.

The global row **replaces** the default baseline; default is not a second independent restriction. No cross-currency conversion or hard-coded user-versus-product ordering is used. Different active role values at the same specificity fail closed for every strategy, even if a more-specific user value exists. Identical role values are allowed. Only scopes listed in the definition participate; relevant stored values with disallowed scopes cause an error rather than being silently accepted.

Missing scoped rows mean inheritance. `false`, zero, JSON null and a missing row are distinct. JSON null is accepted only by `allow_null`; a restrictive boolean/cap cannot use unset as permission or infinity. Required boolean/numeric operation settings reject null or the wrong type.

Context is a JSON object with optional `customer`, `supplier`, `product`, `warehouse` UUID strings, `document_kind`, `currency` and `unit`. User scope always means the authenticated actor. Unknown keys, invalid target IDs, nonexistent targets, incompatible document kinds/units/currencies, disabled definitions and missing required definitions fail closed. Context validates existence, not authorization; operational callers derive relevant context from checked records. The generic inspection function therefore requires all-scope settings read authority.

Supported value types: boolean, integer, decimal, string, enum, UUID, object, and `currency_amount` of exactly `{ "amount": <JSON number>, "currency": "DZD" }`. Integers, finite numeric values, min/max bounds, enum membership and UUID syntax are checked. Currency syntax is three uppercase letters; this is not an ISO currency registry or currency-precision engine.

`validation_rules` has an explicit safe vocabulary:

| Rule                       | Applies to    | Meaning                                     |
| -------------------------- | ------------- | ------------------------------------------- |
| `min_length`, `max_length` | string / enum | Integer character bound from 0 to 1,000,000 |
| `required_keys`            | object        | Array of required top-level string keys     |
| `allowed_keys`             | object        | Array of permitted top-level string keys    |

Unknown rules are rejected. This is not an arbitrary JSON Schema interpreter, regex engine or executable expression facility. Nested object schemas require a separately reviewed extension. Default and applicable stored values are validated before resolution, so an invalid lower-priority value cannot be hidden by a later override. Generic administrative writes are still outside the routines; the runtime role cannot write the settings tables.

### Conservative optional defaults

The optional catalog script declares all ten operational settings as **global-only, nonoverridable** initially. No settings-value rows are inserted. Administrators must explicitly review and enable per-key overridability/precedence later if desired.

| Setting                                   | Default                      |
| ----------------------------------------- | ---------------------------- |
| `quantity.allow_fractional`               | true                         |
| `quantity.decimal_places`                 | 3                            |
| `stock.allow_negative_balance`            | false                        |
| `stock.require_available_quantity`        | true                         |
| `stock.require_adjustment_approval`       | true — blocks direct posting |
| `stock.require_transfer_approval`         | true — blocks direct posting |
| `pricing.allow_zero_unit_price`           | false                        |
| `pricing.allow_manual_price`              | false                        |
| `discount.max_line_percent`               | 0 percent                    |
| `discount.require_approval_above_percent` | 0 percent                    |

Stock may go below zero only when negative balance is explicitly allowed **and** available-quantity enforcement is false. The stricter restriction wins. Transfer policies and quantity precision are checked at both warehouses. The mandatory reason is not configurable. Backorder, credit, invoice and other catalog settings are not silently activated by this starter.

## Stock integrity, concurrency and retries

All write entry points require **READ COMMITTED** and reject other isolation levels. They do not change isolation themselves. The backend owns commit/rollback and should set finite statement/lock timeouts.

- Adjustment/transfer keys are nonblank, at most 120 characters. Stored keys are `adj:…`, `out:…`, `in:…`, fitting the existing 128-character limit. The namespaces are operation-specific.
- An advisory transaction lock serializes attempts with the same request key. Identical successful replay returns the existing ID/group without new movements or a second audit event; different actor/quantity/product/warehouse/reason raises conflict.
- Permission and active-actor checks still occur on replay. New business policies are not reapplied to an already-posted identical operation; replay creates nothing new.
- A product row lock serializes this starter's ledger writers across warehouses. Balance queries after the lock use fresh READ COMMITTED snapshots. The design depends on **all stock writers following this convention**, not just these two routines.
- Transfer warehouse locks are ordered, and both signed movements are inserted together with a shared transfer group. No zero movement, service-product stock, unbalanced pair or same-warehouse transfer is accepted.
- No stock balance table is introduced. On-hand is the sum of the existing ledger, not reserved stock or valuation.
- Functions do not automatically retry deadlocks/timeouts. Callers must roll back and retry the complete transaction appropriately. Multiple operations in one transaction can still deadlock if callers acquire product/order locks in conflicting orders.

Audit records are inserted within the same transaction and contain operation IDs, reason, quantities and relevant stock policy information. They do not contain credentials or fiscal identifiers. Callers must not put secrets/unnecessary personal details in free-text reasons. Failed calls roll back their changes and success audit; this is not a durable failed-attempt audit log. Return errors to the backend's security logging path without leaking secrets.

## Restricted database privileges

Each routine fixes `search_path = pg_catalog, pg_temp`, schema-qualifies application objects and revokes PUBLIC execution in the same declaration transaction. There is no dynamic SQL or user-selected table name.

The optional deployment template creates **fresh NOLOGIN PostgreSQL roles**:

- `hanouti_routine_owner`: owns functions, has only needed catalog reads and ERP/audit writes. It is not a superuser and cannot authenticate directly.
- `hanouti_data_admin`: metadata-only SELECT/UPDATE(frozen) rights; no membership is assigned. Only separate reviewed database-admin logins may receive it, never the application login.
- `hanouti_backend`: schema usage and EXECUTE on exactly fifteen entry points. No direct table privileges or internal-helper execution is granted.

The template intentionally fails if these roles already exist; existing roles must be audited, not silently reused. Grant the backend group to the actual non-superuser application login **only after reviewing all its direct/inherited/PUBLIC privileges**. Do not grant the owner or data-admin role to that login. Ensure neither PUBLIC nor the login can create objects in business schemas or directly read/write protected tables through other grants.

The template does not revoke unrelated deployment privileges globally, provision a login/password, alter RLS, or prevent a database superuser from bypassing rules. It is not an automatically installed security perimeter. Do not grant runtime direct table writes: triggers enforce frozen/header/item gates, but they do not replace all business validation in the protected routines. Transaction-local actor context is not independent authentication. Backup credentials remain separate and read-oriented.

## Validation performed and remaining acceptance tests

Offline work:

- Parsed the routine declaration files and the row/statement-trigger declarations and both optional scripts with `pglast`.
- Parsed PL/pgSQL body grammar. The standalone parser cannot resolve the custom composite parameter of `_validate_value`; its **grammar-only** pass substitutes `record` for that parameter. It does not check real PostgreSQL catalog types, SQL query semantics or privileges.
- Added static Node checks for the fifteen entry points, fixed search paths, PUBLIC revokes, catalog separation and execute-grant allowlist.
- Refreshed the SQL-hash manifest while mapping all 30 tables, including universal metadata and both header lock fields. No application connection wiring is introduced.
- Added unexecuted integration assertions for authorization, membership, deny precedence, policies, replay conflicts, balanced transfers, draft timestamp/version fencing, frozen protection, totals and payment balance.

Run syntax checks offline with Python 3.10+ and `pglast==8.6`:

```sh
python ../.test/data/scripts/validate_routines.py
```

**Required before production:** in a fresh disposable PostgreSQL database with pgvector, review/apply the baseline and optional catalog, run the integration fixture, apply the privilege template and run privilege assertions. Independently test two-session competing withdrawals, simultaneous duplicate keys, opposite-direction transfers, lock timeouts and rollback; verify direct table access/internal helpers are denied for the actual runtime login. Test precision, each validation-rule/type branch, expired grants/settings, revoked memberships and administrative policy changes. None of these live tests was run here.

**Editing upgrade warning:** this remains an unapplied baseline. Do not apply only the new lock files to an older deployed routine set: obsolete writer overloads must be deliberately removed/replaced. See [EDIT_LOCKS.md](EDIT_LOCKS.md) for deployment and two-session acceptance requirements.
