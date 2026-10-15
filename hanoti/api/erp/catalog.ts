/** Inventory only, NOT an HTTP router, dispatcher, SQL executor or permission allowlist.
 * A SQL candidate does not make its JavaScript wrapper implemented or safe to expose.
 */
export const erpPrototypeCatalog = [
  {
    task: 'categories',
    tables: ['erp.categories'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listCategories',
        operation: 'erp.categories.listCategories',
        declaredSqlRoutine: null,
      },
      {
        name: 'getCategory',
        operation: 'erp.categories.getCategory',
        declaredSqlRoutine: null,
      },
      {
        name: 'createCategory',
        operation: 'erp.categories.createCategory',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateCategory',
        operation: 'erp.categories.updateCategory',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteCategory',
        operation: 'erp.categories.deleteCategory',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'brands',
    tables: ['erp.brands'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listBrands',
        operation: 'erp.brands.listBrands',
        declaredSqlRoutine: null,
      },
      {
        name: 'getBrand',
        operation: 'erp.brands.getBrand',
        declaredSqlRoutine: null,
      },
      {
        name: 'createBrand',
        operation: 'erp.brands.createBrand',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateBrand',
        operation: 'erp.brands.updateBrand',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteBrand',
        operation: 'erp.brands.deleteBrand',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'products',
    tables: ['erp.products'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listProducts',
        operation: 'erp.products.listProducts',
        declaredSqlRoutine: null,
      },
      {
        name: 'getProduct',
        operation: 'erp.products.getProduct',
        declaredSqlRoutine: null,
      },
      {
        name: 'createProduct',
        operation: 'erp.products.createProduct',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateProduct',
        operation: 'erp.products.updateProduct',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteProduct',
        operation: 'erp.products.deleteProduct',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'customers',
    tables: ['erp.customers'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listCustomers',
        operation: 'erp.customers.listCustomers',
        declaredSqlRoutine: null,
      },
      {
        name: 'getCustomer',
        operation: 'erp.customers.getCustomer',
        declaredSqlRoutine: null,
      },
      {
        name: 'createCustomer',
        operation: 'erp.customers.createCustomer',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateCustomer',
        operation: 'erp.customers.updateCustomer',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteCustomer',
        operation: 'erp.customers.deleteCustomer',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'suppliers',
    tables: ['erp.suppliers'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listSuppliers',
        operation: 'erp.suppliers.listSuppliers',
        declaredSqlRoutine: null,
      },
      {
        name: 'getSupplier',
        operation: 'erp.suppliers.getSupplier',
        declaredSqlRoutine: null,
      },
      {
        name: 'createSupplier',
        operation: 'erp.suppliers.createSupplier',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateSupplier',
        operation: 'erp.suppliers.updateSupplier',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteSupplier',
        operation: 'erp.suppliers.deleteSupplier',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'warehouses',
    tables: ['erp.warehouses'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listWarehouses',
        operation: 'erp.warehouses.listWarehouses',
        declaredSqlRoutine: null,
      },
      {
        name: 'getWarehouse',
        operation: 'erp.warehouses.getWarehouse',
        declaredSqlRoutine: null,
      },
      {
        name: 'createWarehouse',
        operation: 'erp.warehouses.createWarehouse',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateWarehouse',
        operation: 'erp.warehouses.updateWarehouse',
        declaredSqlRoutine: null,
      },
      {
        name: 'deleteWarehouse',
        operation: 'erp.warehouses.deleteWarehouse',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'sales-orders',
    tables: ['erp.sales_orders'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listSalesOrders',
        operation: 'erp.sales-orders.listSalesOrders',
        declaredSqlRoutine: null,
      },
      {
        name: 'getSalesOrder',
        operation: 'erp.sales-orders.getSalesOrder',
        declaredSqlRoutine: 'erp.order_detail',
      },
      {
        name: 'getSalesOrderTotals',
        operation: 'erp.sales-orders.getSalesOrderTotals',
        declaredSqlRoutine: 'erp.order_totals',
      },
      {
        name: 'createSalesOrderDraft',
        operation: 'erp.sales-orders.createSalesOrderDraft',
        declaredSqlRoutine: 'erp.save_sales_order_draft',
      },
      {
        name: 'updateSalesOrderDraft',
        operation: 'erp.sales-orders.updateSalesOrderDraft',
        declaredSqlRoutine: 'erp.save_sales_order_draft',
      },
      {
        name: 'saveSalesOrderDraft',
        operation: 'erp.sales-orders.saveSalesOrderDraft',
        declaredSqlRoutine: 'erp.save_sales_order_draft',
      },
      {
        name: 'deleteSalesOrderDraft',
        operation: 'erp.sales-orders.deleteSalesOrderDraft',
        declaredSqlRoutine: null,
      },
      {
        name: 'confirmSalesOrder',
        operation: 'erp.sales-orders.confirmSalesOrder',
        declaredSqlRoutine: null,
      },
      {
        name: 'cancelSalesOrder',
        operation: 'erp.sales-orders.cancelSalesOrder',
        declaredSqlRoutine: null,
      },
      {
        name: 'fulfillSalesOrder',
        operation: 'erp.sales-orders.fulfillSalesOrder',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'sales-order-items',
    tables: ['erp.sales_order_items'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listSalesOrderItems',
        operation: 'erp.sales-order-items.listSalesOrderItems',
        declaredSqlRoutine: null,
      },
      {
        name: 'getSalesOrderItem',
        operation: 'erp.sales-order-items.getSalesOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'addSalesOrderItem',
        operation: 'erp.sales-order-items.addSalesOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'updateSalesOrderItem',
        operation: 'erp.sales-order-items.updateSalesOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'removeSalesOrderItem',
        operation: 'erp.sales-order-items.removeSalesOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'replaceSalesOrderItems',
        operation: 'erp.sales-order-items.replaceSalesOrderItems',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'purchase-orders',
    tables: ['erp.purchase_orders'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listPurchaseOrders',
        operation: 'erp.purchase-orders.listPurchaseOrders',
        declaredSqlRoutine: null,
      },
      {
        name: 'getPurchaseOrder',
        operation: 'erp.purchase-orders.getPurchaseOrder',
        declaredSqlRoutine: 'erp.order_detail',
      },
      {
        name: 'getPurchaseOrderTotals',
        operation: 'erp.purchase-orders.getPurchaseOrderTotals',
        declaredSqlRoutine: 'erp.order_totals',
      },
      {
        name: 'createPurchaseOrderDraft',
        operation: 'erp.purchase-orders.createPurchaseOrderDraft',
        declaredSqlRoutine: 'erp.save_purchase_order_draft',
      },
      {
        name: 'updatePurchaseOrderDraft',
        operation: 'erp.purchase-orders.updatePurchaseOrderDraft',
        declaredSqlRoutine: 'erp.save_purchase_order_draft',
      },
      {
        name: 'savePurchaseOrderDraft',
        operation: 'erp.purchase-orders.savePurchaseOrderDraft',
        declaredSqlRoutine: 'erp.save_purchase_order_draft',
      },
      {
        name: 'deletePurchaseOrderDraft',
        operation: 'erp.purchase-orders.deletePurchaseOrderDraft',
        declaredSqlRoutine: null,
      },
      {
        name: 'placePurchaseOrder',
        operation: 'erp.purchase-orders.placePurchaseOrder',
        declaredSqlRoutine: null,
      },
      {
        name: 'cancelPurchaseOrder',
        operation: 'erp.purchase-orders.cancelPurchaseOrder',
        declaredSqlRoutine: null,
      },
      {
        name: 'receivePurchaseOrder',
        operation: 'erp.purchase-orders.receivePurchaseOrder',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'purchase-order-items',
    tables: ['erp.purchase_order_items'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listPurchaseOrderItems',
        operation: 'erp.purchase-order-items.listPurchaseOrderItems',
        declaredSqlRoutine: null,
      },
      {
        name: 'getPurchaseOrderItem',
        operation: 'erp.purchase-order-items.getPurchaseOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'addPurchaseOrderItem',
        operation: 'erp.purchase-order-items.addPurchaseOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'updatePurchaseOrderItem',
        operation: 'erp.purchase-order-items.updatePurchaseOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'removePurchaseOrderItem',
        operation: 'erp.purchase-order-items.removePurchaseOrderItem',
        declaredSqlRoutine: null,
      },
      {
        name: 'replacePurchaseOrderItems',
        operation: 'erp.purchase-order-items.replacePurchaseOrderItems',
        declaredSqlRoutine: null,
      },
    ],
  },
  {
    task: 'payments',
    tables: ['erp.payments'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listPayments',
        operation: 'erp.payments.listPayments',
        declaredSqlRoutine: null,
      },
      {
        name: 'getPayment',
        operation: 'erp.payments.getPayment',
        declaredSqlRoutine: null,
      },
      {
        name: 'createPayment',
        operation: 'erp.payments.createPayment',
        declaredSqlRoutine: null,
      },
      {
        name: 'updatePayment',
        operation: 'erp.payments.updatePayment',
        declaredSqlRoutine: null,
      },
      {
        name: 'voidPayment',
        operation: 'erp.payments.voidPayment',
        declaredSqlRoutine: null,
      },
      {
        name: 'refundPayment',
        operation: 'erp.payments.refundPayment',
        declaredSqlRoutine: null,
      },
      {
        name: 'getSalesPaymentBalance',
        operation: 'erp.payments.getSalesPaymentBalance',
        declaredSqlRoutine: 'erp.sales_payment_balance',
      },
    ],
  },
  {
    task: 'stock',
    tables: ['erp.stock_movements'],
    implementation: 'prototype',
    operations: [
      {
        name: 'listStockMovements',
        operation: 'erp.stock.listStockMovements',
        declaredSqlRoutine: null,
      },
      {
        name: 'getStockMovement',
        operation: 'erp.stock.getStockMovement',
        declaredSqlRoutine: null,
      },
      {
        name: 'getStockBalance',
        operation: 'erp.stock.getStockBalance',
        declaredSqlRoutine: 'erp.stock_balance',
      },
      {
        name: 'adjustStock',
        operation: 'erp.stock.adjustStock',
        declaredSqlRoutine: 'erp.adjust_stock',
      },
      {
        name: 'transferStock',
        operation: 'erp.stock.transferStock',
        declaredSqlRoutine: 'erp.transfer_stock',
      },
    ],
  },
  {
    task: 'order-editing',
    tables: ['erp.sales_orders', 'erp.purchase_orders'],
    implementation: 'prototype',
    operations: [
      {
        name: 'openOrderEdit',
        operation: 'erp.order-editing.openOrderEdit',
        declaredSqlRoutine: 'erp.open_order_edit',
      },
      {
        name: 'renewOrderEdit',
        operation: 'erp.order-editing.renewOrderEdit',
        declaredSqlRoutine: 'erp.renew_order_edit',
      },
      {
        name: 'closeOrderEdit',
        operation: 'erp.order-editing.closeOrderEdit',
        declaredSqlRoutine: 'erp.close_order_edit',
      },
      {
        name: 'forceCloseOrderEdit',
        operation: 'erp.order-editing.forceCloseOrderEdit',
        declaredSqlRoutine: 'erp.force_close_order_edit',
      },
      {
        name: 'getOrderEditStatus',
        operation: 'erp.order-editing.getOrderEditStatus',
        declaredSqlRoutine: 'erp.order_edit_status',
      },
    ],
  },
] as const;

export type ErpTaskName = (typeof erpPrototypeCatalog)[number]['task'];
export type ErpOperationName = (typeof erpPrototypeCatalog)[number]['operations'][number]['name'];
