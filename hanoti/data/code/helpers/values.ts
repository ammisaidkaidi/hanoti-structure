export interface Pagination {
  page: number;
  pageSize: number;
  skip: number;
  take: number;
}

/** Bounded offset pagination. Callers must also supply a stable order and authorization filter. */
export function getPagination(page = 1, pageSize = 25): Pagination {
  if (!Number.isSafeInteger(page) || page < 1)
    throw new Error('page must be a positive safe integer.');
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 100)
    throw new Error('pageSize must be an integer between 1 and 100.');
  const skip = (page - 1) * pageSize;
  if (!Number.isSafeInteger(skip))
    throw new Error('Pagination offset exceeds the safe integer range.');
  return { page, pageSize, skip, take: pageSize };
}

/** Validate before writing a product/customer embedding; does not generate embeddings. */
export function assertVector4096(value: unknown): asserts value is number[] {
  if (!Array.isArray(value) || value.length !== 4096)
    throw new Error('Embedding must contain exactly 4096 finite numbers.');
  // Array.every skips sparse holes; a counted loop deliberately rejects them.
  for (let index = 0; index < value.length; index += 1) {
    const entry: unknown = value[index];
    if (
      typeof entry !== 'number' ||
      !Number.isFinite(entry) ||
      !Number.isFinite(Math.fround(entry))
    ) {
      throw new Error('Embedding entries must be finite float32-compatible numbers.');
    }
  }
}

/** Static TypeORM INSERT/UPDATE expression for JSON null, distinct from SQL NULL. */
export function jsonbNull(): string {
  return "'null'::jsonb";
}
