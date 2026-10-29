# The database on Forge

## Any app

- One database per app on the shared `apps-postgres`. An Admin creates it; the credentials go to a
  0600 file on the host, never printed *(inferred)*.
- **It is not reachable from a laptop or browser**: internal app network only. A Forge Admin can
  grant read-only access through an SSH tunnel.
- **Owner login cap: 40 connections.** Forge asks for **20 or fewer per app**. Size your pool to it.
- Run migrations **as the owner login**, with no `GRANT`, `REVOKE`, `CREATE ROLE` or
  `CREATE EXTENSION`. A local superuser hides permission failures the owner login would hit.
- Nightly host backups: a `pg_dumpall` plus one `pg_dump -Fc` per app *(inferred)*. That is the real
  backup.
- Moving an existing database: a Forge Admin runs `pg_dump` on the source and `pg_restore` into
  `apps-postgres` on the host.

## Lessons for any app

- **URL from one setting, with Forge's fallback.** Read `<APP>_DATABASE_URL` first, then Forge's
  `DATABASE_URL`. Rewrite a leading `postgres://` or `postgresql://` to the driver's prefix (e.g.
  `postgresql+psycopg://`). **No default**: a missing value stops startup naming the setting. The
  URL is a secret and is **never logged**.
- **Migrate at every container start** (e.g. `alembic upgrade head && exec <server>` in the Forge
  Dockerfile). It is the **only** migration path, so an empty database gets the full schema on first
  boot.
- **Dev fixtures never go in the image**, so they cannot reach Forge.
- **One migration chain.** `main`'s head decides what Forge boots. Two revisions with the same
  parent give multiple heads and **the API will not start** on the next deploy. Check
  `main`'s migrations folder before adding one.
- **Pool vs budget.** Library defaults (e.g. 20 + 30 per replica) exceed Forge's 20. Example that
  fits: pool 10 + overflow 10, timeout 10 s (20 max per replica). A full pool should answer
  **`503`** (e.g. `service_busy`) after the timeout, not hang. Re-check before adding a worker or
  replica.
- **`statement_timeout` is a trade-off.** Leaving it unset is deliberate if backup, restore or a
  bulk sync is long; if you set one, exempt those paths.
- **Go-live SQL sanity checks:** duplicate emails on the people table (`GROUP BY lower(btrim(email))
  HAVING count(*) > 1`, expect none) and `SHOW timezone;` (expect UTC). Add the app's own in
  `release-checklists.md` / `app.md`.
- **Data:** if rows come from a reference sync rather than a dump, there is nothing to copy from
  another host.
