/** purchase-order-items: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listPurchaseOrderItems<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.listPurchaseOrderItems');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getPurchaseOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.getPurchaseOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function addPurchaseOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.addPurchaseOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updatePurchaseOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.updatePurchaseOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function removePurchaseOrderItem<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.removePurchaseOrderItem');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function replacePurchaseOrderItems<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-order-items.replacePurchaseOrderItems');
}
