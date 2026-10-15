/** customers: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listCustomers<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.customers.listCustomers');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getCustomer<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.customers.getCustomer');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createCustomer<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.customers.createCustomer');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updateCustomer<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.customers.updateCustomer');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function deleteCustomer<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.customers.deleteCustomer');
}
