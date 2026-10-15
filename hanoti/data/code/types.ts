/** Values representable by PostgreSQL JSONB; big numeric values should be encoded as strings. */
export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };
export { databaseName } from './connection-policy.js';
export const schemaNames = ['auth', 'erp', 'app', 'settings'] as const;
export type SchemaName = (typeof schemaNames)[number];
