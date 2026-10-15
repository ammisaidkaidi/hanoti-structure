from pathlib import Path
import re, shutil
R=Path('/home/user/hanouti')
inputs={
 '002_auth.sql':('auth/001_initial_schema.sql','auth'),
 '003_erp.sql':('erp/001_initial_schema.sql','erp'),
 '004_app.sql':('app/001_initial_schema.sql','app'),
 '005_settings.sql':('app/002_settings_schema.sql','settings'),
 '006_auth_party_permissions.sql':('auth/002_scoped_permissions.sql','auth'),
}
out=R/'data/migrations/hanouti';out.mkdir(parents=True,exist_ok=True)
(out/'001_schemas.sql').write_text('''-- UNAPPLIED DECLARATIONS ONLY — target database: hanouti (PostgreSQL 14+).
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
''')
for output,(input_name,schema) in inputs.items():
 s=(R/'data/migrations'/input_name).read_text()
 s=s[s.index('BEGIN;'):]
 if schema!='settings':s=s.replace('public.',schema+'.')
 s=s.replace('erp.vector(', 'public.vector(')
 s=s.replace('CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;','')
 s=s.replace('CREATE SCHEMA IF NOT EXISTS settings;','')
 s=s.replace('auth.public.', 'auth.').replace('erp.public.','erp.')
 s=s.replace('source_database','source_schema')
 if schema=='app':s=s.replace("source_schema IN ('auth', 'erp', 'app')", "source_schema IN ('auth', 'erp', 'app', 'settings')")
 # Add real nullable cross-schema user attribution FKs. Existing local auth FKs remain untouched.
 if schema in ('app','erp','settings'):
  s=re.sub(r'^(  (?:\w+_user_id|actor_user_id)) UUID([,\n])',r'\1 UUID REFERENCES auth.users(id) ON DELETE SET NULL\2',s,flags=re.M)
  if schema=='app':
   s=s.replace('auth_user_id UUID PRIMARY KEY,','auth_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,')
   s=s.replace('auth_user_id UUID NOT NULL,','auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,')
 if schema=='settings':
  s=s.replace('role_id UUID,','role_id UUID REFERENCES auth.roles(id) ON DELETE RESTRICT,')
  s=s.replace('change_permission_code VARCHAR(128) NOT NULL CHECK', 'change_permission_code VARCHAR(128) NOT NULL REFERENCES auth.permissions(code) ON DELETE RESTRICT CHECK')
 if output=='006_auth_party_permissions.sql':
  s=s.replace('customer_id UUID,','customer_id UUID REFERENCES erp.customers(id) ON DELETE CASCADE,')
  s=s.replace('supplier_id UUID,','supplier_id UUID REFERENCES erp.suppliers(id) ON DELETE CASCADE,')
 # Remove superseded explanatory comments, preserving business constraints and reviewed data fields.
 s='\n'.join(line for line in s.splitlines() if not any(t in line.lower() for t in ['separate database','external auth','external ids','external permission','not a cross-database','external erp','../../','no competing public.settings','002_settings_schema.sql','business settings are declared in the dedicated','pgvector to be installed','provisioning role must be permitted','cross-database foreign keys']))+'\n'
 s=s.replace('setting scope','setting scope')
 header=f'-- UNAPPLIED DECLARATIONS ONLY — database: hanouti; schema: {schema}.\n-- Apply data/migrations/hanouti/*.sql in numbered order. No SQL has been executed.\n'
 if schema=='settings':header+='-- Polymorphic scope_id remains application-validated; direct role/user references are real FKs.\n'
 if output=='006_auth_party_permissions.sql':header+='-- Polymorphic party_id remains application-validated; explicit party permission targets use real FKs.\n'
 (out/output).write_text(header+s)
for name in ('auth','erp','app'):shutil.rmtree(R/'data/migrations'/name)
legacy=R/'data/examples/legacy';legacy.mkdir(parents=True,exist_ok=True)
for source in ['data/migrations/001_create_app_settings.sql','data/seeds/001_development_settings.sql']:
 p=R/source
 if p.exists():shutil.move(str(p),str(legacy/p.name))
p=R/'data/seeds/000_create_databases.sql';p.unlink(missing_ok=True)
(R/'data/seeds/000_create_database.sql').write_text('''-- PROVISIONING DECLARATION ONLY: run with psql against an existing maintenance database.
-- Requires CREATEDB permission; do not use BEGIN or psql --single-transaction.
-- Existing hanouti is left unchanged. Does not create auth/erp/app databases.
\\set ON_ERROR_STOP on
\\set AUTOCOMMIT on
SELECT 'CREATE DATABASE hanouti'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'hanouti')
\\gexec
''')
# Rewrite the offline generator's output layout to a single namespace per SQL schema.
p=R/'data/scripts/generate_entities.py';s=p.read_text()
s=s.replace("for database in ('auth','erp','app'):","for database in ('hanouti',):",1)
s=s.replace("from '../../../types.js'", "from '../../types.js'")
s=s.replace("code/entities/{database}/{schema}/{cls}.ts", "code/entities/{schema}/{cls}.ts")
pos=s.index('for (database,schema),classes in exports.items():')
s=s[:pos]+'''for (database,schema),classes in exports.items():
 emit(ROOT/f'code/entities/{schema}/index.ts','\\n'.join(f"export {{ {cls} }} from './{cls}.js';" for cls in classes))
schemas=('auth','erp','app','settings')
emit(ROOT/'code/entities/index.ts','\\n'.join(f"export * as {schema.title()} from './{schema}/index.js';" for schema in schemas))
registry=[]
for schema in schemas:
 registry.append(f"import * as {schema.title()} from './entities/{schema}/index.js';")
registry.append('\\n// One database and one DataSource; entity grouping is by SQL schema only.')
for schema in schemas:
 values=[f'{schema.title()}.{cls}' for cls in exports[('hanouti',schema)]]
 registry.append(f'export const {schema}Entities = [{", ".join(values)}] as const;')
registry.append('export const entitiesBySchema = { auth: authEntities, erp: erpEntities, app: appEntities, settings: settingsEntities } as const;')
registry.append('export const allEntities = [...authEntities, ...erpEntities, ...appEntities, ...settingsEntities] as const;')
emit(ROOT/'code/entity-registry.ts','\\n'.join(registry))
emit(ROOT/'tests/fixtures/schema-manifest.json',json.dumps(manifest,indent=2))
print(f'Generated {len(manifest["tables"])} entity classes for one database / four schemas; no connection.')
'''
p.write_text(s)
shutil.rmtree(R/'data/code/entities')
# Obsolete compiled entity files would otherwise survive tsc's additive emission.
shutil.rmtree(R/'data/dist',ignore_errors=True)
