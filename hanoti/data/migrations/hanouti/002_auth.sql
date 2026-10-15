-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: auth.
-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.
BEGIN;

CREATE TABLE auth.users (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(320) NOT NULL,
  display_name VARCHAR(160) NOT NULL,
  phone VARCHAR(32),
  -- Store only a password KDF hash (e.g. Argon2id), never plaintext.
  -- NULL permits an externally authenticated account; provisioning enforces its auth method.
  password_hash TEXT,
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'active', 'suspended', 'archived')),
  email_verified_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT users_email_format CHECK (
    email = btrim(email) AND position('@' IN email) > 1
  ),
  CONSTRAINT users_display_name_not_blank CHECK (btrim(display_name) <> ''),
  CONSTRAINT users_password_hash_not_blank CHECK (password_hash IS NULL OR btrim(password_hash) <> '')
);
CREATE UNIQUE INDEX users_email_ci_uq ON auth.users (lower(email));
CREATE INDEX users_status_idx ON auth.users (status);

CREATE TABLE auth.roles (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name VARCHAR(120) NOT NULL CHECK (btrim(name) <> ''),
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE auth.permissions (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(128) NOT NULL UNIQUE CHECK (code ~ '^[a-z][a-z0-9_.:-]*$'),
  description TEXT,
  resource_type VARCHAR(80) NOT NULL CHECK (btrim(resource_type) <> ''),
  supported_scopes TEXT[] NOT NULL,
  risk_level VARCHAR(12) NOT NULL DEFAULT 'normal' CHECK (risk_level IN ('normal', 'sensitive', 'critical')),
  is_delegable BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (
    array_ndims(supported_scopes) = 1
    AND cardinality(supported_scopes) BETWEEN 1 AND 4
    AND supported_scopes <@ ARRAY['self', 'own_party', 'assigned', 'all']::text[]
    AND array_position(supported_scopes, NULL) IS NULL
  )
);

CREATE TABLE auth.user_roles (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES auth.roles(id) ON DELETE CASCADE,
  granted_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role_id)
);
CREATE INDEX user_roles_role_idx ON auth.user_roles (role_id);
CREATE INDEX user_roles_granted_by_idx ON auth.user_roles (granted_by_user_id);

CREATE TABLE auth.role_permissions (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  role_id UUID NOT NULL REFERENCES auth.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES auth.permissions(id) ON DELETE CASCADE,
  effect VARCHAR(5) NOT NULL CHECK (effect IN ('allow', 'deny')),
  record_scope VARCHAR(12) NOT NULL CHECK (record_scope IN ('self', 'own_party', 'assigned', 'all')),
  valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  valid_until TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  granted_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  change_reason TEXT NOT NULL CHECK (btrim(change_reason) <> ''),
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (role_id, permission_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX role_permissions_permission_idx ON auth.role_permissions (permission_id);
CREATE INDEX role_permissions_grantor_idx ON auth.role_permissions (granted_by_user_id);
CREATE INDEX role_permissions_expiry_idx ON auth.role_permissions (valid_until) WHERE valid_until IS NOT NULL;

CREATE TABLE auth.sessions (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- SHA-256 hex digest of a high-entropy opaque token; never the raw bearer token.
  token_hash VARCHAR(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  CHECK (expires_at > created_at),
  CHECK (last_seen_at IS NULL OR last_seen_at >= created_at),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX sessions_user_idx ON auth.sessions (user_id);
CREATE INDEX sessions_expiry_idx ON auth.sessions (expires_at);

CREATE TABLE auth.password_reset_tokens (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash VARCHAR(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  CHECK (expires_at > created_at),
  CHECK (used_at IS NULL OR (used_at >= created_at AND used_at <= expires_at))
);
CREATE INDEX password_reset_tokens_user_idx ON auth.password_reset_tokens (user_id);
CREATE INDEX password_reset_tokens_expiry_idx ON auth.password_reset_tokens (expires_at);

CREATE TABLE auth.email_verification_tokens (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Bind verification to the exact email address being verified.
  email VARCHAR(320) NOT NULL CHECK (email = btrim(email) AND position('@' IN email) > 1),
  token_hash VARCHAR(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  CHECK (expires_at > created_at),
  CHECK (used_at IS NULL OR (used_at >= created_at AND used_at <= expires_at))
);
CREATE INDEX email_verification_tokens_user_idx ON auth.email_verification_tokens (user_id);
CREATE INDEX email_verification_tokens_expiry_idx ON auth.email_verification_tokens (expires_at);

COMMIT;
