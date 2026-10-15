import { ApiNotImplementedError } from './errors.js';

/** Always throws; never returns fabricated data, sends a response or logs request contents. */
export function notImplemented(operation: string): never {
  throw new ApiNotImplementedError(operation);
}
