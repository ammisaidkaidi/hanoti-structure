/** warehouses: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listWarehouses<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.warehouses.listWarehouses');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getWarehouse<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.warehouses.getWarehouse');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createWarehouse<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.warehouses.createWarehouse');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateWarehouse<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.warehouses.updateWarehouse');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteWarehouse<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.warehouses.deleteWarehouse');
}
