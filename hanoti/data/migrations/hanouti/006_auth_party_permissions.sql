-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: auth.
-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.
-- Polymorphic party_id remains application-validated; explicit party permission targets use real FKs.
BEGIN;

CREATE TABLE auth.party_memberships (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  party_type VARCHAR(8) NOT NULL CHECK (party_type IN ('customer', 'supplier')),
  party_id UUID NOT NULL,
  status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended', 'revoked')),
  can_act_on_behalf BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at TIMESTAMPTZ,
  verified_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  valid_until TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  revoked_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  change_reason TEXT NOT NULL CHECK (btrim(change_reason) <> ''),
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  UNIQUE (user_id, party_type, party_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (status <> 'active' OR verified_at IS NOT NULL),
  CHECK (NOT can_act_on_behalf OR (status = 'active' AND verified_at IS NOT NULL)),
  CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX party_memberships_party_idx ON auth.party_memberships (party_type, party_id);
CREATE INDEX party_memberships_expiry_idx ON auth.party_memberships (valid_until) WHERE valid_until IS NOT NULL;
CREATE INDEX party_memberships_verifier_idx ON auth.party_memberships (verified_by_user_id);
CREATE INDEX party_memberships_revoker_idx ON auth.party_memberships (revoked_by_user_id);
CREATE INDEX party_memberships_creator_idx ON auth.party_memberships (created_by_user_id);
CREATE INDEX party_memberships_updater_idx ON auth.party_memberships (updated_by_user_id);

CREATE TABLE auth.subject_permissions (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_id UUID NOT NULL REFERENCES auth.permissions(id) ON DELETE CASCADE,
  subject_type VARCHAR(8) NOT NULL CHECK (subject_type IN ('user', 'customer', 'supplier')),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES erp.customers(id) ON DELETE CASCADE,
  supplier_id UUID REFERENCES erp.suppliers(id) ON DELETE CASCADE,
  effect VARCHAR(5) NOT NULL CHECK (effect IN ('allow', 'deny')),
  record_scope VARCHAR(12) NOT NULL CHECK (record_scope IN ('self', 'own_party', 'assigned', 'all')),
  valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  valid_until TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  granted_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  revoked_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  change_reason TEXT NOT NULL CHECK (btrim(change_reason) <> ''),
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (
    (subject_type = 'user' AND user_id IS NOT NULL AND customer_id IS NULL AND supplier_id IS NULL)
    OR (subject_type = 'customer' AND customer_id IS NOT NULL AND user_id IS NULL AND supplier_id IS NULL)
    OR (subject_type = 'supplier' AND supplier_id IS NOT NULL AND user_id IS NULL AND customer_id IS NULL)
  ),
  -- Party-level grants cannot authorize work on some other party's records.
  CHECK (subject_type = 'user' OR record_scope = 'own_party'),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
-- One non-revoked rule per permission/subject; expiry alone does not free a slot.
-- Updating/replacing a rule must explicitly retire its prior row and record an audit.
CREATE UNIQUE INDEX subject_permissions_user_uq
  ON auth.subject_permissions (user_id, permission_id) WHERE user_id IS NOT NULL AND revoked_at IS NULL;
CREATE UNIQUE INDEX subject_permissions_customer_uq
  ON auth.subject_permissions (customer_id, permission_id) WHERE customer_id IS NOT NULL AND revoked_at IS NULL;
CREATE UNIQUE INDEX subject_permissions_supplier_uq
  ON auth.subject_permissions (supplier_id, permission_id) WHERE supplier_id IS NOT NULL AND revoked_at IS NULL;
CREATE INDEX subject_permissions_permission_idx ON auth.subject_permissions (permission_id);
CREATE INDEX subject_permissions_grantor_idx ON auth.subject_permissions (granted_by_user_id);
CREATE INDEX subject_permissions_revoker_idx ON auth.subject_permissions (revoked_by_user_id);
CREATE INDEX subject_permissions_expiry_idx ON auth.subject_permissions (valid_until) WHERE valid_until IS NOT NULL;

-- Authorization contract (007_authorization_routines.sql now declares its evaluator):
-- * At least one applicable allow, no applicable deny, and valid resource ownership.
-- * Party rules require an active verified membership, can_act_on_behalf=true,
--   matching party ID, active user, and a currently valid time interval.
-- * Client role/party invoice grants initially cover own drafts/requests only.
--   Final issuance has its own permission; no such grants are supplied here.
-- * 'self' means the authenticated user's own resource; 'assigned' requires an
--   explicit assignment model (not yet declared) and must fail closed until supported.
-- * Setting overrides never bypass authorization or immutable database constraints.

COMMIT;
