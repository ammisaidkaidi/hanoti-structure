-- UNAPPLIED DECLARATIONS ONLY — target database: hanouti (PostgreSQL 14+).
-- One migration history across all four business schemas. No seed rows or grants.
-- pgvector must already be installed on the PostgreSQL host/service.
BEGIN;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS erp;
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS settings;
-- public hosts the extension type only; business tables use the four schemas above.
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
COMMIT;
