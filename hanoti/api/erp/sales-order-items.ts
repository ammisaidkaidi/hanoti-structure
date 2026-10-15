/** sales-order-items: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listSalesOrderItems<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.listSalesOrderItems');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getSalesOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.getSalesOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function addSalesOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.addSalesOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateSalesOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.updateSalesOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function removeSalesOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.removeSalesOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function replaceSalesOrderItems<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.sales-order-items.replaceSalesOrderItems');
}
