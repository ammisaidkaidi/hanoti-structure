# Product full names and order-item snapshots

**Unapplied declarations only.** No SQL, database connection or API wiring has been executed. This changes the fresh baseline, not an existing deployed database.

## Columns

The three tables below have a required, nonblank **TEXT** column named `full_name`, exposed by TypeORM as **`fullName: string`**:

- `erp.products`
- `erp.sales_order_items`
- `erp.purchase_order_items`

TEXT avoids truncating a composed name containing long attributes or dimensions. The product's existing `name`, descriptive components and `description` remain separate. Item `description` and `sku_snapshot` are retained; neither replaces the new full-name snapshot.

## Product recomposition

After the generic metadata/frozen guard, `b_product_full_name` runs on product INSERT and ordinary UPDATE. Its private function, `erp._product_full_name_guard()`, builds the stored value in this order:

```text
[ABR] [Name] [Attr] [Material] [Dims] [Color] [Brand] /[Serie] [MadeIn] [Quality] [Ref]
```

Components are trimmed, missing components are omitted, and present components are joined with one space. Interior formatting within a component is retained. The brand label comes from `erp.brands.name`; the slash is added only when a series exists. A product with only `name = 'Drill'` gets `full_name = 'Drill'`.

Example:

```text
DR Drill Cordless Steel 20 mm Black Acme /X1 Algeria A REF-1
```

The database derives the value rather than trusting a supplied full_name. Editing a frozen product is still rejected. An administrator's standalone frozen/unfrozen flag transition preserves the stored full name; it does not silently combine a metadata change with a catalog-label refresh.

**Shared-brand boundary:** renaming a row in `erp.brands` does not itself update product rows. Its latest label is incorporated on the next ordinary update to each product. There is no automatic brand-to-product rewrite or bypass of frozen products in this revision.

## Capturing item snapshots

The sales/purchase draft writer reads the product under `FOR SHARE`, including `full_name`, and inserts it into each item. The existing item guard independently enforces the copy for every permitted INSERT, including privileged direct SQL:

```text
new item.fullName = referenced product.fullName
```

The existing actor, permission, lock/version and frozen checks are not bypassed. The item guard obtains a product share lock while copying, and ignores a caller-supplied label on INSERT. If an existing item's product_id is explicitly replaced by permitted privileged DML, its full-name snapshot is recaptured for that new product. Ordinary quantity/price changes to the same stored item retain its name; rewriting the snapshot alone is rejected.

Later catalog changes do not automatically rewrite existing item snapshots. A frozen but active product can still be used, subject to ordinary business rules; freezing does not mean inactivity.

**Important existing-save behavior:** whole-document saves delete/recreate the item list. Those replacement rows are newly created items and capture the product's latest stored full_name. Snapshots are preserved for existing rows, not across delete/recreate operations. Frozen-line replacement remains blocked.

## Reading names without accepting client-controlled labels

`erp.order_detail(actor, kind, order_id)` still returns `summary` and the editable `document`, and now adds a read-only `item_snapshots` array:

```json
{
  "item_snapshots": [
    {
      "id": "<item-uuid>",
      "line_number": 1,
      "product_id": "<product-uuid>",
      "full_name": "DR Drill Cordless Steel 20 mm Black Acme /X1 Algeria A REF-1"
    }
  ]
}
```

SQL JSON uses snake_case; TypeORM properties use camelCase. A future API can map names explicitly. The editable `document.lines` schema remains unchanged: clients submit product IDs, quantities and permitted price/discount/tax inputs, **not full_name/fullName**. Keeping the read metadata separate allows `document` to round-trip through the existing strict save validation.

## Privileges, testing and deployment

The routine owner receives only the additional required SELECT access to product full_name and brand id/name. The new trigger function is private, uses a fixed search_path and has PUBLIC execution revoked. Backend direct table grants and exposed function count remain unchanged. There are now 38 functions, including 15 backend entry points.

Offline tests check the three mappings, composition declaration, trigger attachment, snapshot copying, read metadata and privilege declarations. `../.test/data/sql/erp_routines_full_names.integration.sql` contains **unexecuted** scenarios for optional components, long labels, supplied-label overrides, product freezing, preserved snapshots, brand-label refresh and replacement saves.

Before deployment, run those assertions and actual non-admin-login/concurrent product-edit tests in a disposable PostgreSQL database. Existing production tables would require an explicit column/backfill/NOT NULL and trigger rollout plan; do not apply this fresh baseline as an incremental upgrade.
