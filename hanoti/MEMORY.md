# Project Memory — Hanouti

Last updated: 2026-10-15 | Session 1 (continued) | Branch: main; repository root is the parent of hanoti/ and .test/
Memory health: 9/10 — fresh context and referenced paths; not a software-validation score.

## Project Overview

PnPM TypeScript monorepo: Vue 3/Tailwind browser, Express server, shared libraries, TypeORM data package and unwired ERP API prototypes; PostgreSQL declarations remain unapplied.

## Where We Left Off

- **Current task:** publish the approved private paired-source repository `ammisaidkaidi/hanoti-structure`. This record describes source state; verify remote push/CI outcomes separately.
- **Latest application work:** renamed application folder to `hanoti/`; corrected active sibling-test paths and workspace links; moved CI to the parent repository root. Database/package identities remain `hanouti`.
- **Next immediate step:** when API work resumes, read `api/common/result.ts` and agree `ResultType` with the user before implementing response handling. Do not invent its shape or wire endpoints yet.
- **Open questions:** `ResultType`, session/authentication contract and concrete operation payload/output contracts remain undefined.
- **Validation boundary:** later `db`-argument and folder/layout changes were not tested; no PostgreSQL connection or SQL execution has occurred.

## Completed

- Declared one `hanouti` database with `auth`, `erp`, `app`, `settings`; 30 entity/table mappings and 38 SQL functions, including 15 public entry points (13 ERP).
- Declared full authorization/settings resolution and operational ERP routines, without deployment or lifecycle wiring.
- Replaced the separate editing-lease table with header locks; added universal timestamps/frozen flags and table-level guards.
- Added product `fullName` composition and sales/purchase item snapshots; retained policy AND permission for sale-price overrides.
- Added 79 async ERP prototypes across 13 task files; every operation rejects with `ApiNotImplementedError`.
- Added required caller-supplied `db` to shared API arguments; no automatic DataSource creation/initialization.
- Consolidated tests, fixtures, configs, historical scripts/logs and ZIP under sibling `../.test/`; preserved architecture baseline as reference only.
- Loaded Memory Bank through the requested `npx skills use` command; user initially deferred files, then explicitly requested this initialization.

## Active Work

- [x] Initialize `MEMORY.md`; no global memory or automatic session hook added.
- [ ] Discuss `ResultType` before further API implementation; user has not requested an implementation yet.
- [ ] Only if authorized locally: install refreshed links, rebuild stale data/API output and validate the changed layout. Generated output is excluded from Git; CI is configured to install/check/build after pushes.

## Blockers

- ERP prototypes have no operational HTTP routes, authentication, response semantics or database calls; a stub is not a working API.
- CI now checks out both siblings from one commit; no separate test source is needed. This fixes the missing provisioning configuration, but does not establish a passing CI result.
- The repository history starts with this publication. Earlier changes have no Git history.

## Key Decisions

| Date       | Decision                                                                 | Reason / boundary                                                                                                       |
| ---------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| 2026-10-15 | Keep pnpm workspaces: `packages/*`, `data`, `api`, `../.test`            | App workspace/lockfile stay in `hanoti/`; preserve sibling layout.                                                      |
| 2026-10-15 | Browser/server use `@app/common`; data stays server-only                 | Keep `pg` in server even though data also uses it; no browser data exports.                                             |
| 2026-10-15 | TypeORM under `data/code/`; one database/four schemas                    | Reversed the former separate-database design; no automatic connections, schema sync or migrations.                      |
| 2026-10-15 | SQL/provisioning/catalog scripts remain explicit declarations            | No SQL execution, API lifecycle wiring or automatic business-permission assignments.                                    |
| 2026-10-15 | Full scoped settings resolver; auth owns authorization                   | Explicitly overridable scoped settings may beat globals; authorization denials and integrity constraints still win.     |
| 2026-10-15 | Negative document quantities and negative stock are independent policies | Existing positive order-line constraints remain; no invoice/return model silently added.                                |
| 2026-10-15 | Approval-required stock operations are blocked                           | No implicit/self approval or invented approval workflow.                                                                |
| 2026-10-15 | Exclusive five-minute renewable header locks                             | `locked_by`, `locked_at`, `lock_version`; supervisors force-close then explicitly reopen, never bypass ownership.       |
| 2026-10-15 | Every table has `updated_at` and `frozen`                                | Frozen means read-only, not inactive; only database administrators manage it; frozen orders protect their items.        |
| 2026-10-15 | Preserve optimistic business timestamps                                  | Item changes advance the parent; heartbeats do not. Keep exact PostgreSQL timestamp strings and bigint version strings. |
| 2026-10-15 | Sale-price override needs policy AND permission                          | Effective `pricing.allow_manual_price` AND applicable `pricing.override`; changes line price, not catalog price.        |
| 2026-10-15 | Product/item `fullName` maps to SQL `full_name TEXT`                     | Product-row trigger composes components; newly created items copy the stored value as a snapshot.                       |
| 2026-10-15 | All current ERP areas get async `.ts` stubs                              | No invented invoice model, working posting/refund workflows or application freeze endpoints.                            |
| 2026-10-15 | `ApiFunctionArgs<P>` has seven required fields                           | `req`, `res`, `session`, `db`, `data`, `params`, `result`; `ApiDatabase` derives from the existing TypeORM factory.     |
| 2026-10-15 | `ResultType` and `ApiSession` stay `unknown`                             | User explicitly deferred result design; no fabricated authentication or response envelope.                              |
| 2026-10-15 | Historical material is isolated, not rerun                               | Old helpers in `../.test/archive/`; baseline snapshots in `docs/architecture/baseline/`; reports in `../.reports/`.     |

## Key Files

Paths below are relative to `hanoti/`; `../.test` and `../.reports` are siblings.

| Path                                                                                                | Purpose                                                                                |
| --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `api/common/types.ts`, `api/common/result.ts`                                                       | Generic async argument contract, caller-supplied DataSource and unresolved result type |
| `api/erp/catalog.ts`, `api/README.md`                                                               | Complete prototype inventory and implementation boundaries                             |
| `data/ERP_ROUTINES.md`                                                                              | SQL entry points, trust model, settings and operational scope                          |
| `data/EDIT_LOCKS.md`                                                                                | Lock/frozen guards, timestamps, admin-only metadata and concurrency caveats            |
| `data/FULL_NAMES.md`                                                                                | Product composition, item snapshots and replacement-save behavior                      |
| `data/SETTINGS_SCHEMA.md`, `data/ALGERIAN_PARTIES.md`                                               | Settings/authorization contract; Algerian party fields and source-backed constraints   |
| `data/TYPEORM.md`, `data/code/data-sources.ts`                                                      | Server-only ORM mappings and explicit connection factory                               |
| `data/migrations/hanouti/009_erp_routines.sql`                                                      | Draft writers, reads, stock operations and audit helpers                               |
| `data/migrations/hanouti/010_row_guards.sql`, `data/migrations/hanouti/011_order_edit_routines.sql` | Universal guards, product-name trigger, header lock functions and trigger attachment   |
| `../.test/README.md`, `../.test/data/fixtures/`                                                     | External test layout; schema/routine manifests                                         |
| `docs/architecture/baseline/README.md`                                                              | Historical snapshots, excluded from active builds/lint/format                          |
| `../.github/workflows/ci.yml`                                                                       | Repository-root workflow checks out both siblings; pnpm runs in hanoti/                |

## Architecture Notes

- Protected SQL functions derive record ownership and evaluate permissions; trusted backend supplies authenticated actor IDs. Transaction-local actor settings are context, not authentication.
- Backend remains function-only. Table guards protect locks/frozen rows but do not replace all validation in the public business functions.
- `lock_version` is a fencing counter, not a secret or proof of a physical browser tab; never silently substitute a fresh client version on retry.
- Draft saves replace the entire item list. Recreated lines capture fresh full-name snapshots; frozen lines prevent replacement.
- Product full name order: ABR, Name, Attr, Material, Dims, Color, Brand, /Serie, MadeIn, Quality, Ref. Attributes/dimensions remain TEXT.
- Product-row edits recompose full names; renaming a shared brand alone waits until the next product edit. Stored existing item rows do not auto-refresh.
- Customer/product embeddings are 4096 dimensions. Preserve Algerian party/job fields and privacy constraints; do not infer unverified identifier rules.
- Shared libraries include automategraph, smart-hybrid-search and http-negotiation-protocol; retain browser/server export boundaries and Tailwind/PostCSS configuration.
- Backup layout remains `/data/migrations/hanouti/{year}/{month}/{day}-time.{ext}`; no real backup has been run.

## Known Issues / Validation State

- Historical milestone: 226 tests plus build/lint/typechecks passed before the `db` argument and later test/folder relocations. This does NOT validate the current tree.
- SQL parsing/static tests never established live catalog semantics, ACL behavior, concurrency or performance. PostgreSQL fixtures remain unexecuted and separately gated.
- Workspace/link/CI changes after moving `.test` are unvalidated; install only when requested, from `hanoti/`, keeping both sibling folders.
- Archived one-off scripts contain obsolete designs and paths; never rerun them to regenerate current files.
- `.reports` was renamed only; its historical generator was not retargeted. Review paths before any future use.
- The local historical ZIP predates memory initialization, the rename and repository setup; it is excluded from Git and has not been rebuilt. Local reports/logs are also excluded.

## Session Log

| Session | Date       | Summary                                                                                                                                                                               |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1       | 2026-10-15 | Initialized memory, reviewed source read-only, renamed folder, then prepared private paired Git repository and root CI. No local tests/builds/install/SQL executed for these changes. |

## User Preferences

- Ask about consequential missing decisions; do not invent behavior. Relevant custom answers to multiple-choice questions are valid.
- If a multiple-choice answer is irrelevant, call it out and repeat the exact same question rather than proceeding.
- Honor “no check” / “no execution” requests: no automatic tests, builds, installs or SQL. A later explicit command authorizes that command, not unrelated checks.
- Keep project source clean; tests/logs/support artifacts belong beside it in `.test`, reports in `.reports`, historical architecture material under project documentation.

## External Context

- Repository: `https://github.com/ammisaidkaidi/hanoti-structure` (private); complete paired-source layout approved by user.
- Memory Bank skill source: `https://github.com/nagendhra-web/memory-bank`; full CLI output retained locally at `../.test/logs/memory-bank-skill-output.txt` (not committed).
- Supporting skill files were temporary; reload the skill if needed rather than assuming that temporary directory survives.
- Never store credentials in project memory or commits. No global memory or automatic-loading hook created.
