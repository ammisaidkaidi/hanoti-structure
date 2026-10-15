/** suppliers: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listSuppliers<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.suppliers.listSuppliers');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getSupplier<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.suppliers.getSupplier');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createSupplier<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.suppliers.createSupplier');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateSupplier<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.suppliers.updateSupplier');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteSupplier<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.suppliers.deleteSupplier');
}
