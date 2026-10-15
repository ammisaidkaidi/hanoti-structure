-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: settings.
-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.
-- Polymorphic scope_id remains application-validated; direct role/user references are real FKs.
BEGIN;



CREATE TABLE settings.setting_definitions (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  key VARCHAR(160) PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_.-]*$'),
  category VARCHAR(64) NOT NULL CHECK (btrim(category) <> ''),
  description TEXT NOT NULL CHECK (btrim(description) <> ''),
  value_type VARCHAR(16) NOT NULL CHECK (value_type IN (
    'boolean', 'integer', 'decimal', 'string', 'enum', 'uuid', 'object', 'currency_amount'
  )),
  -- JSON null represents an explicitly unset default, not a missing row.
  default_value JSONB NOT NULL,
  allow_null BOOLEAN NOT NULL DEFAULT FALSE,
  enum_values JSONB,
  minimum_value NUMERIC,
  maximum_value NUMERIC,
  unit VARCHAR(32) CHECK (unit IS NULL OR btrim(unit) <> ''),
  -- Declarative constraints only: never executable code or SQL expressions.
  validation_rules JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(validation_rules) = 'object'),
  -- Least-specific to most-specific. Each key explicitly chooses its allowed order.
  -- Global is mandatory and first; role, when supported, is second.
  scope_precedence TEXT[] NOT NULL DEFAULT ARRAY['global']::text[],
  document_kinds TEXT[] NOT NULL DEFAULT '{}'::text[],
  is_overridable BOOLEAN NOT NULL DEFAULT FALSE,
  resolution_strategy VARCHAR(20) NOT NULL DEFAULT 'global_only'
    CHECK (resolution_strategy IN ('global_only', 'most_specific', 'all_must_allow', 'minimum_cap')),
  change_permission_code VARCHAR(128) NOT NULL REFERENCES auth.permissions(code) ON DELETE RESTRICT CHECK (change_permission_code ~ '^[a-z][a-z0-9_.:-]*$'),
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (default_value <> 'null'::jsonb OR allow_null),
  CHECK (
    default_value = 'null'::jsonb
    OR (value_type = 'boolean' AND jsonb_typeof(default_value) = 'boolean')
    OR (value_type IN ('integer', 'decimal') AND jsonb_typeof(default_value) = 'number')
    OR (value_type IN ('string', 'enum', 'uuid') AND jsonb_typeof(default_value) = 'string')
    OR (value_type IN ('object', 'currency_amount') AND jsonb_typeof(default_value) = 'object')
  ),
  CHECK (
    CASE WHEN value_type = 'enum' THEN
      enum_values IS NOT NULL AND jsonb_typeof(enum_values) = 'array'
      AND enum_values <> '[]'::jsonb
      AND (default_value = 'null'::jsonb OR enum_values @> jsonb_build_array(default_value))
    ELSE enum_values IS NULL END
  ),
  CHECK (minimum_value IS NULL OR minimum_value NOT IN ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)),
  CHECK (maximum_value IS NULL OR maximum_value NOT IN ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)),
  CHECK (minimum_value IS NULL OR maximum_value IS NULL OR minimum_value <= maximum_value),
  CHECK ((minimum_value IS NULL AND maximum_value IS NULL) OR value_type IN ('integer', 'decimal', 'currency_amount')),
  CHECK (
    array_ndims(scope_precedence) = 1
    AND array_lower(scope_precedence, 1) = 1
    AND cardinality(scope_precedence) BETWEEN 1 AND 7
    AND scope_precedence[1] = 'global'
    AND scope_precedence <@ ARRAY['global', 'role', 'user', 'customer', 'supplier', 'product', 'warehouse']::text[]
    AND array_position(scope_precedence, NULL) IS NULL
    AND (array_position(scope_precedence, 'role') IS NULL OR array_position(scope_precedence, 'role') = 2)
  ),
  -- Reject duplicate scopes so specificity is unambiguous.
  CHECK (
    cardinality(array_positions(scope_precedence, 'global')) <= 1
    AND cardinality(array_positions(scope_precedence, 'role')) <= 1
    AND cardinality(array_positions(scope_precedence, 'user')) <= 1
    AND cardinality(array_positions(scope_precedence, 'customer')) <= 1
    AND cardinality(array_positions(scope_precedence, 'supplier')) <= 1
    AND cardinality(array_positions(scope_precedence, 'product')) <= 1
    AND cardinality(array_positions(scope_precedence, 'warehouse')) <= 1
  ),
  CHECK (array_position(document_kinds, NULL) IS NULL),
  CHECK (
    (NOT is_overridable AND resolution_strategy = 'global_only' AND scope_precedence = ARRAY['global']::text[])
    OR (is_overridable AND resolution_strategy <> 'global_only' AND cardinality(scope_precedence) > 1)
  ),
  CHECK (resolution_strategy <> 'all_must_allow' OR value_type = 'boolean'),
  CHECK (resolution_strategy <> 'minimum_cap' OR value_type IN ('integer', 'decimal', 'currency_amount'))
);
CREATE INDEX setting_definitions_category_idx ON settings.setting_definitions (category);

CREATE TABLE settings.gsettings (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key VARCHAR(160) NOT NULL REFERENCES settings.setting_definitions(key) ON DELETE RESTRICT,
  scope_type VARCHAR(8) NOT NULL CHECK (scope_type IN ('global', 'role')),
  role_id UUID REFERENCES auth.roles(id) ON DELETE RESTRICT,
  value JSONB NOT NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  valid_until TIMESTAMPTZ,
  change_reason TEXT NOT NULL CHECK (btrim(change_reason) <> ''),
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((scope_type = 'global' AND role_id IS NULL) OR (scope_type = 'role' AND role_id IS NOT NULL)),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
-- PostgreSQL 14-compatible uniqueness, including global rows with null role_id.
CREATE UNIQUE INDEX gsettings_global_key_uq ON settings.gsettings (setting_key) WHERE scope_type = 'global';
CREATE UNIQUE INDEX gsettings_role_key_uq ON settings.gsettings (role_id, setting_key) WHERE scope_type = 'role';
CREATE INDEX gsettings_key_idx ON settings.gsettings (setting_key);
CREATE INDEX gsettings_expiry_idx ON settings.gsettings (valid_until) WHERE valid_until IS NOT NULL;

CREATE TABLE settings.settings (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key VARCHAR(160) NOT NULL REFERENCES settings.setting_definitions(key) ON DELETE RESTRICT,
  scope_type VARCHAR(16) NOT NULL CHECK (scope_type IN ('user', 'customer', 'supplier', 'product', 'warehouse')),
  -- user => auth.users; all other targets => their tables in erp.
  scope_id UUID NOT NULL,
  value JSONB NOT NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  valid_until TIMESTAMPTZ,
  change_reason TEXT NOT NULL CHECK (btrim(change_reason) <> ''),
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (scope_type, scope_id, setting_key),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE INDEX settings_key_idx ON settings.settings (setting_key);
CREATE INDEX settings_expiry_idx ON settings.settings (valid_until) WHERE valid_until IS NOT NULL;

-- This file declares tables only. 008_settings_routines.sql adds the unapplied
-- resolver and resolution-time validation. Controlled administrative writes and
-- definition-change reconciliation still require a reviewed implementation.
-- A scoped value may relax a global value ONLY for a definition explicitly using
-- is_overridable=true and resolution_strategy='most_specific'.
-- Ambiguous values from multiple roles fail closed; deny permissions always win.

COMMIT;
