# Release and go-live checklists (Forge-side steps)

Every env change below applies only on **Rebuild & deploy** (a Restart keeps the old env). Read the
API app's log after each deploy for a startup refusal. App-specific steps go in `app.md`.

## Every release

1. Merge to `main`; confirm each build source watches `main` and built the new sha.
2. If the release has a migration: **take a fresh backup straight after the migration runs**
   (a restore accepts only the same schema revision).
3. Run the app's smoke check (a script that takes no secrets, run on the Forge box).
4. Read the log for a startup refusal or multiple migration heads.

## Go-live

- **Email:** verify with test mode on (`email-smtp.md` section 6); at sign-off remove the test-mode
  settings and redeploy.
- **Emailed links:** open one in an InPrivate window: it must still open the target page after
  Microsoft sign-in.
- **First Administrators** have signed in; remove them from the bootstrap list.
- **File storage** is on the blob store, and a backup to it succeeds.
- **Scheduler** is on in exactly one process.
- **Pool vs budget:** the pool fits Forge's connection cap (`database.md`); check Postgres
  `max_connections` against it.
- **CSRF / origin check:** if the app has one that ships log-only, smoke-test a save on Forge,
  confirm no would-refuse line from legitimate traffic, then enforce it and redeploy. If a real save
  is refused, unset it and add the origin to the allowed list.
- **Go-live SQL checks** from `database.md` (duplicate emails, `SHOW timezone` = UTC).
- Ask the Forge admin whether the edge also sets security headers (duplicates are harmless).
- **Record anything that failed** (first real edge sign-in included) as a row in `app.md`.
