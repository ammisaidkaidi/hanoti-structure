# Historical architecture baseline

This folder contains the two original reference snapshots moved from `/home/user/architecture-baseline/`:

- `backup.ts`: an earlier version of the backup implementation.
- `data-sources.ts`: an earlier version of the TypeORM DataSource factory.

Their contents have been preserved. These are **historical comparison material, not active source files or current implementation guidance**. Their original imports may not resolve here, and some rules or interfaces have since changed.

Current maintained implementations are:

- [`packages/server/src/backup.ts`](../../../packages/server/src/backup.ts)
- [`data/code/data-sources.ts`](../../../data/code/data-sources.ts)
- [`data/code/connection-policy.ts`](../../../data/code/connection-policy.ts)

Do not import, execute, regenerate or copy these snapshots over the current implementations. Production TypeScript projects do not include this directory; linting and formatting exclude it to preserve the comparison baseline.

No tests, builds, database connections or SQL execution were performed when relocating this folder.
