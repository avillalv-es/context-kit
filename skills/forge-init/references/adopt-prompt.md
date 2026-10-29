# Forge adoption prompt (template)

The skill fills this in and writes it to `.claude/forge/adopt-prompt.md` in the app repo, keeping
the always-on parts and only the feature blocks that were chosen. `<...>` are filled from the
answers and `knowledge/forge/app.md`. Delete these first two paragraphs and every unused block.

---

# Make <app> run on Forge

Plan, in plan mode, every change this repo needs to build, start and work on Forge, then stop for
approval. Read `knowledge/forge/README.md` and `knowledge/forge/app.md` first, and the file each
step names. Read the code before proposing anything; reuse what is already there.

**Forge apps:** <name: Dockerfile, context, port, health path, one line each>
**Features:** Entra sign-in, Healer<, Postgres><, blob storage><, email (SMTP)><, RBAC><, scheduler/backups>

## Rules for every change

- No value, secret, connection string or real hostname in the repo, an image, a log or this plan.
  Env vars by **name** only.
- All config from env, read in one place, validated at startup: a bad value stops the process
  naming the setting, never echoing the value.
- Keep the local dev setup working; the Forge Dockerfiles sit beside the local ones.

## Always

1. **Containers** (`platform.md`): a `Dockerfile.forge` per Forge app meeting the six container
   rules. The frontend is built for base path `/app/<name>/`; every asset, router and API URL
   carries it. An unauthenticated health path. No state on disk. Build-time values are non-secret
   `ARG` defaults.
<web+api>   **Web + API:** nginx in the web app proxies `/api/`, `/health`<, `/_forge/rbac/`> to the API,
   resolving per request (`resolver 127.0.0.11`, variable `proxy_pass`, upstream as an `ENV`
   default); repeat security headers per location; the API trusts proxy headers.</web+api>
2. **`forge.yaml`** at the repo root with exactly: <harnesses / needs for the chosen features>.
3. **Entra edge sign-in** (`sign-in-and-first-admin.md`): in the API, verify the bearer token on
   every request: RS256 against the tenant's JWKS, issuer from the tenant id, audience = the edge
   client id, expiry with 60 s leeway, require `oid`; 401 on any failure, WARNING event name only.
   Never trust `X-Auth-Request-*`. Settings: auth mode `edge`, the edge client id (required), tenant
   id, allowed email domains. Refuse to start in edge mode with any dev-auth bypass on. Map `oid` /
   email to the app's own account; unknown people get an access-pending 403, not an account. A
   first-Admin bootstrap list (emails and oids) that promotes at start and never demotes. A
   sign-out link to `/oauth2/sign_out`. There is **no client secret**: the app only verifies tokens.
4. **Healer** (`platform.md`): read `HEALER_ENDPOINT`, `HEALER_APP_KEY`, `HEALER_KEY` when present
   and log one "Healer is off" line when not. `HEALER_KEY` never reaches the browser.
5. **Env and secrets** (`env-and-secrets.md`): update the tables in `app.md` with every setting
   the code reads: name, why, secret or not, set by (Admin / Forge-injected / Dockerfile `ARG`), and
   the "leave unset on Forge" list. Secrets an Admin must set: <the list, e.g. the database URL if
   the app does not use `needs.postgres`, any external API credential>. Injected by Forge, never
   set by hand: <`FORGE_RBAC_*`, `S3_*`/`AWS_*`, `HEALER_*` as applicable>.
6. **Smoke script** that takes no secrets: health answers; anonymous `/app/<name>/` and its API get a
   302 to Microsoft; an asset loads under the base path.

<postgres>
## Postgres (`database.md`)

- The URL from `<APP>_DATABASE_URL`, falling back to Forge's `DATABASE_URL`; driver prefix
  rewritten; no default; never logged.
- Migrations run at every container start as the owner login (no `GRANT`, `CREATE ROLE`,
  `CREATE EXTENSION`); the only migration path; dev fixtures stay out of the image.
- Pool plus overflow ≤ 20 per app, a pool timeout, and a 503 when the pool is full.
</postgres>
<blob>
## Blob storage (`files-backups-scheduler.md`)

- Files go to the `blob` harness through the injected `S3_*` / `AWS_*` names, path-style
  addressing; the app never creates the bucket and never stores the credentials.
- No storage configured: the upload route answers 503 and writes nothing. Nothing on local disk.
</blob>
<scheduler>
## Scheduler and backups (`files-backups-scheduler.md`)

- One worker, or a lock: the in-process scheduler runs once per process. A setting turns it on.
- In-app backups go to the blob store, never a container directory; a restore accepts only the same
  schema revision.
</scheduler>
<smtp>
## Email through the SMTP relay (`email-smtp.md`)

- Settings: host `smtp`, port 587, STARTTLS off, no credentials, one From at
  `@energysolutions.com` (startup refuses any other domain), an absolute base URL for links.
- The code rules in section 3: one outbox choke point, record before send, a dead relay never
  blocks the business action, re-check at send time, one recipient per message, a timeout and no
  `with smtplib.SMTP(...)`, plain text plus HTML, secrets only in the link fragment, event-name logs.
- Test mode (filter) on until sign-off; a kill switch stored in the database.
</smtp>
<rbac>
## RBAC (`rbac.md`)

- `needs: { rbac: true }`; serve the contract at `/_forge/rbac/v1`, outside the sign-in
  middleware. Declare only assignable capabilities as `resource:action` plus `rbac:manage`;
  reserved admin keys are never declared. Grants add to existing accounts, read fresh per request;
  a store failure fails closed. Run the Healer conformance kit locally.
</rbac>

## Deliver

- The plan as small, reviewable slices, each with its files and how it is tested.
- A last slice that updates `app.md` and walks `first-deploy.md` section 1.
- An **Admin hand-over list**, exactly as `first-deploy.md` section 2 needs it: build source per
  app (watched branch `main`), `auth: entra` on every app, and each env name and secret to set.
  Names only.
