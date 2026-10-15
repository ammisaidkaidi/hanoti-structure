/** order-editing: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** Future SQL candidate: erp.open_order_edit; currently NOT called. */
export async function openOrderEdit<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.order-editing.openOrderEdit');
}

/** Future SQL candidate: erp.renew_order_edit; currently NOT called. */
export async function renewOrderEdit<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.order-editing.renewOrderEdit');
}

/** Future SQL candidate: erp.close_order_edit; currently NOT called. */
export async function closeOrderEdit<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.order-editing.closeOrderEdit');
}

/** Future SQL candidate: erp.force_close_order_edit; currently NOT called. */
export async function forceCloseOrderEdit<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.order-editing.forceCloseOrderEdit');
}

/** Future SQL candidate: erp.order_edit_status; currently NOT called. */
export async function getOrderEditStatus<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.order-editing.getOrderEditStatus');
}
