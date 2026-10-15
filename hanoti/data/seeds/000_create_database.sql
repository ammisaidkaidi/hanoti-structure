-- PROVISIONING DECLARATION ONLY: run with psql against an existing maintenance database.
-- Requires CREATEDB permission; do not use BEGIN or psql --single-transaction.
-- Existing hanouti is left unchanged. Does not create auth/erp/app databases.
\set ON_ERROR_STOP on
\set AUTOCOMMIT on
SELECT 'CREATE DATABASE hanouti'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'hanouti')
\gexec
