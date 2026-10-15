from pathlib import Path
import json
root=Path('/home/user/hanouti'); api=root/'api'
assert not api.exists(), 'Review existing api folder instead of overwriting it.'
(api/'erp').mkdir(parents=True);(api/'common').mkdir();(api/'tests').mkdir()
def write(path,text): (api/path).write_text(text)
tasks={}
for slug,singular,plural in [('categories','Category','Categories'),('brands','Brand','Brands'),('products','Product','Products'),('customers','Customer','Customers'),('suppliers','Supplier','Suppliers'),('warehouses','Warehouse','Warehouses')]:
 tasks[slug]={'tables':[f'erp.{slug}'],'functions':[(f'list{plural}',None),(f'get{singular}',None),(f'create{singular}',None),(f'update{singular}',None),(f'delete{singular}',None)]}
for kind,Title in [('sales','Sales'),('purchase','Purchase')]:
 tasks[f'{kind}-orders']={'tables':[f'erp.{kind}_orders'],'functions':[
 (f'list{Title}Orders',None),(f'get{Title}Order','erp.order_detail'),(f'get{Title}OrderTotals','erp.order_totals'),
 (f'create{Title}OrderDraft',f'erp.save_{kind}_order_draft'),(f'update{Title}OrderDraft',f'erp.save_{kind}_order_draft'),(f'save{Title}OrderDraft',f'erp.save_{kind}_order_draft'),(f'delete{Title}OrderDraft',None),
 *(([(f'confirm{Title}Order',None),(f'cancel{Title}Order',None),(f'fulfill{Title}Order',None)]) if kind=='sales' else [(f'place{Title}Order',None),(f'cancel{Title}Order',None),(f'receive{Title}Order',None)])]}
 tasks[f'{kind}-order-items']={'tables':[f'erp.{kind}_order_items'],'functions':[
 (f'list{Title}OrderItems',None),(f'get{Title}OrderItem',None),(f'add{Title}OrderItem',None),(f'update{Title}OrderItem',None),(f'remove{Title}OrderItem',None),(f'replace{Title}OrderItems',None)]}
tasks['payments']={'tables':['erp.payments'],'functions':[(n,None) for n in ['listPayments','getPayment','createPayment','updatePayment','voidPayment','refundPayment']]+[('getSalesPaymentBalance','erp.sales_payment_balance')]}
tasks['stock']={'tables':['erp.stock_movements'],'functions':[('listStockMovements',None),('getStockMovement',None),('getStockBalance','erp.stock_balance'),('adjustStock','erp.adjust_stock'),('transferStock','erp.transfer_stock')]}
tasks['order-editing']={'tables':['erp.sales_orders','erp.purchase_orders'],'functions':[(n,s) for n,s in [('openOrderEdit','erp.open_order_edit'),('renewOrderEdit','erp.renew_order_edit'),('closeOrderEdit','erp.close_order_edit'),('forceCloseOrderEdit','erp.force_close_order_edit'),('getOrderEditStatus','erp.order_edit_status')]]}
write('common/result.ts','''/** Opaque placeholder. The ResultType contract will be designed separately. */
export type ResultType = unknown;
''')
write('common/types.ts','''import type { Request, Response } from 'express';
import type { ResultType } from './result.js';

/** Route parameters only; not an authorization context or a validation result. */
export type ApiParams = Readonly<Record<string, string | readonly string[] | undefined>>;

/** No session/authentication structure has been agreed or implemented yet. */
export type ApiSession = unknown;

/** Raw HTTP input remains unknown; data is the separately supplied operation payload. */
export type ApiRequest = Request<ApiParams, unknown, unknown>;
export type ApiResponse = Response<unknown>;

/** Shared shape for all async ERP prototypes. All six properties are required. */
export interface ApiFunctionArgs<P = unknown> {
  req: ApiRequest;
  res: ApiResponse;
  session: ApiSession;
  data: P;
  params: ApiParams;
  result: ResultType;
}

/** Generic placeholder signature; concrete payload/output contracts come later. */
export type ApiPrototypeFunction = <P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
) => Promise<T>;
''')
write('common/errors.ts','''/** Internal stub error, not a ResultType definition or an HTTP response contract. */
export class ApiNotImplementedError extends Error {
  readonly code = 'NOT_IMPLEMENTED';
  readonly operation: string;

  constructor(operation: string) {
    super(`Not implemented: ${operation}`);
    this.name = 'ApiNotImplementedError';
    this.operation = operation;
  }
}
''')
write('common/not-implemented.ts','''import { ApiNotImplementedError } from './errors.js';

/** Always throws; never returns fabricated data, sends a response or logs request contents. */
export function notImplemented(operation: string): never {
  throw new ApiNotImplementedError(operation);
}
''')
write('common/index.ts','''export type { ResultType } from './result.js';
export type {
  ApiFunctionArgs,
  ApiParams,
  ApiPrototypeFunction,
  ApiRequest,
  ApiResponse,
  ApiSession,
} from './types.js';
export { ApiNotImplementedError } from './errors.js';
export { notImplemented } from './not-implemented.js';
''')
barrel=[];catalog=[]
for task,spec in tasks.items():
 text=f'''/** {task}: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type {{ ApiFunctionArgs }} from '../common/types.js';
import {{ notImplemented }} from '../common/not-implemented.js';

'''
 ops=[]
 for name,sql in spec['functions']:
  comment=f'Future SQL candidate: {sql}; currently NOT called.' if sql else 'No dedicated public SQL operation is currently declared; implementation requires review.'
  text+=f'''/** {comment} */
export async function {name}<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {{
  void arg;
  return notImplemented('erp.{task}.{name}');
}}

'''
  ops.append({'name':name,'operation':f'erp.{task}.{name}','declaredSqlRoutine':sql})
 write(f'erp/{task}.ts',text)
 barrel.append(f"export * from './{task}.js';")
 catalog.append({'task':task,'tables':spec['tables'],'implementation':'prototype','operations':ops})
write('erp/catalog.ts','''/** Inventory only, NOT an HTTP router, dispatcher, SQL executor or permission allowlist.
 * A SQL candidate does not make its JavaScript wrapper implemented or safe to expose.
 */
export const erpPrototypeCatalog = '''+json.dumps(catalog,indent=2)+' as const;\n')
write('erp/index.ts','\n'.join(barrel)+"\nexport { erpPrototypeCatalog } from './catalog.js';\n")
write('index.ts',"/** Server-side ERP function prototypes. Importing this package performs no I/O. */\nexport * from './common/index.js';\nexport * from './erp/index.js';\nexport * as Erp from './erp/index.js';\n")
package={
 'name':'@app/api','version':'0.1.0','private':True,'type':'module',
 'description':'Server-side ERP async function prototypes; no routes or database lifecycle',
 'files':['dist','README.md'],
 'exports':{'.':{'types':'./dist/index.d.ts','import':'./dist/index.js'},'./common':{'types':'./dist/common/index.d.ts','import':'./dist/common/index.js'},'./erp':{'types':'./dist/erp/index.d.ts','import':'./dist/erp/index.js'},'./erp/*':{'types':'./dist/erp/*.d.ts','import':'./dist/erp/*.js'}},
 'scripts':{'build':'tsc -p tsconfig.json','typecheck':'tsc -p tsconfig.json --noEmit && tsc -p tsconfig.test.json','test':'vitest run'},
 'dependencies':{'@types/express':'5.0.6'},
 'devDependencies':{'@types/node':'^22.20.5','typescript':'~5.9.3','vitest':'^3.2.7'},
 'engines':{'node':'^20.19.0 || ^22.13.0 || >=24.11.0'}}
write('package.json',json.dumps(package,indent=2)+'\n')
write('tsconfig.json',json.dumps({'extends':'../tsconfig.base.json','compilerOptions':{'module':'NodeNext','moduleResolution':'NodeNext','types':['node'],'rootDir':'.','outDir':'dist','declaration':True,'declarationMap':True,'sourceMap':True},'include':['index.ts','common/**/*.ts','erp/**/*.ts']},indent=2)+'\n')
write('tsconfig.test.json',json.dumps({'extends':'./tsconfig.json','compilerOptions':{'noEmit':True},'include':['index.ts','common/**/*.ts','erp/**/*.ts','tests/**/*.ts']},indent=2)+'\n')
p=root/'pnpm-workspace.yaml';s=p.read_text();assert "  - 'data'" in s;s=s.replace("  - 'data'", "  - 'data'\n  - 'api'");p.write_text(s)
p=root/'package.json';obj=json.loads(p.read_text());old=obj['scripts']['build'];assert 'pnpm --filter @app/server build' in old;obj['scripts']['build']=old.replace('pnpm --filter @app/server build','pnpm --filter @app/api build && pnpm --filter @app/server build');p.write_text(json.dumps(obj,indent=2)+'\n')
print(len(tasks),'ERP task files;',sum(len(t['functions']) for t in tasks.values()),'async prototypes; no runtime wiring.')
