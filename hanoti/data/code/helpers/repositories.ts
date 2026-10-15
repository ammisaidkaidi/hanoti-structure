import {
  DataSource,
  type EntityManager,
  type EntityTarget,
  type ObjectLiteral,
  type Repository,
} from 'typeorm';

/** Use the transaction's EntityManager when inside withTransaction; no global repositories. */
export function getRepository<T extends ObjectLiteral>(
  source: DataSource | EntityManager,
  entity: EntityTarget<T>,
): Repository<T> {
  const manager = source instanceof DataSource ? source.manager : source;
  if (!manager.dataSource.isInitialized)
    throw new Error('Initialize the database explicitly before requesting a repository.');
  if (!manager.dataSource.hasMetadata(entity))
    throw new Error('The entity does not belong to this database connection.');
  if (manager.queryRunner?.isReleased)
    throw new Error('This transaction manager has already been released.');
  return manager.getRepository(entity);
}

export type TransactionIsolation = 'READ COMMITTED' | 'REPEATABLE READ' | 'SERIALIZABLE';

/** One hanouti transaction may span auth, erp, app and settings through this same manager. */
export async function withTransaction<T>(
  source: DataSource,
  operation: (manager: EntityManager) => Promise<T>,
  isolation: TransactionIsolation = 'READ COMMITTED',
): Promise<T> {
  if (!source.isInitialized)
    throw new Error('Initialize the database explicitly before starting a transaction.');
  if (!['READ COMMITTED', 'REPEATABLE READ', 'SERIALIZABLE'].includes(isolation))
    throw new Error('Unsupported PostgreSQL transaction isolation.');
  return source.transaction(isolation, operation);
}
