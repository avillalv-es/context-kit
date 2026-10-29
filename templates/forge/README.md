# Forge knowledge: running an app on Forge on-prem

Everything needed to build, configure, deploy and debug an app on Forge, the on-prem app host.
These files are **plugin-owned**: `/forge-init` copies them from the context-kit plugin into
`knowledge/forge/`, and re-running `/forge-init` **refreshes** them. Put this app's own facts
(its apps, build sources, env list, failures and release steps) in [app.md](app.md), which is
never overwritten.

Forge is still being built by its owner, so re-check a Forge-generic rule against the running
guide (My apps ▸ Developer guide) before relying on it.

**Marking.** Anything not confirmed from the repo's code is tagged *(inferred)*. Forge-side facts
(what an Admin set, what Forge injects) cannot be seen from the repo. Env vars are listed by
**name only**; no value, secret, connection string or real address belongs in this folder.

## Files

Every app gets all of these except the feature files. A feature file (`database.md`,
`files-backups-scheduler.md`, `email-smtp.md`, `rbac.md`) is copied only when the app uses that
feature; a missing one means the feature is not in use. Re-run `/forge-init` to add it.

| File | Read it when |
|---|---|
| [app.md](app.md) | Always: this app's Forge apps, build sources, env list, release steps and failures. |
| [first-deploy.md](first-deploy.md) | Getting the app onto Forge the first time: what Dev does in the repo, what to ask an Admin for, what to check after. |
| [platform.md](platform.md) | First time on Forge: the shape (edge, path prefix), what a container must do, the web+API pattern, `forge.yaml`, build source, who can do what, optional services. |
| [env-and-secrets.md](env-and-secrets.md) | Setting or changing any variable: the layers, Restart vs Rebuild & deploy, secrets, build-time vs runtime values, what Forge injects. |
| [email-smtp.md](email-smtp.md) | Anything about mail: the IT relay's rules, the settings an app needs, what the code must do to comply, test mode vs dev redirect, kill switch, verifying a send, failure modes. |
| [sign-in-and-first-admin.md](sign-in-and-first-admin.md) | Edge sign-in (`auth: entra`), verifying the token in the API, the first Administrator on an empty database. |
| [database.md](database.md) | The shared Postgres: owner login, connection caps, migrations at start, pool size, moving data, host backups. |
| [files-backups-scheduler.md](files-backups-scheduler.md) | Attachments (no mounts, use the blob harness), in-app backups, the in-process scheduler and why it needs one worker. |
| [rbac.md](rbac.md) | Forge's federated RBAC harness and adopting it additively. |
| [release-checklists.md](release-checklists.md) | Before a release or go-live: the ordered steps and the go-live checks. |
| [troubleshooting.md](troubleshooting.md) | Something is broken: failures seen on Forge apps, quick checks, known risks. |

## Keeping it current

Add a Symptom / Cause / Fix row to `app.md` the moment a failure is hit, and an app-specific step
to its "Release steps". A rule that holds for **every** Forge app should go back to the plugin's
`templates/forge/` instead, so all apps get it. A new topic gets its own file and a row above.
