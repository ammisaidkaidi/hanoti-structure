# ERP API function prototypes

**Status: async prototypes only.** Every exported operation rejects with `ApiNotImplementedError`. There are no HTTP routes, response writes, authentication/authorization checks, database calls, transactions, stock/payment posting or successful operation results in this package. Do not expose these stubs as working endpoints.

This server-side pnpm workspace is named **`@app/api`** and lives at `hanoti/api/`. It does not replace `packages/server`, `packages/common` or `data`. The running Express application does not import or mount it. Importing the package performs no I/O.

## Folder structure

```text
api/
├── index.ts                     Root exports, including the Erp namespace
├── common/
│   ├── types.ts                 req/res/session/db/data/params/result contract
│   ├── result.ts                ResultType = unknown, pending discussion
│   ├── errors.ts                ApiNotImplementedError
│   ├── not-implemented.ts       Shared throwing helper
│   ├── index.ts                 Shared exports
│   └── README.md                Helper-porting boundaries
├── erp/
│   ├── categories.ts
│   ├── brands.ts
│   ├── products.ts
│   ├── customers.ts
│   ├── suppliers.ts
│   ├── warehouses.ts
│   ├── sales-orders.ts
│   ├── sales-order-items.ts
│   ├── purchase-orders.ts
│   ├── purchase-order-items.ts
│   ├── payments.ts
│   ├── stock.ts
│   ├── order-editing.ts
│   ├── catalog.ts               Inventory only; not routing/authorization
│   └── index.ts                 ERP exports
├── package.json
└── tsconfig.json
```

## Requested async signature

Valid TypeScript expresses the return once, as `Promise<T>`:

```ts
export async function createProduct<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.createProduct');
}
```

The shared argument contract has all seven required properties:

```ts
interface ApiFunctionArgs<P = unknown> {
  req: ApiRequest;
  res: ApiResponse;
  session: ApiSession;
  db: ApiDatabase;
  data: P;
  params: ApiParams;
  result: ResultType;
}
```

- `req` and `res` use **type-only Express 5 imports**, matching the existing server. Express is not loaded or started by this package. Its raw request body is `unknown`, not automatically validated as `P`.
- `db: ApiDatabase` is the caller-supplied TypeORM `DataSource` returned by `@app/data`'s factory. It is a type-only reference: the API does not create, initialize, use or destroy the instance.
- `data: P` is the separately supplied operation payload. A future adapter must validate it; TypeScript generics are not runtime validation.
- `params` is a read-only string/string-array route-parameter dictionary, with possibly absent values. It does not establish record ownership or authorization.
- `session` is deliberately `unknown`: the application authentication/session contract is not implemented. No user identity is fabricated or read from request data.
- **`ResultType = unknown`** is centralized in `common/result.ts`. No status, data, error, HTTP-envelope or mutation semantics have been decided. The stub error's internal `code` does not define ResultType.
- `T` is a placeholder for an eventual operation output. Current functions never resolve successfully, regardless of the chosen type argument. Their result/HTTP-response relationship will be defined later.

The stubs neither inspect nor modify arguments. Each returns a rejected promise rather than a synchronous throw to its caller. Errors contain only a static operation identifier, not request/session contents. There are no fake successful returns or `as T` assertions.

## Task coverage

**79 async prototypes across 13 task files**, covering all 12 current ERP tables plus cross-order editing:

| File                      | Operations                                                                                                                                                                                                                        |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `categories.ts`           | listCategories, getCategory, createCategory, updateCategory, deleteCategory                                                                                                                                                       |
| `brands.ts`               | listBrands, getBrand, createBrand, updateBrand, deleteBrand                                                                                                                                                                       |
| `products.ts`             | listProducts, getProduct, createProduct, updateProduct, deleteProduct                                                                                                                                                             |
| `customers.ts`            | listCustomers, getCustomer, createCustomer, updateCustomer, deleteCustomer                                                                                                                                                        |
| `suppliers.ts`            | listSuppliers, getSupplier, createSupplier, updateSupplier, deleteSupplier                                                                                                                                                        |
| `warehouses.ts`           | listWarehouses, getWarehouse, createWarehouse, updateWarehouse, deleteWarehouse                                                                                                                                                   |
| `sales-orders.ts`         | listSalesOrders, getSalesOrder, getSalesOrderTotals, createSalesOrderDraft, updateSalesOrderDraft, saveSalesOrderDraft, deleteSalesOrderDraft, confirmSalesOrder, cancelSalesOrder, fulfillSalesOrder                             |
| `sales-order-items.ts`    | listSalesOrderItems, getSalesOrderItem, addSalesOrderItem, updateSalesOrderItem, removeSalesOrderItem, replaceSalesOrderItems                                                                                                     |
| `purchase-orders.ts`      | listPurchaseOrders, getPurchaseOrder, getPurchaseOrderTotals, createPurchaseOrderDraft, updatePurchaseOrderDraft, savePurchaseOrderDraft, deletePurchaseOrderDraft, placePurchaseOrder, cancelPurchaseOrder, receivePurchaseOrder |
| `purchase-order-items.ts` | listPurchaseOrderItems, getPurchaseOrderItem, addPurchaseOrderItem, updatePurchaseOrderItem, removePurchaseOrderItem, replacePurchaseOrderItems                                                                                   |
| `payments.ts`             | listPayments, getPayment, createPayment, updatePayment, voidPayment, refundPayment, getSalesPaymentBalance                                                                                                                        |
| `stock.ts`                | listStockMovements, getStockMovement, getStockBalance, adjustStock, transferStock                                                                                                                                                 |
| `order-editing.ts`        | openOrderEdit, renewOrderEdit, closeOrderEdit, forceCloseOrderEdit, getOrderEditStatus                                                                                                                                            |

No invoice model or application freeze/unfreeze functions are added. There are deliberately no generic ledger update/delete or payment hard-delete prototypes. Lifecycle/payment-writing names reserve future task locations only: their eligibility, posting, approval and reversal rules still require design before implementation. A prototype is not an approved permission or an executable workflow.

`erpPrototypeCatalog` inventories every function and identifies existing public SQL candidates where applicable. It is **not** a dispatcher, route map, permission allowlist, SQL binding or statement that the wrapper is implemented. It covers the 13 already-declared public ERP routines; every JavaScript wrapper still rejects. A null SQL candidate means no dedicated protected SQL operation has been declared for that prototype.

## Future implementation boundaries

When implementations are explicitly approved:

1. Derive the actor from trusted authentication, validate input, and decide ResultType/output handling before using req/res/result. Do not accept an actor or administrative privilege from the submitted payload.
2. Keep database lifecycle and connection ownership explicit. Use protected functions where available, not private helpers or broader backend table grants.
3. Retain policy **AND** permission for manual sale-price overrides; preserve scoped authorization, explicit denials, frozen protection, optimistic timestamps and lock-version fencing.
4. Keep the single-editor five-minute lock contract and explicit supervisor close/reopen. No application-user freeze/unfreeze rights are implied.
5. Preserve database-maintained product `fullName` and item snapshot rules. Do not trust client-supplied product labels.
6. Granular item functions are prototypes, not existing append/edit SQL entry points. The current draft save replaces all items; implementing granular methods needs a reviewed protected approach, not an unguarded direct INSERT/UPDATE/DELETE.
7. Creation, update and combined save draft functions are alternative API-level entry shapes for the same declared writer; no differing payload contracts or implementation behavior has been chosen yet.
8. Lifecycle operations, receipts, payment recording/refunds and posting remain unimplemented. Approval-required stock operations remain blocked by the existing declarations.

## Imports and checks

For future use, add `"@app/api": "workspace:*"` to the consuming server workspace and build this package. No consumer dependency has been added yet. Imports can then use the root, namespace, or task subpath:

```ts
import { createProduct, type ApiFunctionArgs } from '@app/api';
import { Erp } from '@app/api';
import { saveSalesOrderDraft } from '@app/api/erp/sales-orders';
import type { ResultType } from '@app/api/common';
```

These are import examples, not installed server routes. Build/test output is under `api/dist` and is not tracked in the source ZIP.

```sh
pnpm --filter @app/api typecheck
pnpm --filter @app/api test
pnpm --filter @app/api build
pnpm check
```

The hanouti workspace includes `api`, `packages/*`, `data`, and the external sibling `../.test`; the root build includes the API package and root checks explicitly include the sibling test workspace. Tests verify all exported stubs reject without touching arguments, all current ERP tables/public SQL candidates are inventoried, and the generic/opaque type contract is retained. No database connection or SQL execution is required or performed.

## Centralized tests and logs

Tests now live in [`../.test/api/`](../../.test/api/) and their TypeScript configuration is `../.test/api/tsconfig.test.json`. `pnpm --filter @app/api test` delegates to the central `@app/tests` workspace. Production typechecking stays in this package; `pnpm --filter @app/tests typecheck` checks test code. Fixtures and historical logs are under `../.test/`, not production source directories. This relocation has not been validated by running checks.
