/** brands: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listBrands<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.brands.listBrands');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getBrand<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.brands.getBrand');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createBrand<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.brands.createBrand');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateBrand<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.brands.updateBrand');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteBrand<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.brands.deleteBrand');
}
