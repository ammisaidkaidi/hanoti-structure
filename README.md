# hanoti-structure

Private source repository containing the Hanoti application and its sibling test workspace.

```text
hanoti-structure/
├── .github/workflows/ci.yml       CI for the complete paired checkout
├── .test/                        Tests, fixtures and historical support sources
│   └── archive/                  Reference only; do not execute archived builders
└── hanoti/                       Application and pnpm workspace root
    ├── api/                      ERP async prototypes (not implemented)
    ├── data/                     TypeORM mappings and unapplied SQL declarations
    ├── packages/                 Browser, server and shared code
    ├── docs/architecture/baseline/ Historical reference snapshots
    ├── MEMORY.md                 Project decisions and continuation context
    ├── pnpm-workspace.yaml
    └── pnpm-lock.yaml
```

## Working with the source

Keep `hanoti/` and `.test/` together. The repository root is their parent, while the pnpm workspace root is `hanoti/`.

Commands for an authorized developer to run:

```sh
git clone https://github.com/ammisaidkaidi/hanoti-structure.git
cd hanoti-structure/hanoti
pnpm install --frozen-lockfile
pnpm build
```

`pnpm build` builds common/data before the API and the applications, regenerating the API declarations with the required caller-supplied `db` property. Generated `dist/` files are deliberately not committed; do not reuse stale local output.

For development and verification, see [the application README](hanoti/README.md) and [the test workspace README](.test/README.md). Run pnpm commands from `hanoti/`, not from `.test/` or the repository root.

## Names and safety boundaries

- The application folder is **hanoti**. The existing package/service identities and PostgreSQL database name **hanouti** are retained. In particular, SQL remains under `hanoti/data/migrations/hanouti/`.
- SQL is unapplied. No database initialization, migrations, SQL assertions or backup job is enabled automatically.
- All ERP API operations remain rejecting prototypes. Result/session contracts and operational endpoints are not implemented.
- No local tests, dependency installation or builds were performed during repository preparation. Historical passing results do not validate this revision.
- The GitHub Actions workflow checks out both siblings from the same commit, installs dependencies and runs `pnpm check`. It does not execute the PostgreSQL integration scripts. Consult Actions for its actual outcome; no passing status is assumed here.
- Secrets, dependency directories, compiled output, local reports/logs and ZIP artifacts are excluded. Never commit tokens or populated environment files; use environment variables or protected secret storage.

Project context: [hanoti/MEMORY.md](hanoti/MEMORY.md).
