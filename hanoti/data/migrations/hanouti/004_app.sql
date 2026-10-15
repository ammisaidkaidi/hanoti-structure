-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: app.
-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.
BEGIN;


CREATE TABLE app.user_preferences (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  auth_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  locale VARCHAR(35) NOT NULL DEFAULT 'en' CHECK (btrim(locale) <> ''),
  time_zone VARCHAR(64) NOT NULL DEFAULT 'UTC' CHECK (btrim(time_zone) <> ''),
  theme VARCHAR(16) NOT NULL DEFAULT 'system' CHECK (theme IN ('system', 'light', 'dark')),
  preferences JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(preferences) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE app.files (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Metadata only: object bytes live in private filesystem/object storage.
  storage_backend VARCHAR(32) NOT NULL CHECK (btrim(storage_backend) <> ''),
  storage_container VARCHAR(160) NOT NULL CHECK (btrim(storage_container) <> ''),
  storage_key TEXT NOT NULL CHECK (btrim(storage_key) <> ''),
  original_name VARCHAR(255) NOT NULL CHECK (btrim(original_name) <> ''),
  content_type VARCHAR(160) NOT NULL CHECK (btrim(content_type) <> ''),
  byte_size BIGINT NOT NULL CHECK (byte_size >= 0),
  sha256 VARCHAR(64) CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'available', 'quarantined', 'deleted')),
  uploaded_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  UNIQUE (storage_backend, storage_container, storage_key),
  CHECK ((status = 'deleted') = (deleted_at IS NOT NULL))
);
CREATE INDEX files_uploaded_by_idx ON app.files (uploaded_by_user_id);
CREATE INDEX files_status_created_idx ON app.files (status, created_at);

CREATE TABLE app.notifications (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind VARCHAR(80) NOT NULL CHECK (btrim(kind) <> ''),
  title VARCHAR(240) NOT NULL CHECK (btrim(title) <> ''),
  body TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload) = 'object'),
  read_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (read_at IS NULL OR read_at >= created_at),
  CHECK (archived_at IS NULL OR archived_at >= created_at)
);
CREATE INDEX notifications_user_date_idx ON app.notifications (auth_user_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON app.notifications (auth_user_id, created_at DESC)
  WHERE read_at IS NULL AND archived_at IS NULL;

CREATE TABLE app.feature_flags (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  key VARCHAR(120) PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_.-]*$'),
  description TEXT,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  configuration JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(configuration) = 'object'),
  updated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX feature_flags_updated_by_idx ON app.feature_flags (updated_by_user_id);

CREATE TABLE app.audit_events (
  frozen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_schema VARCHAR(8) NOT NULL CHECK (source_schema IN ('auth', 'erp', 'app', 'settings')),
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action VARCHAR(160) NOT NULL CHECK (btrim(action) <> ''),
  entity_type VARCHAR(120) NOT NULL CHECK (btrim(entity_type) <> ''),
  -- Text supports UUID entity IDs and non-UUID setting/flag keys.
  entity_id VARCHAR(255),
  request_id VARCHAR(128),
  ip_address INET,
  -- Redact secrets and unnecessary personal data before writing events.
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX audit_events_actor_date_idx ON app.audit_events (actor_user_id, occurred_at DESC);
CREATE INDEX audit_events_entity_idx ON app.audit_events (source_schema, entity_type, entity_id, occurred_at DESC);
CREATE INDEX audit_events_request_idx ON app.audit_events (request_id) WHERE request_id IS NOT NULL;
CREATE INDEX audit_events_occurred_idx ON app.audit_events (occurred_at DESC);

COMMIT;
