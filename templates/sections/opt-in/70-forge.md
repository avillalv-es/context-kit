## Forge

This app runs on Forge, the on-prem app host. Its Forge knowledge is in
`knowledge/forge/`; start at `knowledge/forge/README.md`, which says which file to read.

- Read it before touching a Dockerfile, `forge.yaml`, env vars, sign-in, email,
  the database, files or backups, or when a deploy misbehaves.
- This app's own Forge facts (features, apps, secrets, env list) are in `knowledge/forge/app.md`.
- A Restart keeps the old env; an env change needs Rebuild & deploy.
- No values, secrets or connection strings in the repo, an image or a log.
- The other files there are plugin-owned: re-run `/forge-init` to refresh them.
- Turn this off with `/forge-init off`.
