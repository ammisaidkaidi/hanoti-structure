/** Server-only lightweight entry point: no TypeORM, entities, environment reads or I/O. */
export const databaseName = 'hanouti' as const;
export type ConnectionConsumer = 'typeorm' | 'libpq';

const tlsQueryKeys = new Set(['sslmode', 'sslrootcert', 'sslcert', 'sslkey']);

/**
 * Validate the shared database target and the consumer's permitted URL query keys.
 * The returned URL includes credentials: never log it. Values retain existing URL semantics;
 * TLS values/credential decoding and driver-specific configuration belong to each adapter.
 * Failures intentionally omit the input and parser cause; callers own their public messages.
 */
export function parseDatabaseUrl(value: string, consumer: ConnectionConsumer): URL {
  try {
    if (consumer !== 'typeorm' && consumer !== 'libpq') throw new Error();
    const url = new URL(value);
    if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname || url.hash)
      throw new Error();
    if (decodeURIComponent(url.pathname.slice(1)) !== databaseName) throw new Error();
    for (const key of url.searchParams.keys()) {
      if (!tlsQueryKeys.has(key) && !(consumer === 'libpq' && key === 'connect_timeout'))
        throw new Error();
    }
    return url;
  } catch {
    // Do not attach URL errors: they may contain passwords or certificate paths.
    throw new Error('Invalid PostgreSQL connection URL.');
  }
}
