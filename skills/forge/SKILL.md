---
name: forge
description: Use when you are unsure what Forge (the on-prem app platform) needs or does - forge.yaml keys, the Dockerfile and container rules, the /app/ base path, builds and deploys, env vars and secrets, sign-in vs access control, onboarding steps and probes, harnesses (Healer, RBAC, Postgres, blob/S3, AI gateway, Agent API, OCR, RAG, chat), API keys, developer access, Forge's MCP tools, agent PRs, or end-user guides; when a Forge build or deploy fails; or when the user runs /forge. Answers from Forge's own developer guide, read live. Do not use to set a repo up for Forge from scratch; that is forge-init.
---

# Forge developer guide

Forge ships its developer guide with each release, so the guide is the source
of truth and this skill does not bundle it. Read it live, in this order:

1. **Forge's MCP server** (preferred): `forge_dev_guides` lists the pages,
   `forge_dev_guide_page` with a path such as `forge/forge-yaml` returns one.
   `forge_harnesses` and `forge_app_harnesses` give live harness state.
2. **A local copy** at `~/.claude/forge-guide/<path>.md`, if the user keeps one
   (`/forge refresh` writes it). Say how old it is when you answer from it.
3. **This repo's `knowledge/forge/`**, if `/forge-init` wrote it. It is a
   summary, not the guide: say so when you rely on it.

If none is available, say so and ask the user to connect Forge's MCP server
(the guide's `forge/agents-and-healer-pipeline` page has the `claude mcp add`
line). Never ask for, read or handle a Forge API key or token.

## How to answer

1. Check the rules below. Many questions end there.
2. Otherwise fetch the one page the table names and read only what you need.
3. Answer with the rule and the page it came from (`forge/forge-yaml`). If the
   guide does not say, say so; do not guess a Forge behaviour.
4. Admin-only actions (register a build source, set a secret value, attach a
   harness, enable the AI gateway, issue an API key, turn strip prefix off):
   say so and list what to ask an Admin for. Agents never deploy.

## Rules that settle most questions

- **Container:** one HTTP port (8080 usual), a cheap unauthenticated health
  path, all config from env, no mounts. Served under `/app/<name>/`.
- **Base path:** never hard-code it. Read `FORGE_PATH_BASE` or the
  `X-Forwarded-Prefix` header, and use no root-relative asset URLs.
- **forge.yaml** at the repo root is strict: only `name, port, health, auth,
  access, onboarding, needs, secrets, guides, harnesses, api`. An unknown key
  fails the build. The branch and Dockerfile belong to the build source.
- **Secrets:** `secrets:` lists names only; an Admin sets the values in Forge.
  Names Forge manages itself are rejected there.
- **Env changes need Rebuild & deploy.** Restart keeps the old env, and harness
  credentials arrive only on a deploy.
- **Sign-in is not access.** `auth: entra` admits every employee. The app
  validates the bearer token itself and denies by default.
- **A failed build never touches the running app**, and a failed commit is not
  retried: push a fix or Rebuild & deploy.
- **Use a harness before building your own** error capture, audit, roles,
  database, storage or model access. Check its status live: some are planned.

## Which page

| Question | Page |
| --- | --- |
| What Forge gives an app; repo to running app | `forge/index` |
| First deploy; Dockerfile rules; onboarding steps; third-party images | `forge/getting-started` |
| Org rules for agents: user guides, PR labels, commits, harnesses | `forge/claude-org-rules` |
| Any `forge.yaml` key, type or limit; the `api:` block | `forge/forge-yaml` |
| Token validation per stack; the access-control probe | `forge/access-control` |
| Build pipeline; base path per stack; refused deploys | `forge/build-and-deploy` |
| Env layers; managed env per harness; adding a secret | `forge/env-and-secrets` |
| My apps; developer assignment; rebuild and restart rights | `forge/developer-access` |
| Calling or serving an API with Forge API keys | `forge/api-keys` |
| Healer error to agent PR; reviewing agent PRs; the MCP server | `forge/agents-and-healer-pipeline` |
| The end-user guide; `guides:`; the guide check | `forge/user-guides` |
| Harness catalog and how to turn one on | `harnesses/index` |
| Healer, RBAC, Postgres, blob storage | `harnesses/healer`, `harnesses/rbac`, `harnesses/postgres`, `harnesses/blob` |
| AI gateway, Agent API | `harnesses/ai-gateway`, `harnesses/agent-api` |
| OCR, RAG, chat | `harnesses/ocr`, `harnesses/rag`, `harnesses/chat` |

A failing deploy: start with "When a deploy is refused" in
`forge/build-and-deploy`, then the harness page's Gotchas. If `forge_dev_guides`
lists a page this table lacks, use it.

## This repo's own Forge facts

`knowledge/forge/app.md` (from `/forge-init`) holds this app's names, secrets
and env list. Where `knowledge/forge/` and the guide disagree on a Forge-wide
rule, the guide wins: say so in one line.

## Refreshing the local copy

`/forge refresh` writes the guide to `~/.claude/forge-guide/`, outside every
repo, so it is never committed:

1. With Forge's MCP server, list the pages with `forge_dev_guides` and save
   each `forge_dev_guide_page` result as `~/.claude/forge-guide/<path>.md`.
2. Without it, the user can open the guide in a browser where they are signed
   in; convert each page's article to Markdown and save it the same way.
3. Write the date to `~/.claude/forge-guide/FETCHED` and report which pages
   changed.

The guide is internal: never copy it into this plugin's repo or any public one.
