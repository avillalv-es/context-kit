# Troubleshooting on Forge

Logs: My apps ▸ app ▸ logs (or `forge_dev_logs`). Return a request id on every error response, so
a quoted id can be searched in the API log. Mail problems: `email-smtp.md` section 7. This app's
own failures: `app.md`.

## Failures seen on Forge apps

Add a row to `app.md` the moment one is hit here; promote it to this table only if every app can
hit it.

| Symptom | Cause | Fix |
|---|---|---|
| nginx crash-loops | Unresolved variable in the nginx config, or a static upstream while the API is down | Set the variable as an `ENV` default; resolve per request through `127.0.0.11` with a variable `proxy_pass`. |
| "Could not sign you in", `/api/.../me` 401 | Deployed with `auth: none`, so no token arrives | An Admin sets `auth: entra` on **every** app of the product. |
| Web app stuck on an old commit after merges | Build source watches a stale branch | An Admin points it at `main`. |
| A local stack mailed real people | A developer `.env` with a real HTTP-based mail flow URL and test mode off | Keep test mode on locally, or pause sending in the app's admin screen. |
| A reference-data sync returned `500` on a unique violation | A feed row's unique key (e.g. email) already belonged to a different entity, and the load had no per-entity isolation | Run each entity in its own savepoint, let the current feed win the key, and answer `422` naming the stage, exception class and SQLSTATE. |

## Quick checks by symptom

| Symptom | Check |
|---|---|
| Container restarting at start | Startup refusal in the log (a bad env value names the variable), or multiple migration heads. |
| Env change "did nothing" | It was a Restart; use Rebuild & deploy. Or it is a build-time frontend value. |
| Assets 404 / blank page | Base path: the frontend must be built with `/app/<name>/`. |
| `503` busy / pool full | Pool exhausted; see `database.md`. |
| Uploaded files gone after a deploy | Storage is `local`; set `s3`. |
| `403` cross-site on save | CSRF/origin check on and forwarded headers do not match; unset it, add the origin. |
| `/_forge/rbac/v1` 503 | `FORGE_RBAC_*` not written yet; redeploy after onboarding. |

## Known risks (not yet acted on)

- **Backups.** Garage data is not backed up off the box; the host `pg_dump` is the real database
  backup *(inferred)*.
- **Scheduler.** Safe only with one worker; adding workers needs a lock. Whether it is on in Forge is
  an Admin decision to record in `app.md`.
- **Memory.** One worker should fit 512 MB but it is unmeasured; ask for 1 GB if it restarts under load.
- **Email** can only be tested from inside Forge, and only with the owner's go.
- **First edge sign-in** and any emailed link after sign-in are unproven on a new app until done.
