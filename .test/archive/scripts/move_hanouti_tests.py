from pathlib import Path
import json,re,shutil
root=Path('/home/user/hanouti'); dest=root/'.test';dest.mkdir(exist_ok=True)
# Keep each suite's identity; move fixtures and SQL assertions with the data suite.
for old,new in [('data/tests','data'),('api/tests','api'),('packages/common/tests','packages/common'),('packages/server/tests','packages/server')]:
 target=dest/new;target.parent.mkdir(parents=True,exist_ok=True);shutil.move(str(root/old),str(target))
for old,new in [('data/tsconfig.test.json','data/tsconfig.test.json'),('api/tsconfig.test.json','api/tsconfig.test.json'),('packages/server/tsconfig.test.json','packages/server/tsconfig.test.json')]:
 shutil.move(str(root/old),str(dest/new))
(dest/'data/scripts').mkdir()
shutil.move(str(root/'data/scripts/validate_routines.py'),str(dest/'data/scripts/validate_routines.py'))
logs=dest/'logs';logs.mkdir()
for p in Path('/home/user').glob('hanouti*.log'):shutil.move(str(p),str(logs/p.name))
# Project-owned logs only; leave installed dependencies and third-party skill content intact.
excluded={'node_modules','dist','.git','.cache','.agents','agent','.test'}
for p in root.rglob('*.log'):
 if not set(p.relative_to(root).parts)&excluded:
  target=logs/'project'/p.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True);shutil.move(str(p),str(target))
# Relocated imports and fixture reads.
for p in (dest/'data').glob('*.ts'):
 s=p.read_text().replace("'../code/", "'../../data/code/")
 if p.name=='entities.test.ts':
  s=s.replace('new URL(`../${path}`','new URL(`../../data/${path}`')
 elif p.name=='connection-policy.test.ts':
  s=s.replace("new URL('../', import.meta.url)","new URL('../../data/', import.meta.url)")
 else:
  s=s.replace('new URL(`../${path}`','new URL(`../../${path}`')
  for quote in ("'",'`'):
   s=s.replace('read('+quote+'migrations/', 'read('+quote+'data/migrations/')
   s=s.replace('read('+quote+'seeds/', 'read('+quote+'data/seeds/')
   s=s.replace('read('+quote+'tests/sql/', 'read('+quote+'.test/data/sql/')
 p.write_text(s)
p=dest/'api/prototypes.test.ts';s=p.read_text().replace("'../index.js'","'../../api/index.js'").replace("'../common/","'../../api/common/").replace("'../erp/","'../../api/erp/")
s=s.replace("'../../data/tests/fixtures/","'../data/fixtures/").replace("new URL('../package.json'","new URL('../../api/package.json'").replace('new URL(`../erp/','new URL(`../../api/erp/');p.write_text(s)
for package in ('common','server'):
 for p in (dest/f'packages/{package}').glob('*.ts'):
  s=p.read_text().replace("'../src/",f"'../../../packages/{package}/src/");p.write_text(s)
p=dest/'packages/server/backup.test.ts';s=p.read_text().replace("import { tmpdir } from 'node:os';", "import { fileURLToPath } from 'node:url';")
s=s.replace("  const root = await mkdtemp(join(tmpdir(), 'hanouti-backup-'));", "  const temporaryDirectory = fileURLToPath(new URL('../../.tmp/', import.meta.url));\n  await mkdir(temporaryDirectory, { recursive: true });\n  const root = await mkdtemp(join(temporaryDirectory, 'hanouti-backup-'));");p.write_text(s)
# Explicit paths permit test source files to live outside production package directories.
configs={
 'data':('../../data/tsconfig.json','../..',['../../data/code/**/*.ts','./*.ts']),
 'api':('../../api/tsconfig.json','../..',['../../api/index.ts','../../api/common/**/*.ts','../../api/erp/**/*.ts','./*.ts']),
 'packages/common':('../../../packages/common/tsconfig.json','../../..',['../../../packages/common/src/**/*.ts','./*.ts']),
 'packages/server':('../../../packages/server/tsconfig.json','../../..',['../../../packages/server/src/**/*.ts','./*.ts']),
}
for name,(extends,rootdir,include) in configs.items():
 (dest/name/'tsconfig.test.json').write_text(json.dumps({'extends':extends,'compilerOptions':{'rootDir':rootdir,'noEmit':True},'include':include},indent=2)+'\n')
# Test dependencies belong to the test workspace, so package resolution works from .test/.
test_package={
 'name':'@app/tests','version':'0.1.0','private':True,'type':'module',
 'description':'Centralized Hanouti tests, fixtures, offline SQL validation and local test artifacts',
 'scripts':{
  'test':'vitest run --config vitest.config.ts',
  'test:api':'vitest run --config vitest.config.ts api',
  'test:data':'vitest run --config vitest.config.ts data',
  'test:common':'vitest run --config vitest.config.ts packages/common',
  'test:server':'vitest run --config vitest.config.ts packages/server',
  'typecheck':'tsc -p data/tsconfig.test.json && tsc -p api/tsconfig.test.json && tsc -p packages/common/tsconfig.test.json && tsc -p packages/server/tsconfig.test.json'
 },
 'devDependencies':{
  '@app/api':'workspace:*','@app/common':'workspace:*','@app/data':'workspace:*','@app/server':'workspace:*',
  '@types/node':'^22.20.5','@types/supertest':'^6.0.3','pg':'8.23.1','supertest':'^7.1.4',
  'typeorm':'1.1.2','typescript':'~5.9.3','vitest':'^3.2.7'
 },
 'engines':{'node':'^20.19.0 || ^22.13.0 || >=24.11.0'}
}
(dest/'package.json').write_text(json.dumps(test_package,indent=2)+'\n')
(dest/'vitest.config.ts').write_text("""import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// An explicit root includes this hidden folder and keeps all test artifacts together.
export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  cacheDir: fileURLToPath(new URL('./.cache/vitest/', import.meta.url)),
  test: {
    include: ['api/**/*.test.ts', 'data/**/*.test.ts', 'packages/**/*.test.ts'],
    coverage: {
      reportsDirectory: fileURLToPath(new URL('./coverage/', import.meta.url)),
    },
  },
});
""")
for package,suite in [('api','api'),('data','data'),('packages/common','common'),('packages/server','server')]:
 p=root/package/'package.json';obj=json.loads(p.read_text());obj['scripts']['test']=f'pnpm --filter @app/tests test:{suite}'
 obj['scripts']['typecheck']='tsc -p tsconfig.json --noEmit'
 obj.get('devDependencies',{}).pop('vitest',None)
 if suite=='server':
  obj['devDependencies'].pop('supertest',None);obj['devDependencies'].pop('@types/supertest',None)
 p.write_text(json.dumps(obj,indent=2)+'\n')
p=root/'package.json';obj=json.loads(p.read_text());obj['scripts']['test']='pnpm --filter @app/common build && pnpm --filter @app/data build && pnpm --filter @app/tests test';p.write_text(json.dumps(obj,indent=2)+'\n')
p=root/'pnpm-workspace.yaml';s=p.read_text().replace("  - 'api'", "  - 'api'\n  - '.test'");p.write_text(s)
# Update importer metadata only, reusing existing resolutions. No install/check is run.
p=root/'pnpm-lock.yaml';s=p.read_text();importers,remainder=s.split('\npackages:\n',1)
importers=re.sub(r"(?m)^      (?:vitest|supertest|'@types/supertest'):\n(?:        [^\n]*\n)+",'',importers)
versions={'@app/api':'link:../api','@app/common':'link:../packages/common','@app/data':'link:../data','@app/server':'link:../packages/server','@types/node':'22.20.5','@types/supertest':'6.0.3','pg':'8.23.1','supertest':'7.3.1','typeorm':'1.1.2(pg@8.23.1)','typescript':'5.9.3','vitest':'3.2.7(@types/node@22.20.5)(jiti@1.21.7)(tsx@4.23.15)'}
block='\n  .test:\n    devDependencies:\n'
for name,specifier in test_package['devDependencies'].items():
 key=f"'{name}'" if name.startswith('@') else name
 block+=f'      {key}:\n        specifier: {specifier}\n        version: {versions[name]}\n'
importers=importers.replace('\n  api:\n',block+'\n  api:\n',1);p.write_text(importers+'\npackages:\n'+remainder)
# Production mapping generation still owns entity output; only its manifest destination moves.
p=root/'data/scripts/generate_entities.py';s=p.read_text().replace('see tests/fixtures/schema-manifest.json','see .test/data/fixtures/schema-manifest.json').replace("emit(ROOT/'tests/fixtures/schema-manifest.json'", "emit(ROOT.parent/'.test/data/fixtures/schema-manifest.json'");p.write_text(s)
for p in (root/'data/code/entities').rglob('*.ts'):
 s=p.read_text().replace('see tests/fixtures/schema-manifest.json','see .test/data/fixtures/schema-manifest.json');p.write_text(s)
p=dest/'data/scripts/validate_routines.py';s=p.read_text().replace('root = Path(__file__).resolve().parents[1]', "root = Path(__file__).resolve().parents[3] / 'data'\ntests = Path(__file__).resolve().parents[1]").replace("(root / 'tests/fixtures/routines-manifest.json')", "(tests / 'fixtures/routines-manifest.json')").replace("(root / 'tests/sql')", "(tests / 'sql')");p.write_text(s)
p=root/'.gitignore';p.write_text(p.read_text()+'\n# Centralized local test artifacts (test source remains versioned)\n.test/logs/\n.test/.tmp/\n.test/.cache/\n.test/coverage/\n')
p=root/'.prettierignore';p.write_text(p.read_text()+'\n# Historical logs and generated test artifacts\n.test/logs/\n.test/.tmp/\n.test/.cache/\n.test/coverage/\n')
# Old logs are historical records: do not edit their contents or imply they validate this move.
print('Moved project test suites, fixtures, test configs, SQL validator and saved logs into .test/. Updated imports, scripts and dependency metadata. No checks executed.')
