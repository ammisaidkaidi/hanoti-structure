/** sales-orders: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listSalesOrders<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.listSalesOrders');
}

/** Future SQL candidate: erp.order_detail; currently NOT called. */
export async function getSalesOrder<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.getSalesOrder');
}

/** Future SQL candidate: erp.order_totals; currently NOT called. */
export async function getSalesOrderTotals<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.getSalesOrderTotals');
}

/** Future SQL candidate: erp.save_sales_order_draft; currently NOT called. */
export async function createSalesOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.createSalesOrderDraft');
}

/** Future SQL candidate: erp.save_sales_order_draft; currently NOT called. */
export async function updateSalesOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.updateSalesOrderDraft');
}

/** Future SQL candidate: erp.save_sales_order_draft; currently NOT called. */
export async function saveSalesOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.saveSalesOrderDraft');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteSalesOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.deleteSalesOrderDraft');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function confirmSalesOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.confirmSalesOrder');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function cancelSalesOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.cancelSalesOrder');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function fulfillSalesOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-orders.fulfillSalesOrder');
}
