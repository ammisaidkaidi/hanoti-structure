/** categories: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listCategories<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.categories.listCategories');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getCategory<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.categories.getCategory');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createCategory<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.categories.createCategory');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateCategory<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.categories.updateCategory');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteCategory<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.categories.deleteCategory');
}
