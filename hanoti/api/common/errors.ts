/** Internal stub error, not a ResultType definition or an HTTP response contract. */
export class ApiNotImplementedError extends Error {
  readonly code = 'NOT_IMPLEMENTED';
  readonly operation: string;

  constructor(operation: string) {
    super(`Not implemented: ${operation}`);
    this.name = 'ApiNotImplementedError';
    this.operation = operation;
  }
}
