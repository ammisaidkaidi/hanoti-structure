# Hanouti sibling test workspace

This folder is **beside `hanoti/`**, not inside it:

```text
workspace/
├── .test/                         This folder: @app/tests
└── hanoti/                       Application and pnpm workspace root
    └── docs/architecture/baseline/ Historical reference snapshots
```

Keep these two folder names and their relative positions when copying or extracting the project. Tests import production source through `../hanoti/`-relative paths. `hanoti/pnpm-workspace.yaml` explicitly includes `../.test`; the shared dependency lockfile remains `hanoti/pnpm-lock.yaml`.

**No tests, builds, dependency installation or validation checks were run for this relocation.** Logs contain historical output and are not proof that the new layout or later changes pass checks.

## Contents

```text
.test/
├── api/                          API prototypes tests and test tsconfig
├── data/
│   ├── *.test.ts
│   ├── fixtures/                 Schema/routine manifests and import-blocking fixture
│   ├── sql/                      Unexecuted PostgreSQL assertion scripts
│   ├── scripts/validate_routines.py
│   └── tsconfig.test.json
├── packages/
│   ├── common/                   Shared-library tests and test tsconfig
│   └── server/                   Server/backup tests and test tsconfig
├── archive/                      Historical helpers/fragments; do not run
├── logs/                         Historical local output; git-ignored
├── artifacts/                    Downloadable ZIP; excluded from its own contents
├── .tmp/                         Backup-test temporary files, created on demand
├── .cache/                       Vitest cache, created on demand
├── coverage/                     Optional coverage output, created on demand
├── eslint.config.js              Reuses the application's lint configuration
├── vitest.config.ts              Explicit test root and source access paths
├── .prettierignore
├── .gitignore
├── package.json
└── README.md
```

Third-party skill documentation and dependency files have not been moved. Archived helpers and logs retain their original contents and historical paths.

## Commands for later use

Always manage installation from **`hanoti/`**, where the shared pnpm workspace and lockfile live. Do not run an independent install in `.test/`.

```sh
cd hanoti
pnpm install --frozen-lockfile
pnpm test
```

The root `test` script builds the shared/data prerequisites and invokes the central suite once. Vitest explicitly uses this hidden folder as its root and allows imports from the sibling application. Existing package test shortcuts delegate here.

After building prerequisites, individual suites and test typechecks are available from `hanoti/`:

```sh
pnpm --filter @app/tests --fail-if-no-match test:api
pnpm --filter @app/tests --fail-if-no-match test:data
pnpm --filter @app/tests --fail-if-no-match test:common
pnpm --filter @app/tests --fail-if-no-match test:server
pnpm --filter @app/tests --fail-if-no-match typecheck
```

Root linting and formatting explicitly include this external test workspace; they no longer rely on traversing a child `.test` directory. The test formatter uses `hanoti/.prettierrc.json`. Archived helpers, logs, artifacts, cache, temporary files and coverage output are excluded from formatting/linting.

Use the root `pnpm test`, not `pnpm -r test`, to avoid running delegated suites twice. The `--fail-if-no-match` flags prevent a missing sibling test package from silently skipping test commands.

## Source control and CI

The `hanoti-structure` repository tracks `hanoti/` and `.test/` as siblings. Its root `.github/workflows/ci.yml` checks out both from the same commit, so the test source cannot silently drift to a different repository revision.

CI runs from `hanoti/` and keeps an explicit sibling-test prerequisite. No separate test download is needed. Keep both folders in every environment that runs the full checks.

## SQL declarations and generation

SQL assertions under `data/sql/` remain **unexecuted** and are not run by `pnpm test` or `pnpm check`.

From `hanoti/`, the optional grammar-only validator is:

```sh
# Requires Python 3.10+ and pglast==8.6. Parses only; never executes SQL.
python ../.test/data/scripts/validate_routines.py
```

Production declarations remain under `hanoti/data/migrations/hanouti/` and `hanoti/data/seeds/`. The maintained generator remains `hanoti/data/scripts/generate_entities.py` and now writes the schema manifest to sibling `.test/data/fixtures/schema-manifest.json`. Manifest SQL paths remain relative to the application's `data/` directory.

## Logs and deliverable

Capture future output under this folder, for example from `hanoti/`:

```sh
mkdir -p ../.test/logs
pnpm test > ../.test/logs/test.log 2>&1
```

These are instructions only; they were not executed during relocation.

The historical local bundle `artifacts/hanouti-starter.zip` predates the folder rename and repository setup. It remains excluded from Git, along with logs, generated outputs and dependencies. Use the repository for the current paired layout; do not assume that ZIP contains the latest source.
