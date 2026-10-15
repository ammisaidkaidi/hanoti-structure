-- PostgreSQL example; apply with a migration tool you choose, not on server startup.
BEGIN;
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMIT;
