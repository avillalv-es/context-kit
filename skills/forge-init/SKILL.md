---
name: forge-init
description: Use when the user is creating, setting up, onboarding or deploying an app on Forge (the on-prem app host), asks to add Forge knowledge to a repo, asks what an app needs to run on Forge, or runs /forge-init. Asks which Forge features the app uses, writes the matching Forge knowledge to knowledge/forge/, writes knowledge/forge/app.md once with the features and secrets, adds the Forge section to CLAUDE.md, then plans every code change in plan mode. Do not use to answer a single Forge question in a repo that already has knowledge/forge/; read knowledge/forge/README.md instead.
---

# Forge init

Takes an app from "not on Forge" to a reviewed plan for everything it needs:
the Forge knowledge for the features it uses (`knowledge/forge/`), its own
facts (`knowledge/forge/app.md`), a short `## Forge` section in `CLAUDE.md`,
and a plan-mode prompt that adds the code.

The general files are plugin-owned. They come from
`${CLAUDE_PLUGIN_ROOT}/templates/forge/` and a re-run brings them up to date.
`app.md` belongs to the repo: it is written once and only ever added to.

Never write a value, secret, connection string or real hostname into any of
these files. Env vars and secrets are listed by name only.

## 1. CLAUDE.md first

If the project root has no `CLAUDE.md`, run the `context-cleanup` skill in
Mode A first (as `/context-init` would), then continue here.

## 2. Read the repo, then ask once

Read `forge.yaml`, `Dockerfile*`, `docker-compose*`, nginx configs, the
settings/config module and the dependency manifests. From them, work out the
apps (one per container), each one's port, Dockerfile, context and health path,
and which features the code already uses. On a re-run, start from the
"Features" list in `app.md`.

Then ask in **one** round (AskUserQuestion; multi-select for features, with
what the repo suggests pre-described as "(detected)"):

- **Features** (any number):
  - **Postgres**: a database on the shared `apps-postgres`.
  - **Blob storage (S3)**: uploaded files or attachments.
  - **Email (SMTP)**: the app sends mail through the IT relay.
  - **RBAC**: users and roles managed centrally from Forge.
  - **Scheduler / backups**: in-process jobs, in-app backups.
- **Apps**, only what the repo did not answer: names, and for each its port,
  Dockerfile, context folder and health path; whether it is a web + API pair.

**Always on, never asked:** Entra edge sign-in, Healer, the container rules,
env and secrets, the first deploy, releases and troubleshooting.

## 3. Copy the knowledge for those features

| Always | Postgres | Blob or Scheduler | Email | RBAC |
|---|---|---|---|---|
| `README.md`, `platform.md`, `env-and-secrets.md`, `sign-in-and-first-admin.md`, `first-deploy.md`, `release-checklists.md`, `troubleshooting.md` | `database.md` | `files-backups-scheduler.md` | `email-smtp.md` | `rbac.md` |

For each file to install, from `${CLAUDE_PLUGIN_ROOT}/templates/forge/`:

- missing from `knowledge/forge/`: copy it;
- identical (`cmp -s`): skip it;
- different: show `diff -u <repo file> <template>` and ask once, for all such
  files together, whether to overwrite. A local change that holds for every
  Forge app belongs in the plugin's template; one that holds only for this
  app belongs in `app.md`. Say so in one line when asking.

A file for a feature that was not chosen is not copied. One already there from
an earlier choice is left alone; mention it in the report.

## 4. app.md

If `knowledge/forge/app.md` is missing, write it from
`${CLAUDE_PLUGIN_ROOT}/templates/forge/app.md`. If it exists, only update its
"Features" list and add rows; never remove or rewrite what is there.

Fill in:

- **Features**: tick the chosen ones; Entra sign-in and Healer are always ticked.
- **Forge apps**: one row per app. The watched branch is known only to a Forge
  Admin: "ask an Admin" unless the user states it.
- **forge.yaml**: the harnesses and `needs` the features call for
  (`blob` for blob storage or backups, `rbac: true` for RBAC; `postgres: true`
  only if the app will read Forge's `DATABASE_URL`).
- **Secrets an Admin must set**: names only. Start from the features: the
  database URL when the app reads its own (not `needs.postgres`), any external
  API credential or signed webhook URL the code reads. Entra sign-in needs
  **no** secret: the app only verifies tokens.
- **Env vars**: every setting the code already reads, with why, secret or not,
  and who sets it; then the ones the plan will add for sign-in and each chosen
  feature, marked "(to add)".

## 5. The CLAUDE.md section

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" on forge CLAUDE.md
```

The section is opt-in: `/context-init` keeps it current once it is there but
never adds it on its own. If the file holds `<!-- context-kit:off forge -->`,
the user turned it off; `on` puts it back, so ask first.

If `knowledge/INDEX.md` exists and has no `forge/README.md` row, add one to its
"In this folder" table:

`| [forge/README.md](forge/README.md) | Anything about running this app on Forge: deploys, env vars, sign-in, email, the database, files, RBAC, failures. |`

## 6. The adoption prompt, in plan mode

Fill in `references/adopt-prompt.md`: keep the always-on parts, keep only the
feature blocks that were chosen (drop the `<tag>` lines around them), drop the
web + API paragraph unless the app is a pair, and fill each `<...>` from
`app.md`. Write it to `.claude/forge/adopt-prompt.md`.

Report steps 2 to 5 in one line each. Then enter plan mode (`EnterPlanMode`;
load it with ToolSearch if it is deferred) and plan from that prompt: read the
code, then present every change it lists, as slices, with the Admin hand-over
list at the end. If plan mode cannot be entered, say so in one line and ask the
user to switch to plan mode (Shift+Tab) and run the prompt.

Do not write code or commit before the plan is approved.
