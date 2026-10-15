/** products: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listProducts<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.listProducts');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getProduct<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.getProduct');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createProduct<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.createProduct');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateProduct<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.updateProduct');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteProduct<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.products.deleteProduct');
}
