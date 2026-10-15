import 'reflect-metadata';
import type { TlsOptions } from 'node:tls';
import { DataSource, type DataSourceOptions } from 'typeorm';
import { allEntities } from './entity-registry.js';
import { databaseName, parseDatabaseUrl } from './connection-policy.js';

export interface DatabaseConnectionOptions {
  url: string;
  ssl?: boolean | TlsOptions;
  poolSize?: number;
  connectTimeoutMs?: number;
}
export type DatabaseConfiguration = DatabaseConnectionOptions;

function assertUrl(value: string): URL {
  try {
    return parseDatabaseUrl(value, 'typeorm');
  } catch {
    // URL parser errors can include secrets; intentionally do not attach their cause.
    throw new Error(
      'Invalid DATABASE_URL: expected a PostgreSQL URL targeting hanouti, with only documented TLS query options.',
    );
  }
}

function positiveInteger(value: number, label: string, max: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new Error(`${label} must be an integer between 1 and ${max}.`);
  }
  return value;
}

/** Read explicitly; no dotenv loading, environment reads, or connections happen on import. */
export function readDatabaseConfiguration(env: NodeJS.ProcessEnv): DatabaseConfiguration {
  const url = env.DATABASE_URL ?? '';
  assertUrl(url);
  return { url };
}

/** Construct metadata/driver configuration only. Call initialize explicitly to connect. */
export function createDataSource(options: DatabaseConnectionOptions): DataSource {
  const url = assertUrl(options.url);
  if (
    options.ssl !== undefined &&
    [...url.searchParams.keys()].some((key) => key.startsWith('ssl'))
  ) {
    throw new Error(
      'Choose either URL TLS parameters or the ssl option, not both; node-postgres may otherwise replace TLS configuration.',
    );
  }
  const configuration: DataSourceOptions = {
    type: 'postgres',
    url: options.url,
    // Every business entity declares its explicit schema. public hosts pgvector only.
    entities: [...allEntities],
    synchronize: false,
    migrationsRun: false,
    migrations: [],
    dropSchema: false,
    installExtensions: false,
    uuidExtension: 'pgcrypto',
    logging: false,
    logNotifications: false,
    parseInt8: false,
    invalidWhereValuesBehavior: { null: 'throw', undefined: 'throw' },
    poolSize: positiveInteger(options.poolSize ?? 10, 'poolSize', 100),
    connectTimeoutMS: positiveInteger(
      options.connectTimeoutMs ?? 10000,
      'connectTimeoutMs',
      300000,
    ),
    applicationName: databaseName,
    ...(options.ssl === undefined ? {} : { ssl: options.ssl }),
  };
  return new DataSource(configuration);
}
