// Server-only entry point. Do not re-export this package from @app/common/browser.
import 'reflect-metadata';
export { Auth, Erp, App, Settings } from './entities/index.js';
export {
  authEntities,
  erpEntities,
  appEntities,
  settingsEntities,
  entitiesBySchema,
  allEntities,
} from './entity-registry.js';
export { createDataSource, readDatabaseConfiguration } from './data-sources.js';
export type { DatabaseConnectionOptions, DatabaseConfiguration } from './data-sources.js';
export { databaseName, schemaNames } from './types.js';
export type { SchemaName, JsonValue, JsonObject, JsonPrimitive } from './types.js';
export * from './helpers/index.js';
