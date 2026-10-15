/** payments: async prototypes only. No routes, SQL, authorization or business logic are installed. */
import type { ApiFunctionArgs } from '../common/types.js';
import { notImplemented } from '../common/not-implemented.js';

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function listPayments<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.listPayments');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function getPayment<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.getPayment');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function createPayment<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.createPayment');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function updatePayment<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.updatePayment');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function voidPayment<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.voidPayment');
}

/** No dedicated public SQL operation is currently declared; implementation requires review. */
export async function refundPayment<P = unknown, T = unknown>(arg: ApiFunctionArgs<P>): Promise<T> {
  void arg;
  return notImplemented('erp.payments.refundPayment');
}

/** Future SQL candidate: erp.sales_payment_balance; currently NOT called. */
export async function getSalesPaymentBalance<P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
): Promise<T> {
  void arg;
  return notImplemented('erp.payments.getSalesPaymentBalance');
}
