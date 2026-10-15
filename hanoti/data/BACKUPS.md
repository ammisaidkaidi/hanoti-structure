# Daily whole-database backup — hanouti

## Schedule and destination

The standalone backup job now backs up **one PostgreSQL database, `hanouti`**, once daily at **02:00 UTC** using the supplied systemd timer. One custom-format dump includes `auth`, `erp`, `app`, `settings`, and other database objects included by pg_dump. No schema/table filter is used.

```text
{DATA_DIR}/migrations/hanouti/{year}/{month}/{day}-HH-mm-ss-SSS.dump

/data/migrations/hanouti/2026/10/14-02-00-00-123.dump
```

Timestamps are UTC. `DATA_DIR` defaults to the repository's data folder; the production service template sets `/data`. This replaces the earlier per-database archive layout. Existing old archives outside this unapplied workspace are not converted or deleted.

A single pg_dump provides a consistent database snapshot across all four schemas. It is a logical backup, not a physical cluster backup or point-in-time recovery solution; cluster roles/tablespaces are not included. Coordinate schema migrations and application recovery procedures separately.

## Safety behavior

- One `pg_dump --format=custom` call followed by `pg_restore --list`.
- One private `.dump.partial` file, created with mode 0600. New directories use 0700; existing permissions are not automatically changed.
- Nonempty, list-readable archives are fsynced and published using a same-directory hard link without overwriting an existing destination. The filesystem must support hard links.
- Lock at `{DATA_DIR}/migrations/.backup.lock` prevents overlaps on the same filesystem.
- Timeouts default to 30 minutes per tool; failures clean up owned partial output and release the lock. Process crashes may leave stale files/locks for operator review.
- Credentials go into child environment variables, not command-line URLs. Tool stderr is not forwarded to avoid accidental disclosure; privileged OS users can still inspect environments.
- JSON completion/failure events and nonzero failure exit codes support monitoring.
- No automated archive deletion, encryption, off-host replication, or alert delivery is configured.

`pg_restore --list` checks archive catalog readability, not a full restore. Perform actual restore drills. Keep backups private and out of Git; never treat `.dump` files or dated directories as executable migrations.

## Configuration

Install PostgreSQL client tools (`pg_dump`, `pg_restore`) and Node.js on the designated backup host. npm's `pg` driver does not install these executables. Prefer client tools matching the server major version; pg_dump must not be older than the server major version. Restore hosts need compatible pgvector support too.

Supply **`DATABASE_URL` targeting `/hanouti`**, using a backup role able to read all intended objects across all schemas, including row-security/large-object requirements where applicable. Do not reuse backup/provisioning credentials as application credentials. Old per-domain URL variables are no longer read.

Supported connection URL query parameters for this CLI: `sslmode`, `sslrootcert`, `sslcert`, `sslkey`, `connect_timeout`. URL-encode special characters. Use verified TLS for remote production servers. The ORM factory has a separate `connectTimeoutMs` option instead of the CLI's `connect_timeout` URL parameter.

The backup module shares target/query-key validation through the server-only `@app/data/connection-policy` entry point, without loading TypeORM or entity metadata. libpq environment conversion remains backup-specific. Unsupported inherited-object query keys (such as `toString`, `constructor`, `__proto__`, and `hasOwnProperty`) are now explicitly rejected; their accidental acceptance in the prior validator was a bug. Valid documented options and public error messages remain unchanged.

`BACKUP_TIMEOUT_MS` permits 1000–86400000 ms per executable; if increased, also increase the systemd service's total timeout (90 minutes by default for dump + verification).

## Manual commands (not run automatically)

Configure the backup variables in `packages/server/.env`, or provide a protected process environment. The CLI loads the file relative to its own package; environment values take precedence.

```sh
pnpm install
pnpm db:backup
# Or, after building:
pnpm build
pnpm db:backup:production
# Direct compiled entry point:
node packages/server/dist/scripts/backup.js
```

These commands would connect when run with valid credentials. No real backup has been run in this workspace; orchestration tests mock PostgreSQL tools.

## Enable on a Linux/systemd deployment host

The service/timer templates remain **uninstalled and disabled by default**:

- `ops/systemd/hanouti-backup.service`
- `ops/systemd/hanouti-backup.timer`
- `ops/backup.env.example`

Deploy/build at `/opt/hanoti`, or edit the service paths. Ensure `/usr/bin/node` and client-tool PATH are correct. Create a dedicated `hanouti` OS user/group, with read access to deployment files and write access only to needed backup locations. Then, if authorized:

```sh
sudo install -d -m 0700 -o hanouti -g hanouti /data/migrations
sudo install -d -m 0700 /etc/hanouti
sudo install -m 0600 ops/backup.env.example /etc/hanouti/backup.env
sudoedit /etc/hanouti/backup.env
sudo install -m 0644 ops/systemd/hanouti-backup.service /etc/systemd/system/
sudo install -m 0644 ops/systemd/hanouti-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start hanouti-backup.service
sudo journalctl -u hanouti-backup.service --no-pager -n 100
# Only after a real backup and restore drill succeed:
sudo systemctl enable --now hanouti-backup.timer
systemctl list-timers hanouti-backup.timer
```

Replace placeholder credentials before starting. If changing storage, update both DATA_DIR and the service's ReadWritePaths. ProtectHome blocks home-directory credential/certificate files; place required TLS materials at an explicitly readable protected location or adjust the sandbox deliberately.

`Persistent=true` permits one catch-up after downtime, not recreation of each missed daily archive. Install the timer on **one host only**. Non-systemd deployments may schedule the compiled command daily through their platform scheduler with the same protected environment/storage.

## Operations and restore testing

Monitor the service exit code, daily backup freshness, disk capacity, and any future replication. After an unclean shutdown, inspect `.backup.lock/owner.json` and confirm no backup process is running before deleting a stale lock or partial file. Never expire locks blindly.

Agree on retention and encrypted off-host storage before unattended production use. A dump contains private auth, fiscal, customer, and settings data; the single archive now includes them together. Do not expose it to the browser or application download endpoints.

For an isolated restore drill, an operator should first create a **new empty disposable database**, such as `hanouti_restore_check`. Restore with compatible extensions available and appropriate credentials:

```sh
# Password supplied securely, for example via protected .pgpass. No --clean flag.
PGHOST=localhost PGUSER=restore_operator PGDATABASE=hanouti_restore_check \
  pg_restore --dbname=hanouti_restore_check --exit-on-error --no-owner --no-privileges \
  /data/migrations/hanouti/2026/10/14-02-00-00-123.dump
```

Validate all four schemas, row counts, cross-schema foreign keys, settings, and application invariants. Skipping ownership/privileges is for the disposable drill; separately document production ownership/grants. Prefer a complete restore because cross-schema foreign keys mean isolated schema restores may have dependencies. Nothing here restores into or modifies a live database automatically.
