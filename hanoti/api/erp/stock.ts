/** stock: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listStockMovements<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.stock.listStockMovements');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getStockMovement<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.stock.getStockMovement');
}

/** Future SQL candidate: erp.stock_balance; currently NOT called. */
export async function getStockBalance<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.stock.getStockBalance');
}

/** Future SQL candidate: erp.adjust_stock; currently NOT called. */
export async function adjustStock<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.stock.adjustStock');
}

/** Future SQL candidate: erp.transfer_stock; currently NOT called. */
export async function transferStock<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.stock.transferStock');
}
