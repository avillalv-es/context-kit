# Files, backups and the scheduler on Forge

## Any app

- Containers have **no mounts**: anything written to the container filesystem is lost on the next
  redeploy. Use the `blob` harness (`harnesses: [blob]` in `forge.yaml`) for files.
- The harness injects `S3_BUCKET`, `S3_ENDPOINT`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. Read them as aliases; never store the credentials.
  The store is Garage: use **path-style** addressing. The app never creates the bucket.
- Garage's object data is **not backed up off the box** yet *(inferred)*.
- An in-process scheduler runs once **per process**: run one worker, or take a lock.

## Attachments pattern

- Offer storage backends by setting (e.g. `local`, `s3`, `database`). **With none configured, the
  upload route answers `503` and writes nothing.** On Forge pick `s3`: `local` is emptied by every
  redeploy.
- **Switching stores does not move files**: files under the old setting download as 404. Moving
  them is a one-time steward step (a script that verifies size and checksum, then deletes the old
  copy, and is idempotent so it can be rerun until zero failures).
- Keep object keys under a stable prefix per feature (e.g. `<thing>/<id>/<uuid>`), and a separate
  prefix for backups.
- Run a **retention job** if files should not live forever (daily; it runs only where the
  scheduler is on).
- Files kept in the database are not in an in-app backup file if that has a size cap; the host
  `pg_dump` has them.

## In-app backups

- **No in-container backup directory**: it is emptied by every redeploy. Leave the local dir unset
  and answer `503 backup_not_configured` from the folder routes; write backups to the blob store.
- A backup file holds the **whole database**: a durable copy needs a private location.
- A restore accepts only a backup of the **same schema revision**: take a fresh backup **right
  after any migration**.
- Never prune manual and safety backups; keep a retention count for scheduled ones.

## Scheduler

- **One worker per process** (e.g. APScheduler in-process, one server worker). The scheduler must be
  on in **exactly one** process: two run every job twice. Do not add workers without a lock.
- Gate it with a setting that is off by default and switch it on deliberately on Forge.
