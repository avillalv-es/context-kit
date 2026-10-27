---
name: forge-init
description: Use when the user is creating, setting up, onboarding or deploying an app on Forge (the on-prem app host), asks to add Forge knowledge to a repo, or runs /forge-init. Writes the plugin's general Forge knowledge to knowledge/forge/, writes knowledge/forge/app.md once from the app's own answers, and adds the Forge section to CLAUDE.md. Re-running refreshes the general files. Do not use to answer a single Forge question in a repo that already has knowledge/forge/; read knowledge/forge/README.md instead.
---

# Forge init

Gives a Forge app the knowledge every Forge app needs, in the three-tier
layout: the general rules in `knowledge/forge/` (looked up when needed), the
app's own facts in `knowledge/forge/app.md`, and a short `## Forge` section in
`CLAUDE.md` that says where both are.

The general files are plugin-owned. They come from
`${CLAUDE_PLUGIN_ROOT}/templates/forge/` and a re-run brings them up to date.
`app.md` belongs to the repo: it is written once and never overwritten.

Never write a value, secret, connection string or real hostname into any of
these files. Env vars are listed by name only.

## 1. CLAUDE.md first

If the project root has no `CLAUDE.md`, run the `context-cleanup` skill in
Mode A first (as `/context-init` would), then continue here.

## 2. The general files

For each file in `${CLAUDE_PLUGIN_ROOT}/templates/forge/` except `app.md`:

- missing from `knowledge/forge/`: copy it;
- identical (`cmp -s`): skip it;
- different: show `diff -u <repo file> <template>` and ask once, for all such
  files together, whether to overwrite. A local change that holds for every
  Forge app belongs in the plugin's template instead; one that holds only for
  this app belongs in `app.md`. Say so in one line when asking.

Create `knowledge/forge/` if it is missing.

## 3. app.md, once

If `knowledge/forge/app.md` exists, leave it alone and skip this step.

Otherwise read the repo first (`forge.yaml`, `Dockerfile*`, `docker-compose*`,
nginx configs, the settings/config module) and fill in what it already shows.
Then ask, in one round, only what the repo could not answer:

- the Forge app name(s), one per container;
- for each: its port, Dockerfile, build context folder and health path;
- what `forge.yaml` declares or should declare (harnesses, `needs`).

Write `app.md` from `${CLAUDE_PLUGIN_ROOT}/templates/forge/app.md` with those
answers. The watched branch is known only to a Forge Admin: leave it as
"ask an Admin" unless the user states it. In the env table, list the variable
names the code reads with why and whether each is a secret, never a value;
leave placeholder rows where nothing is known yet.

## 4. The CLAUDE.md section

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/claude-sections.sh" on forge CLAUDE.md
```

The section is opt-in: `/context-init` keeps it current once it is there but
never adds it on its own. If the file holds `<!-- context-kit:off forge -->`,
the user turned it off; `on` puts it back, so ask first.

## 5. The index

If `knowledge/INDEX.md` exists and has no `forge/README.md` row, add one to its
"In this folder" table:

`| [forge/README.md](forge/README.md) | Anything about running this app on Forge: deploys, env vars, sign-in, email, the database, files, RBAC, failures. |`

## 6. Report

One line per step: files copied, skipped and overwritten; `app.md` written or
kept; the section's `claude-sections.sh` output; the index row added or
already there. Do not commit.
