/** purchase-orders: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listPurchaseOrders<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.listPurchaseOrders');
}

/** Future SQL candidate: erp.order_detail; currently NOT called. */
export async function getPurchaseOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.getPurchaseOrder');
}

/** Future SQL candidate: erp.order_totals; currently NOT called. */
export async function getPurchaseOrderTotals<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.getPurchaseOrderTotals');
}

/** Future SQL candidate: erp.save_purchase_order_draft; currently NOT called. */
export async function createPurchaseOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.createPurchaseOrderDraft');
}

/** Future SQL candidate: erp.save_purchase_order_draft; currently NOT called. */
export async function updatePurchaseOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.updatePurchaseOrderDraft');
}

/** Future SQL candidate: erp.save_purchase_order_draft; currently NOT called. */
export async function savePurchaseOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.savePurchaseOrderDraft');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deletePurchaseOrderDraft<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.deletePurchaseOrderDraft');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function placePurchaseOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.placePurchaseOrder');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function cancelPurchaseOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.cancelPurchaseOrder');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function receivePurchaseOrder<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.purchase-orders.receivePurchaseOrder');
}
