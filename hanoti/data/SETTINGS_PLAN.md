# Settings and permissions — approved plan

**Plan approved with the decisions below. DDL declarations have been added; no SQL, seeds, grants, or runtime policy enforcement has been executed.**

## Approved decisions

- Settings tables use the `settings` schema and permission tables use `auth`, both inside the single `hanouti` database. This supersedes the prior three-database layout.
- Negative document quantities and negative stock balances remain separately configurable.
- Client permissions initially cover own drafts/requests, not final invoice issuance.
- Specific values may override global values only for explicitly overridable `most_specific` keys. Other strategies remain restrictive; authorization denies and immutable invariants always win.
- See [SETTINGS_SCHEMA.md](SETTINGS_SCHEMA.md) for declared objects, per-key scope ordering, and outstanding runtime work.

## 1. Separate business settings from access permissions

- **Settings** answer: “Which business rules apply?” Example: a draft invoice may contain a zero-quantity item.
- **Permissions** answer: “Who can perform which action, on which records?” Example: an authenticated customer may create an invoice draft for their own customer account.
- A setting must never grant access by itself. An action succeeds only when authorization, record ownership/scope, business settings, and non-overridable invariants all pass.
- `client` means the ERP `customers` entity; `user` means an authenticated identity in the `auth` schema of hanouti. A caller-supplied `client_id` is not proof of identity.

## 2. Proposed tables and database placement

### Settings schema: business settings

| Table                          | Purpose                                                                                                     |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `settings.setting_definitions` | Registry of known keys, types, defaults, validation rules, allowed scopes, and resolution strategy          |
| `settings.gsettings`           | Your **GSettings**: business-wide settings and role-level settings; a null role target means business-wide  |
| `settings.settings`            | Your **Settings**: overrides/restrictions for specific users, customers, suppliers, products, or warehouses |

Use lowercase `gsettings` in PostgreSQL to avoid requiring quoted mixed-case identifiers. The UI can display “GSettings”.

The old public settings draft was replaced by dedicated `settings.*` tables. All schemas now share hanouti. If earlier drafts were applied elsewhere, migrate their data explicitly rather than rerunning this revised unapplied baseline.

Proposed definition fields:

- `key`, `description`, `category`
- `value_type`: boolean, integer, decimal, string, enum, UUID, or constrained JSON object
- `default_value`, optional allowed enum values, numeric bounds, units
- `allowed_scopes`: global, role, user, customer, supplier, product, warehouse
- `resolution_strategy`: default inheritance, all-must-allow, minimum-cap, or explicit-selection
- `document_kinds`: the applicable document types; no assumption that a sales rule applies to purchases
- `change_permission_code`, `is_enabled`; all stored value changes require a reason

Proposed value fields:

- `id`, `setting_key`, `value JSONB`
- Explicit target (`role_id` for role-level GSettings; `scope_type` plus `scope_id` for Settings)
- `version` for optimistic concurrency
- `valid_from`, `valid_until` for bounded exceptions
- `created_by_user_id`, `updated_by_user_id`, timestamps, change reason

Constraints: known setting key, valid target shape, one current value per key/target, and consistent expiry. Global uniqueness must handle a null role target explicitly on PostgreSQL 14 (for example with a partial unique index), not rely on ordinary nullable-column uniqueness. The API validates JSON types/ranges and polymorphic target existence; no claim that a simple foreign key to the definition registry validates a JSON value's type.

Scope is chosen per key. For example, document numbering is global, a discount cap can vary by role/user/customer, and stock thresholds can vary by product/warehouse. We will not allow every setting at every scope indiscriminately.

### Auth schema: action authorization

Reuse `users`, `roles`, `permissions`, and `user_roles`.

- Extend `role_permissions` with explicit **allow/deny** and a supported record scope. This is the authoritative role-to-permission mapping, not a duplicate mapping in GSettings.
- Add `subject_permissions` for direct user/customer/supplier rules, with permission, effect, record scope, optional expiry, attribution, and reason.
- Add `party_memberships` to link an authenticated user to an ERP customer or supplier account, with active/revoked state and an explicit ability to act on behalf of that account. A contact record alone is not authorization.
- `party_memberships` is the authoritative customer/supplier account mapping. The redundant `customers.auth_user_id` was removed from the unapplied declaration; any externally deployed version needs an explicit data migration.

Local auth relationships use real foreign keys. Direct party/user/role references have cross-schema foreign keys. Polymorphic party/setting target IDs still require application validation and lifecycle reconciliation.

Keep display-only choices in existing `user_preferences`, and deployment rollout switches in existing `feature_flags`; neither grants business permissions. No secrets, database credentials, or raw backup commands belong in a settings value.

## 3. Resolution rules

### Ordinary preferences/defaults

Only for keys explicitly classified as inheritable defaults:

`explicit permitted subject value → role default → business-wide value → registered default`

Use each key’s explicitly configured scope order; do not arbitrarily compare supplier and warehouse values. Prefer user preferences for purely visual settings. Conflicting active role values fail closed; never depend on query order.

### Approved specific-value overrides

For definitions explicitly marked `is_overridable=true` with `resolution_strategy=most_specific`, the highest applicable scope in the key’s configured order wins and may relax the global value. A setting never overrides an authorization deny or an immutable integrity constraint. Global-only keys cannot have effective scoped overrides.

### Guardrails and limits

- **All-must-allow flags:** for keys explicitly using this restrictive strategy, business-wide policy sets the maximum envelope. Scoped values may restrict but not relax it. This is distinct from the approved most-specific strategy.
- **Numeric caps:** take the minimum applicable cap, such as a maximum discount. A higher user-specific value cannot silently defeat a lower role cap.
- Missing scoped rows mean **inherit**, not false. Proposed quantity-exception defaults remain false until explicitly configured; whether a scoped allowance can override the global value depends on the definition’s approved strategy.
- Scope relations come from trusted server-side context, not arbitrary request IDs.

### Authorization

- **Deny by default.** At least one applicable allow is required.
- An explicit applicable deny takes precedence over role or individual allows.
- Record scopes: `self`, `own_party`, `assigned`, or `all`, supported only where their meaning is defined. Assigned-resource access remains unavailable until an assignment model exists.
- A direct grant does not bypass an applicable deny or permit access to another customer's invoice.
- Check permissions on the server for every action and again inside posting/issuing workflows. Hiding a button is not authorization.
- A privileged exception needs a separate permission, an explicit reason, and an audit event; no hidden superuser bypass for quantity, stock, or financial rules.

## 4. Initial business-setting catalog

These are **proposed defaults**, not seed rows. They apply only where supported by the final document model.

### A. Quantities and stock

| Key                                        | Proposed default | Notes                                                                  |
| ------------------------------------------ | ---------------- | ---------------------------------------------------------------------- |
| `invoice.sales.allow_zero_quantity`        | false            | Zero-quantity sales draft lines                                        |
| `invoice.purchase.allow_zero_quantity`     | false            | Zero-quantity purchase draft lines                                     |
| `invoice.sales.allow_negative_quantity`    | false            | Pending decision on returns/credit-note modeling                       |
| `invoice.purchase.allow_negative_quantity` | false            | Pending decision on supplier returns                                   |
| `invoice.allow_zero_value_document`        | false            | Separate from zero-quantity items                                      |
| `quantity.allow_fractional`                | true             | Only for units/products permitting fractions                           |
| `quantity.decimal_places`                  | 3                | Cannot exceed the current NUMERIC(...,3) capacity                      |
| `stock.allow_negative_balance`             | false            | Allow on-hand below zero; distinct from signed movements               |
| `stock.require_available_quantity`         | true             | Must be consistent with negative-balance policy                        |
| `stock.allow_backorder`                    | false            | Unavailable ordered quantity stays unfulfilled; not a fake stock issue |
| `stock.require_adjustment_reason`          | true             | Existing invariant; not relaxable through ordinary settings            |
| `stock.require_adjustment_approval`        | true             | Approver needs a separate permission                                   |
| `stock.require_transfer_approval`          | true             | Warehouse transfers require controlled posting                         |

**Important:** a stock-out movement normally has a negative `quantity_delta`; a stock-in movement normally has a positive delta. Disabling “negative invoice quantity” must not block legitimate stock-out ledger entries. Negative invoice quantity, negative stock balance, and signed stock movement are three different concepts.

Zero-quantity draft lines must never post a zero stock movement. Whether zero-value lines may appear on an issued document remains an explicit document-type/legal review decision.

### B. Pricing, discounts, payments, and credit

| Key                                       | Proposed default                                     |
| ----------------------------------------- | ---------------------------------------------------- |
| `pricing.allow_zero_unit_price`           | false                                                |
| `pricing.allow_manual_price`              | false; also requires permission                      |
| `pricing.allow_below_cost`                | false; only enforce once cost basis is defined       |
| `discount.max_line_percent`               | 0 until configured                                   |
| `discount.max_document_percent`           | 0 until configured                                   |
| `discount.require_reason`                 | true                                                 |
| `discount.require_approval_above_percent` | 0                                                    |
| `payment.allow_partial`                   | true                                                 |
| `payment.allow_overpayment`               | false                                                |
| `payment.require_refund_approval`         | true                                                 |
| `credit.allow_sales_on_credit`            | false                                                |
| `credit.limit_amount`                     | unset; credit blocked until configured with currency |
| `credit.payment_terms_days`               | 0                                                    |
| `credit.block_overdue_customer`           | true                                                 |

Percent values are bounded to 0–100. Monetary limits include a currency and cannot be compared across currencies without an approved conversion policy. Cost-based rules require an agreed costing/valuation model; the current product table does not establish that model. Settings must not pretend to implement it.

### C. Document lifecycle and validation

| Key                                          | Proposed default                                                        |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| `invoice.sales.require_customer`             | true for customer-specific issuance; walk-in policy separately reviewed |
| `invoice.purchase.require_supplier`          | true                                                                    |
| `invoice.require_identity_validation`        | true at issuance; rules depend on party/document type                   |
| `invoice.require_approval_before_issue`      | true                                                                    |
| `invoice.allow_backdated_issue`              | false                                                                   |
| `invoice.max_backdate_days`                  | 0                                                                       |
| `invoice.allow_future_issue_date`            | false                                                                   |
| `invoice.require_payment_before_fulfillment` | true, subject to approved credit policy                                 |
| `invoice.require_cancellation_reason`        | true                                                                    |
| `invoice.number_prefix`                      | explicit business configuration                                         |
| `invoice.number_reset_period`                | explicit choice, not automatically legal for every document             |
| `invoice.default_currency`                   | DZD proposed, pending confirmation                                      |
| `invoice.default_language`                   | fr proposed; permit ar/en                                               |
| `invoice.print_show_internal_reference`      | false                                                                   |

Immutable rules, not ordinary switches: never delete an issued financial document to hide it, never rewrite an issued document silently, never allow duplicate issued document numbers, and never accept nonfinite numeric values. Corrections use an explicit controlled reversal/credit-note workflow. Tax rates, rounding, numbering, required legal identifiers, and retention need jurisdiction/document review; this catalog is not a compliance certification.

### D. Party and operational defaults

| Key                                            | Proposed default                          |
| ---------------------------------------------- | ----------------------------------------- |
| `customer.require_verified_account_for_portal` | true                                      |
| `supplier.require_approval_before_purchase`    | true                                      |
| `party.allow_inactive_for_new_documents`       | false                                     |
| `party.default_payment_terms_days`             | 0                                         |
| `product.default_unit_code`                    | each                                      |
| `warehouse.default_id`                         | unset                                     |
| `approval.purchase_threshold_amount`           | unset: approval required until configured |
| `notification.invoice_issued`                  | true                                      |
| `notification.payment_received`                | true                                      |
| `notification.low_stock`                       | true                                      |
| `audit.log_sensitive_policy_changes`           | true; invariant, not user-disableable     |

Notification delivery still needs implemented channels and preferences; a setting alone sends nothing. Configuration of the existing OS backup schedule remains deployment-controlled, not editable arbitrary commands in the database. Do not add a toggle to include NIN or fiscal identifiers in embeddings.

## 5. Initial permission catalog

Each action is separate; no broad “can manage everything” flag.

| Area                         | Proposed permission codes                                                                                                                                                                                                      |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sales invoices               | `invoice.sales.create_draft`, `invoice.sales.read`, `invoice.sales.edit_draft`, `invoice.sales.submit`, `invoice.sales.approve`, `invoice.sales.issue`, `invoice.sales.cancel`, `invoice.sales.print`, `invoice.sales.export`  |
| Purchase invoices            | `invoice.purchase.create_draft`, `invoice.purchase.read`, `invoice.purchase.edit_draft`, `invoice.purchase.submit`, `invoice.purchase.approve`, `invoice.purchase.issue`, `invoice.purchase.cancel`, `invoice.purchase.export` |
| Credit notes / returns       | `credit_note.create_draft`, `credit_note.approve`, `credit_note.issue`, `return.receive`, `return.dispatch`                                                                                                                    |
| Payments and credit          | `payment.record`, `payment.read`, `payment.refund`, `payment.approve_refund`, `credit.approve`, `credit.change_limit`                                                                                                          |
| Stock                        | `stock.read`, `stock.receive`, `stock.issue`, `stock.adjust`, `stock.approve_adjustment`, `stock.transfer`, `stock.approve_transfer`, `stock.count`                                                                            |
| Pricing exceptions           | `pricing.change`, `pricing.override`, `discount.apply`, `discount.approve`, `pricing.approve_below_cost`                                                                                                                       |
| Master data                  | `product.create`, `product.update`, `product.archive`, `customer.create`, `customer.update`, `customer.archive`, `supplier.create`, `supplier.update`, `supplier.archive`                                                      |
| Sensitive information        | `party.identifiers.read`, `party.identifiers.update`, `party.identifiers.export`, `party.nin.read`, `party.nin.update`                                                                                                         |
| Settings                     | `settings.read`, `settings.update_own_preferences`, `settings.update_scoped`, `settings.update_global`, `settings.update_role`, `settings.approve_exception`                                                                   |
| Authorization administration | `role.assign`, `role.permissions.manage`, `subject.permissions.manage`, `party.memberships.manage`                                                                                                                             |
| Audit/reporting              | `audit.read`, `report.sales.read`, `report.purchases.read`, `report.stock.read`, `report.financial.export`                                                                                                                     |

Do not grant scoped-settings write access merely because somebody can edit their UI preferences. Role assignment and direct grants must be bounded by the grantor's delegation authority so users cannot grant themselves invoice-issuance or administrator rights.

### Examples matching your request

1. **Allow the client role to create a facture:** allow `invoice.sales.create_draft` for role `client`, with `own_party` scope. Default recommendation: this creates a draft/request, not a legally issued invoice.
2. **Allow one client_id:** create an allow rule for that customer party and action. It applies only to authenticated users with an active authorized membership of that customer account.
3. **Block one client despite a role grant:** an explicit customer-party deny wins.
4. **Allow staff to work for any customer:** separate role/user permission with `all` scope; never infer this from portal permissions.
5. **Permit a quantity exception:** authorization must allow the action and the effective setting must allow it. A scoped setting may relax a global restriction only for an explicitly overridable most-specific key. SQL integrity constraints still apply; the setting alone does not authorize invoice creation.

Supplier portal permissions follow the same identity/scope checks. A supplier may submit information about its own documents; it does not automatically gain permission to post receipts, issue buyer-side purchase documents, or approve payments.

## 6. Dependencies and changes required before execution

1. **Invoices do not yet exist in the schema.** Current `sales_orders` / `purchase_orders` are not invoice tables. Define a distinct invoice/credit-note lifecycle, or explicitly decide how orders relate to invoices, before activating invoice rules.
2. Existing order-item quantities enforce `quantity > 0`, and their monetary checks assume positive quantities. A settings row cannot override a SQL CHECK. Signed invoice lines need an intentional new document/line model and revised tax/discount/return semantics; do not simply remove a check.
3. Stock direction constraints must remain consistent. A stock issue is negative even when all user-entered invoice quantities are positive.
4. JSON settings cannot alter database constraints or run code. The backend will resolve approved policies and enforce them in transactions when implementation is requested.
5. Version and audit settings/permission changes. Capture relevant effective policy/version with issued documents so later settings edits do not reinterpret history.
6. Avoid authorization bypass during cache/replication failure: use version-aware caches, invalidate revoked permissions promptly, and fail closed for sensitive actions if policy cannot be resolved.
7. Cross-schema writes can now share one PostgreSQL transaction. Use the same transaction manager for business changes and audit writes; reliable external event delivery still needs its own design.

## 7. Delivery phases

1. Approved: separate quantity/balance controls, own-client drafts, dedicated settings schema, and explicitly overridable most-specific values.
2. Declared: registry, GSettings, scoped Settings, and permission/membership structures; see SETTINGS_SCHEMA.md. No values or grants seeded.
3. Separately review invoice/credit-note declarations and the monetary/stock invariants they require.
4. Only on a later request: seed definitions/defaults and role grants, implement policy resolution, API enforcement, administration UI, and tests.

Suggested tests for that later implementation: multiple conflicting roles, deny-overrides, expired grants, spoofed client_id, revoked party membership, decimal/currency limits, zero and negative quantities, policy changes during issuance, and audit/backup privacy.

## SQL routine implementation update

The approved operational starter and full four-strategy SQL resolver are now declared in `007`–`009`; see [ERP_ROUTINES.md](ERP_ROUTINES.md). The optional catalog script supplies ten conservative default definitions and permission names but no access assignments, and has not been executed. API wiring, administration writes, approval workflows and live acceptance tests remain outstanding. Earlier delivery phases above describe the original plan.

## Remaining work, not blockers for these declarations

Before seeding or runtime implementation, configure the explicit scope order and overridability of each catalog key, define invoice/credit-note document semantics and any assigned-resource relationships, and review jurisdiction-dependent monetary/document rules. No unresolved runtime choice is silently implemented by these SQL files.
