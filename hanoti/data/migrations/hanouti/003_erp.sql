-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: erp.
-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.
BEGIN;



CREATE TABLE erp.categories (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id UUID REFERENCES erp.categories(id) ON DELETE RESTRICT,
  code VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(code) <> ''),
  name VARCHAR(160) NOT NULL CHECK (btrim(name) <> ''),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE INDEX categories_parent_idx ON erp.categories (parent_id);

CREATE TABLE erp.brands (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(160) NOT NULL CHECK (btrim(name) <> ''),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX brands_name_ci_uq ON erp.brands (lower(name));

CREATE TABLE erp.products (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku VARCHAR(80) NOT NULL CHECK (btrim(sku) <> ''),
  barcode VARCHAR(128) UNIQUE CHECK (barcode IS NULL OR btrim(barcode) <> ''),
  -- Product components: [ABR] [Name] [Attr] [Material] [Dims] [Color]
  -- [Brand] /[Serie] [MadeIn] [Quality] [Ref]. full_name is maintained by a database trigger.
  abbreviation TEXT CHECK (abbreviation IS NULL OR btrim(abbreviation) <> ''),
  name VARCHAR(240) NOT NULL CHECK (btrim(name) <> ''),
  -- Database-maintained composed label; components remain authoritative.
  full_name TEXT NOT NULL CHECK (btrim(full_name) <> ''),
  attributes TEXT CHECK (attributes IS NULL OR btrim(attributes) <> ''),
  material TEXT CHECK (material IS NULL OR btrim(material) <> ''),
  dimensions TEXT CHECK (dimensions IS NULL OR btrim(dimensions) <> ''),
  color TEXT CHECK (color IS NULL OR btrim(color) <> ''),
  brand_id UUID REFERENCES erp.brands(id) ON DELETE RESTRICT,
  series TEXT CHECK (series IS NULL OR btrim(series) <> ''),
  made_in TEXT CHECK (made_in IS NULL OR btrim(made_in) <> ''),
  quality TEXT CHECK (quality IS NULL OR btrim(quality) <> ''),
  reference TEXT CHECK (reference IS NULL OR btrim(reference) <> ''),
  -- Nullable until generated; non-NULL values must have exactly 4096 dimensions.
  embedding public.vector(4096),
  description TEXT,
  category_id UUID REFERENCES erp.categories(id) ON DELETE RESTRICT,
  kind VARCHAR(16) NOT NULL DEFAULT 'stock' CHECK (kind IN ('stock', 'service')),
  unit_code VARCHAR(16) NOT NULL DEFAULT 'each' CHECK (btrim(unit_code) <> ''),
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  sale_price NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (sale_price >= 0 AND sale_price <> 'NaN'::numeric),
  reorder_level NUMERIC(18,3) NOT NULL DEFAULT 0 CHECK (reorder_level >= 0 AND reorder_level <> 'NaN'::numeric),
  tags TEXT[] NOT NULL DEFAULT '{}',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX products_sku_ci_uq ON erp.products (lower(sku));
CREATE INDEX products_category_idx ON erp.products (category_id);
CREATE INDEX products_brand_idx ON erp.products (brand_id);

CREATE TABLE erp.customers (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(code) <> ''),
  name VARCHAR(240) NOT NULL CHECK (btrim(name) <> ''),
  -- Optional professional/legal profile; rules depend on the party and transaction.
  -- See data/ALGERIAN_PARTIES.md for official sources and validation limits.
  party_type VARCHAR(16) CHECK (party_type IN ('natural_person', 'legal_person')),
  first_name VARCHAR(120) CHECK (first_name IS NULL OR btrim(first_name) <> ''),
  last_name VARCHAR(120) CHECK (last_name IS NULL OR btrim(last_name) <> ''),
  legal_name VARCHAR(240) CHECK (legal_name IS NULL OR btrim(legal_name) <> ''),
  legal_form VARCHAR(80) CHECK (legal_form IS NULL OR btrim(legal_form) <> ''),
  job_title TEXT CHECK (job_title IS NULL OR btrim(job_title) <> ''),
  job_info TEXT CHECK (job_info IS NULL OR btrim(job_info) <> ''),
  business_activity TEXT CHECK (business_activity IS NULL OR btrim(business_activity) <> ''),
  activity_code VARCHAR(32) CHECK (activity_code IS NULL OR btrim(activity_code) <> ''),
  contact_person_name VARCHAR(240) CHECK (contact_person_name IS NULL OR btrim(contact_person_name) <> ''),
  email VARCHAR(320),
  phone VARCHAR(32),
  fax VARCHAR(32) CHECK (fax IS NULL OR btrim(fax) <> ''),
  -- Algerian identifiers are strings: preserve leading zeros; validate format only.
  nif VARCHAR(20) CHECK (nif IS NULL OR nif ~ '^([0-9]{15}|[0-9]{20})$'),
  nis VARCHAR(18) CHECK (nis IS NULL OR nis ~ '^([0-9]{15}|[0-9]{18})$'),
  rc VARCHAR(64) CHECK (rc IS NULL OR btrim(rc) <> ''),
  -- NIN belongs to this party, not automatically to its representative/contact.
  -- Optional: collect only for a justified purpose; do not include in embeddings.
  nin VARCHAR(18) CHECK (nin IS NULL OR nin ~ '^[0-9]{18}$'),
  article_imposition VARCHAR(32) CHECK (article_imposition IS NULL OR btrim(article_imposition) <> ''),
  professional_registration_type VARCHAR(80)
    CHECK (professional_registration_type IS NULL OR btrim(professional_registration_type) <> ''),
  professional_registration_number VARCHAR(128)
    CHECK (professional_registration_number IS NULL OR btrim(professional_registration_number) <> ''),
  share_capital NUMERIC(20,2) CHECK (share_capital IS NULL OR (share_capital >= 0 AND share_capital <> 'NaN'::numeric)),
  share_capital_currency VARCHAR(3) CHECK (share_capital_currency IS NULL OR share_capital_currency ~ '^[A-Z]{3}$'),
  -- Legacy/foreign tax reference only. Use nif for the Algerian fiscal identifier.
  tax_identifier VARCHAR(80),
  address JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(address) = 'object'),
  -- Authenticated customer-account links are declared in auth.erp.party_memberships.
  -- No second auth_user_id mapping is kept here in this unapplied baseline.
  -- Nullable until generated; non-NULL values must have exactly 4096 dimensions.
  embedding public.vector(4096),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((share_capital IS NULL) = (share_capital_currency IS NULL)),
  CHECK ((professional_registration_type IS NULL) = (professional_registration_number IS NULL))
);
CREATE INDEX customers_nif_idx ON erp.customers (nif) WHERE nif IS NOT NULL;
CREATE INDEX customers_nis_idx ON erp.customers (nis) WHERE nis IS NOT NULL;
CREATE INDEX customers_rc_idx ON erp.customers (rc) WHERE rc IS NOT NULL;
CREATE INDEX customers_name_ci_idx ON erp.customers (lower(name));

CREATE TABLE erp.suppliers (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(code) <> ''),
  name VARCHAR(240) NOT NULL CHECK (btrim(name) <> ''),
  -- Optional professional/legal profile; rules depend on the party and transaction.
  -- See data/ALGERIAN_PARTIES.md for official sources and validation limits.
  party_type VARCHAR(16) CHECK (party_type IN ('natural_person', 'legal_person')),
  first_name VARCHAR(120) CHECK (first_name IS NULL OR btrim(first_name) <> ''),
  last_name VARCHAR(120) CHECK (last_name IS NULL OR btrim(last_name) <> ''),
  legal_name VARCHAR(240) CHECK (legal_name IS NULL OR btrim(legal_name) <> ''),
  legal_form VARCHAR(80) CHECK (legal_form IS NULL OR btrim(legal_form) <> ''),
  job_title TEXT CHECK (job_title IS NULL OR btrim(job_title) <> ''),
  job_info TEXT CHECK (job_info IS NULL OR btrim(job_info) <> ''),
  business_activity TEXT CHECK (business_activity IS NULL OR btrim(business_activity) <> ''),
  activity_code VARCHAR(32) CHECK (activity_code IS NULL OR btrim(activity_code) <> ''),
  contact_person_name VARCHAR(240) CHECK (contact_person_name IS NULL OR btrim(contact_person_name) <> ''),
  email VARCHAR(320),
  phone VARCHAR(32),
  fax VARCHAR(32) CHECK (fax IS NULL OR btrim(fax) <> ''),
  -- Algerian identifiers are strings: preserve leading zeros; validate format only.
  nif VARCHAR(20) CHECK (nif IS NULL OR nif ~ '^([0-9]{15}|[0-9]{20})$'),
  nis VARCHAR(18) CHECK (nis IS NULL OR nis ~ '^([0-9]{15}|[0-9]{18})$'),
  rc VARCHAR(64) CHECK (rc IS NULL OR btrim(rc) <> ''),
  -- NIN belongs to this party, not automatically to its representative/contact.
  -- Optional: collect only for a justified purpose; do not include in embeddings.
  nin VARCHAR(18) CHECK (nin IS NULL OR nin ~ '^[0-9]{18}$'),
  article_imposition VARCHAR(32) CHECK (article_imposition IS NULL OR btrim(article_imposition) <> ''),
  professional_registration_type VARCHAR(80)
    CHECK (professional_registration_type IS NULL OR btrim(professional_registration_type) <> ''),
  professional_registration_number VARCHAR(128)
    CHECK (professional_registration_number IS NULL OR btrim(professional_registration_number) <> ''),
  share_capital NUMERIC(20,2) CHECK (share_capital IS NULL OR (share_capital >= 0 AND share_capital <> 'NaN'::numeric)),
  share_capital_currency VARCHAR(3) CHECK (share_capital_currency IS NULL OR share_capital_currency ~ '^[A-Z]{3}$'),
  -- Legacy/foreign tax reference only. Use nif for the Algerian fiscal identifier.
  tax_identifier VARCHAR(80),
  address JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(address) = 'object'),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((share_capital IS NULL) = (share_capital_currency IS NULL)),
  CHECK ((professional_registration_type IS NULL) = (professional_registration_number IS NULL))
);
CREATE INDEX suppliers_nif_idx ON erp.suppliers (nif) WHERE nif IS NOT NULL;
CREATE INDEX suppliers_nis_idx ON erp.suppliers (nis) WHERE nis IS NOT NULL;
CREATE INDEX suppliers_rc_idx ON erp.suppliers (rc) WHERE rc IS NOT NULL;

CREATE TABLE erp.warehouses (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(code) <> ''),
  name VARCHAR(160) NOT NULL CHECK (btrim(name) <> ''),
  address JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(address) = 'object'),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE erp.sales_orders (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  locked_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  locked_at TIMESTAMPTZ,
  lock_version BIGINT NOT NULL DEFAULT 0 CHECK (lock_version >= 0),
  CHECK ((locked_by IS NULL) = (locked_at IS NULL)),
  CHECK (locked_by IS NULL OR lock_version > 0),
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(order_number) <> ''),
  customer_id UUID REFERENCES erp.customers(id) ON DELETE RESTRICT,
  warehouse_id UUID REFERENCES erp.warehouses(id) ON DELETE RESTRICT,
  status VARCHAR(16) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'confirmed', 'fulfilled', 'cancelled')),
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  customer_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(customer_snapshot) = 'object'),
  notes TEXT,
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ordered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fulfilled_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Supports same-currency payment foreign keys without a cross-table trigger.
  UNIQUE (id, currency_code),
  CHECK ((status = 'fulfilled') = (fulfilled_at IS NOT NULL)),
  CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);
CREATE INDEX sales_orders_customer_idx ON erp.sales_orders (customer_id);
CREATE INDEX sales_orders_warehouse_idx ON erp.sales_orders (warehouse_id);
CREATE INDEX sales_orders_status_date_idx ON erp.sales_orders (status, ordered_at);
CREATE INDEX sales_orders_created_by_idx ON erp.sales_orders (created_by_user_id);

CREATE TABLE erp.sales_order_items (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_order_id UUID NOT NULL REFERENCES erp.sales_orders(id) ON DELETE RESTRICT,
  line_number INTEGER NOT NULL CHECK (line_number > 0),
  product_id UUID NOT NULL REFERENCES erp.products(id) ON DELETE RESTRICT,
  sku_snapshot VARCHAR(80) NOT NULL CHECK (btrim(sku_snapshot) <> ''),
  -- Product full_name captured on insertion or product replacement; never a live label.
  full_name TEXT NOT NULL CHECK (btrim(full_name) <> ''),
  description VARCHAR(500) NOT NULL CHECK (btrim(description) <> ''),
  unit_code VARCHAR(16) NOT NULL CHECK (btrim(unit_code) <> ''),
  quantity NUMERIC(18,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
  unit_price NUMERIC(18,4) NOT NULL CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric),
  discount_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0 AND discount_amount <> 'NaN'::numeric),
  tax_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0 AND tax_amount <> 'NaN'::numeric),
  -- Currency is inherited from the order. Tax is an explicit line-total snapshot.
  line_total NUMERIC(24,4) GENERATED ALWAYS AS
    (round(quantity * unit_price - discount_amount + tax_amount, 4)) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (sales_order_id, line_number),
  UNIQUE (id, product_id),
  CHECK (discount_amount <= quantity * unit_price)
);
CREATE INDEX sales_order_items_product_idx ON erp.sales_order_items (product_id);

CREATE TABLE erp.purchase_orders (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  locked_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  locked_at TIMESTAMPTZ,
  lock_version BIGINT NOT NULL DEFAULT 0 CHECK (lock_version >= 0),
  CHECK ((locked_by IS NULL) = (locked_at IS NULL)),
  CHECK (locked_by IS NULL OR lock_version > 0),
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number VARCHAR(64) NOT NULL UNIQUE CHECK (btrim(order_number) <> ''),
  supplier_id UUID NOT NULL REFERENCES erp.suppliers(id) ON DELETE RESTRICT,
  warehouse_id UUID NOT NULL REFERENCES erp.warehouses(id) ON DELETE RESTRICT,
  status VARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  supplier_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(supplier_snapshot) = 'object'),
  expected_on DATE,
  notes TEXT,
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ordered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  received_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((status = 'received') = (received_at IS NOT NULL)),
  CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);
CREATE INDEX purchase_orders_supplier_idx ON erp.purchase_orders (supplier_id);
CREATE INDEX purchase_orders_warehouse_idx ON erp.purchase_orders (warehouse_id);
CREATE INDEX purchase_orders_status_date_idx ON erp.purchase_orders (status, ordered_at);
CREATE INDEX purchase_orders_created_by_idx ON erp.purchase_orders (created_by_user_id);

CREATE TABLE erp.purchase_order_items (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id UUID NOT NULL REFERENCES erp.purchase_orders(id) ON DELETE RESTRICT,
  line_number INTEGER NOT NULL CHECK (line_number > 0),
  product_id UUID NOT NULL REFERENCES erp.products(id) ON DELETE RESTRICT,
  sku_snapshot VARCHAR(80) NOT NULL CHECK (btrim(sku_snapshot) <> ''),
  -- Product full_name captured on insertion or product replacement; never a live label.
  full_name TEXT NOT NULL CHECK (btrim(full_name) <> ''),
  description VARCHAR(500) NOT NULL CHECK (btrim(description) <> ''),
  unit_code VARCHAR(16) NOT NULL CHECK (btrim(unit_code) <> ''),
  quantity NUMERIC(18,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
  unit_cost NUMERIC(18,4) NOT NULL CHECK (unit_cost >= 0 AND unit_cost <> 'NaN'::numeric),
  discount_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0 AND discount_amount <> 'NaN'::numeric),
  tax_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0 AND tax_amount <> 'NaN'::numeric),
  line_total NUMERIC(24,4) GENERATED ALWAYS AS
    (round(quantity * unit_cost - discount_amount + tax_amount, 4)) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (purchase_order_id, line_number),
  UNIQUE (id, product_id),
  CHECK (discount_amount <= quantity * unit_cost)
);
CREATE INDEX purchase_order_items_product_idx ON erp.purchase_order_items (product_id);

CREATE TABLE erp.payments (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_order_id UUID NOT NULL,
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  direction VARCHAR(8) NOT NULL DEFAULT 'receipt' CHECK (direction IN ('receipt', 'refund')),
  method VARCHAR(16) NOT NULL CHECK (method IN ('cash', 'card', 'bank_transfer', 'other')),
  status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'voided')),
  amount NUMERIC(18,4) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
  provider VARCHAR(80),
  provider_reference VARCHAR(160),
  -- Required unique business key to prevent duplicate payment postings.
  idempotency_key VARCHAR(128) NOT NULL UNIQUE CHECK (btrim(idempotency_key) <> ''),
  recorded_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (sales_order_id, currency_code)
    REFERENCES erp.sales_orders(id, currency_code) ON DELETE RESTRICT,
  CHECK (status <> 'completed' OR paid_at IS NOT NULL),
  CHECK (provider_reference IS NULL OR (provider IS NOT NULL AND btrim(provider) <> '' AND btrim(provider_reference) <> ''))
);
CREATE UNIQUE INDEX payments_provider_reference_uq
  ON erp.payments (provider, provider_reference) WHERE provider_reference IS NOT NULL;
CREATE INDEX payments_order_idx ON erp.payments (sales_order_id);
CREATE INDEX payments_recorded_by_idx ON erp.payments (recorded_by_user_id);
CREATE INDEX payments_status_date_idx ON erp.payments (status, created_at);

CREATE TABLE erp.stock_movements (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES erp.products(id) ON DELETE RESTRICT,
  warehouse_id UUID NOT NULL REFERENCES erp.warehouses(id) ON DELETE RESTRICT,
  kind VARCHAR(16) NOT NULL CHECK (kind IN (
    'opening', 'purchase', 'sale', 'return_in', 'return_out',
    'adjustment', 'transfer_in', 'transfer_out'
  )),
  quantity_delta NUMERIC(18,3) NOT NULL CHECK (quantity_delta <> 0 AND quantity_delta <> 'NaN'::numeric),
  sales_order_item_id UUID,
  purchase_order_item_id UUID,
  transfer_group_id UUID,
  idempotency_key VARCHAR(128) NOT NULL UNIQUE CHECK (btrim(idempotency_key) <> ''),
  reason TEXT,
  recorded_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (sales_order_item_id, product_id)
    REFERENCES erp.sales_order_items(id, product_id) ON DELETE RESTRICT,
  FOREIGN KEY (purchase_order_item_id, product_id)
    REFERENCES erp.purchase_order_items(id, product_id) ON DELETE RESTRICT,
  CHECK (num_nonnulls(sales_order_item_id, purchase_order_item_id) <= 1),
  CHECK (sales_order_item_id IS NULL OR kind IN ('sale', 'return_in')),
  CHECK (purchase_order_item_id IS NULL OR kind IN ('purchase', 'return_out')),
  CHECK (
    (kind IN ('opening', 'purchase', 'return_in', 'transfer_in') AND quantity_delta > 0)
    OR (kind IN ('sale', 'return_out', 'transfer_out') AND quantity_delta < 0)
    OR kind = 'adjustment'
  ),
  CHECK ((kind IN ('transfer_in', 'transfer_out')) = (transfer_group_id IS NOT NULL)),
  CHECK (kind <> 'adjustment' OR (reason IS NOT NULL AND btrim(reason) <> ''))
);
CREATE INDEX stock_movements_balance_idx ON erp.stock_movements (product_id, warehouse_id, occurred_at);
CREATE INDEX stock_movements_warehouse_idx ON erp.stock_movements (warehouse_id);
CREATE INDEX stock_movements_sales_item_idx ON erp.stock_movements (sales_order_item_id);
CREATE INDEX stock_movements_purchase_item_idx ON erp.stock_movements (purchase_order_item_id);
CREATE INDEX stock_movements_transfer_idx ON erp.stock_movements (transfer_group_id) WHERE transfer_group_id IS NOT NULL;
CREATE INDEX stock_movements_recorded_by_idx ON erp.stock_movements (recorded_by_user_id);

COMMIT;
