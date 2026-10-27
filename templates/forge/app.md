# This app on Forge

Owned by this repo: written once by `/forge-init`, **never overwritten**. Add to it freely. The
other files in this folder are plugin-owned and describe Forge in general. Names only, never
values, secrets or real hostnames.

## Forge apps

| Forge app | Container | Port | Dockerfile | Context | Health path | Watched branch (ask an Admin) |
|---|---|---|---|---|---|---|
| `<app-name>` | `forge-app-<app-name>` | `<port>` | `<path/Dockerfile.forge>` | `<folder>/` | `<path>` | `<branch>` |

## forge.yaml

- harnesses: `<blob | none>`
- needs: `<rbac | postgres | none>`

## Env vars

Names only. Each app picks its own names (`<APP>_` prefix).

| Name | Why | Secret? | Set by |
|---|---|---|---|
| `<APP>_DATABASE_URL` | the database | **yes** | Admin |
| `<APP>_<NAME>` | `<purpose>` | `<yes/no>` | `<Admin / Forge / Dockerfile ARG>` |

## Leave unset on Forge

- `<APP>_<NAME>`: `<why the default is the safe value>`

## Release steps

App-specific, in order, on top of `release-checklists.md`:

1. `<step, e.g. a post-deploy action only this app needs>`

## Failures hit

| Symptom | Cause | Fix |
|---|---|---|
| `<what was seen>` | `<why>` | `<what fixed it>` |
