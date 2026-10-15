"""Regenerate server-only TypeORM mappings from reviewed SQL declarations.
Requires Python 3.10+ and pglast==8.6; never connects to PostgreSQL.
Generated entity files are overwritten. Review changes before committing.
"""
from pathlib import Path
import hashlib
import json
import re
from collections import defaultdict
from pglast import ast, parse_sql
from pglast.stream import RawStream

ROOT = Path(__file__).resolve().parents[1]
CLASSES = {
 'users':'User','roles':'Role','permissions':'Permission','user_roles':'UserRole',
 'role_permissions':'RolePermission','sessions':'Session','password_reset_tokens':'PasswordResetToken',
 'email_verification_tokens':'EmailVerificationToken','subject_permissions':'SubjectPermission',
 'party_memberships':'PartyMembership','categories':'Category','brands':'Brand','products':'Product',
 'customers':'Customer','suppliers':'Supplier','warehouses':'Warehouse','sales_orders':'SalesOrder',
 'sales_order_items':'SalesOrderItem','purchase_orders':'PurchaseOrder','purchase_order_items':'PurchaseOrderItem',
 'payments':'Payment','stock_movements':'StockMovement','user_preferences':'UserPreference','files':'File',
 'notifications':'Notification','feature_flags':'FeatureFlag','audit_events':'AuditEvent',
 'setting_definitions':'SettingDefinition','gsettings':'GSettings','settings':'Setting',
}
TYPE_MAP={'uuid':('uuid','string'),'varchar':('varchar','string'),'text':('text','string'),
 'int4':('integer','number'),'int8':('bigint','string'),'bool':('boolean','boolean'),
 'numeric':('numeric','string'),'timestamptz':('timestamptz','Date'),'date':('date','string'),
 'inet':('inet','string'),'jsonb':('jsonb','JsonValue'),'vector':('vector','number[]')}
HIDDEN={'password_hash','token_hash','nin','nif','nis','tax_identifier','embedding'}
def camel(value):
 parts=value.split('_');return parts[0]+''.join(x.title() for x in parts[1:])
def q(value):return json.dumps(value,ensure_ascii=False)
def raw(node):return RawStream()(node)
def arr(values):return '['+', '.join(q(v) for v in values)+']'
def emit(path,text):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text.rstrip()+'\n')
manifest={'files':{},'tables':[]}
exports=defaultdict(list)
for database in ('hanouti',):
 statements=[]
 for path in sorted((ROOT/'migrations'/database).glob('*.sql')):
  manifest['files'][str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
  statements.extend(x.stmt for x in parse_sql(path.read_text()))
 table_nodes=[x for x in statements if isinstance(x,ast.CreateStmt)]
 for table in table_nodes:
  schema=table.relation.schemaname or 'public';name=table.relation.relname;cls=CLASSES[name]
  columns=[x for x in table.tableElts if isinstance(x,ast.ColumnDef)]
  table_constraints=[x for x in table.tableElts if isinstance(x,ast.Constraint)]
  constraints=[]
  for col in columns:
   constraints.extend((c,col.colname) for c in col.constraints or [])
  constraints.extend((c,None) for c in table_constraints)
  primary=[]
  for c,col in constraints:
   if c.contype.name=='CONSTR_PRIMARY':primary.extend([col] if col else [v.sval for v in c.keys])
  assert primary,name
  checks=[];uniques=[];foreign_keys=[]
  for c,col in constraints:
   kind=c.contype.name
   if kind=='CONSTR_CHECK':checks.append({'name':c.conname,'expression':raw(c.raw_expr)})
   if kind=='CONSTR_UNIQUE':uniques.append([col] if col else [v.sval for v in c.keys])
   if kind=='CONSTR_FOREIGN':
    refcols=[x.sval for x in c.pk_attrs or []]
    assert refcols,'Explicit referenced columns required'
    foreign_keys.append({'target':c.pktable.relname,'schema':c.pktable.schemaname or 'public',
      'columns':[col] if col else [x.sval for x in c.fk_attrs],
      'referencedColumns':refcols,'onDelete':{'a':'NO ACTION','r':'RESTRICT','c':'CASCADE','n':'SET NULL','d':'SET DEFAULT'}[c.fk_del_action]})
  indices=[]
  for ix in statements:
   if isinstance(ix,ast.IndexStmt) and ix.relation.relname==name and (ix.relation.schemaname or 'public')==schema:
    complex_index=any(not elem.name or elem.ordering.name!='SORTBY_DEFAULT' for elem in ix.indexParams)
    indices.append({'name':ix.idxname,'columns':[e.name for e in ix.indexParams if e.name],
      'unique':ix.unique,'where':raw(ix.whereClause) if ix.whereClause else None,'sqlManaged':complex_index})
  imports={'Entity','Column'}; decorators=[f'@Entity({{ name: {q(name)}, schema: {q(schema)}, synchronize: false }})']
  for check in checks:
   imports.add('Check'); args=(q(check['name'])+', ' if check['name'] else '')+q(check['expression'])
   decorators.append(f'@Check({args})')
  for fields in uniques:
   imports.add('Unique');decorators.append(f'@Unique({arr([camel(x) for x in fields])})')
  for fk in foreign_keys:
   imports.add('ForeignKey');decorators.append(f'@ForeignKey({q(CLASSES[fk["target"]])}, {arr([camel(x) for x in fk["columns"]])}, {arr([camel(x) for x in fk["referencedColumns"]])}, {{ onDelete: {q(fk["onDelete"])} }})')
  for index in indices:
   imports.add('Index')
   if index['sqlManaged']:
    decorators.append(f'@Index({q(index["name"])}, {{ synchronize: false }})')
   else:
    opts=['unique: true'] if index['unique'] else []
    if index['where']:opts.append('where: '+q(index['where']))
    suffix=', { '+', '.join(opts)+' }' if opts else ''
    decorators.append(f'@Index({q(index["name"])}, {arr([camel(x) for x in index["columns"]])}{suffix})')
  body=[]; column_manifest=[];uses_json=False
  for col in columns:
   cons={c.contype.name:c for c in col.constraints or []}
   pgtype=col.typeName.names[-1].sval
   typ,ts=TYPE_MAP[pgtype]
   is_array=bool(col.typeName.arrayBounds)
   if is_array:ts+='[]'
   uses_json |= pgtype=='jsonb'
   nullable=col.colname not in primary and 'CONSTR_NOTNULL' not in cons
   default=raw(cons['CONSTR_DEFAULT'].raw_expr) if 'CONSTR_DEFAULT' in cons else None
   generated=raw(cons['CONSTR_GENERATED'].raw_expr) if 'CONSTR_GENERATED' in cons else None
   mods=[v.val.ival for v in col.typeName.typmods or []]
   props=[f'name: {q(col.colname)}',f'type: {q(typ)}']
   if nullable:props.append('nullable: true')
   if is_array:props.append('array: true')
   if mods:
    if typ=='numeric':
     props.append(f'precision: {mods[0]}')
     if len(mods)>1:props.append(f'scale: {mods[1]}')
    else:props.append(f'length: {mods[0]}')
   hidden=col.colname in HIDDEN
   if hidden:props.append('select: false')
   if default is not None:props.append(f'default: () => {q(default)}')
   if generated:props.extend([f'asExpression: {q(generated)}',"generatedType: 'STORED'",'insert: false','update: false'])
   decorator='PrimaryColumn' if col.colname in primary else 'Column'
   imports.add(decorator)
   if col.colname in primary and default=='gen_random_uuid()':props.append("generated: 'uuid'")
   # Narrow simple enum-style column checks without interpreting arbitrary SQL.
   if ts=='string':
    for constraint in col.constraints or []:
     if constraint.contype.name=='CONSTR_CHECK':
      check=raw(constraint.raw_expr)
      m=re.fullmatch(rf'{re.escape(col.colname)} IN \((.+)\)',check)
      if m:
       vals=re.findall(r"'([^']*)'",m.group(1))
       if vals:ts=' | '.join(q(v) for v in vals)
   annotation=ts+(' | null' if nullable else '')
   readonly='readonly ' if generated else ''
   marker='?' if hidden else '!'
   body.extend([f'  @{decorator}({{ '+', '.join(props)+' })',f'  {readonly}{camel(col.colname)}{marker}: {annotation};',''])
   column_manifest.append({'name':col.colname,'property':camel(col.colname),'type':typ,'nullable':nullable,'primary':col.colname in primary,
     'array':is_array,'length':mods[0] if mods and typ!='numeric' else None,'precision':mods[0] if mods and typ=='numeric' else None,
     'scale':mods[1] if len(mods)>1 and typ=='numeric' else None,'default':default,'generated':generated,'hidden':hidden})
  # Some join entities have only primary columns.
  if not any(x['primary'] is False for x in column_manifest):imports.discard('Column')
  text=f'// SQL source: data/migrations/{database}/ (see ../.test/data/fixtures/schema-manifest.json).\n// Generated by data/scripts/generate_entities.py; review SQL before regenerating.\n'
  text+="import 'reflect-metadata';\nimport { "+', '.join(sorted(imports))+" } from 'typeorm';\n"
  if uses_json:text+="import type { JsonValue } from '../../types.js';\n"
  text+='\n'+'\n'.join(decorators)+f'\nexport class {cls} {{\n'+'\n'.join(body)+'}\n'
  emit(ROOT/f'code/entities/{schema}/{cls}.ts',text)
  exports[(database,schema)].append(cls)
  manifest['tables'].append({'database':database,'schema':schema,'name':name,'className':cls,'columns':column_manifest,'checks':checks,'uniqueColumns':uniques,'foreignKeys':foreign_keys,'indexes':indices})
for (database,schema),classes in exports.items():
 emit(ROOT/f'code/entities/{schema}/index.ts','\n'.join(f"export {{ {cls} }} from './{cls}.js';" for cls in classes))
schemas=('auth','erp','app','settings')
emit(ROOT/'code/entities/index.ts','\n'.join(f"export * as {schema.title()} from './{schema}/index.js';" for schema in schemas))
registry=[]
for schema in schemas:
 registry.append(f"import * as {schema.title()} from './entities/{schema}/index.js';")
registry.append('\n// One database and one DataSource; entity grouping is by SQL schema only.')
for schema in schemas:
 values=[f'{schema.title()}.{cls}' for cls in exports[('hanouti',schema)]]
 registry.append(f'export const {schema}Entities = [{", ".join(values)}] as const;')
registry.append('export const entitiesBySchema = { auth: authEntities, erp: erpEntities, app: appEntities, settings: settingsEntities } as const;')
registry.append('export const allEntities = [...authEntities, ...erpEntities, ...appEntities, ...settingsEntities] as const;')
emit(ROOT/'code/entity-registry.ts','\n'.join(registry))
emit(ROOT.parent.parent/'.test/data/fixtures/schema-manifest.json',json.dumps(manifest,indent=2))
print(f'Generated {len(manifest["tables"])} entity classes for one database / four schemas; no connection.')
