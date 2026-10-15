import type { DataSource } from 'typeorm';

// Serialize lifecycle transitions for each source, including overlapping start/stop calls.
const pending = new WeakMap<DataSource, Promise<void>>();
function enqueue(source: DataSource, operation: () => Promise<void>): Promise<void> {
  const previous = pending.get(source) ?? Promise.resolve();
  const task = previous.catch(() => undefined).then(operation);
  pending.set(source, task);
  // Register both handlers to avoid an unhandled rejection from a discarded finally promise.
  const clear = () => {
    if (pending.get(source) === task) pending.delete(source);
  };
  void task.then(clear, clear);
  return task;
}

/** Explicit opt-in; importing classes or creating a DataSource does not connect. */
export function initializeDataSource(source: DataSource): Promise<void> {
  return enqueue(source, async () => {
    if (!source.isInitialized) await source.initialize();
  });
}

/** Safe to call after an unsuccessful start; waits for pending initialization. */
export function destroyDataSource(source: DataSource): Promise<void> {
  return enqueue(source, async () => {
    if (source.isInitialized) await source.destroy();
  });
}
