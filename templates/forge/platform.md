# The Forge platform: shape, containers, manifest, build source

## The shape

- One Forge host serves every app under one hostname: `https://<forge-host>/app/<name>/`.
- The edge (Traefik) **strips `/app/<name>`** before forwarding, so the container sees `/`. It
  sends `X-Forwarded-Prefix`, and Forge sets `BASE_PATH`, `PUBLIC_URL` and `FORGE_APP_NAME` as
  env *(inferred)*.
- Containers sit on the `forge-apps` Docker network only: no published ports, no volume mounts,
  512 MB / 1 CPU by default (max 2 GB / 2 CPU), `restart: unless-stopped` *(inferred)*.
- Shared services on the same network: `apps-postgres` (one database per app), a Garage S3 store
  (the `blob` harness), the IT SMTP relay (host `smtp`), Healer (errors), RBAC.
- Dev page per app: My apps ▸ app (`/dev/apps/<name>`): Rebuild & deploy, Restart, builds, logs.
  Env & secrets is on the **Containers** page and is Admin-only *(inferred)*.

## What every app's container must do

1. Serve **one HTTP port**, and read **all config from env** (no config file baked with values).
2. Work under `/app/<name>/`: every asset, router and API URL carries the prefix, because the edge
   strips it before your server sees the request.
3. Expose a **health path** that answers without sign-in from inside the network.
4. Keep **no state in the container filesystem**: a redeploy empties it. Files go to the blob
   store, data to Postgres.
5. Trust `X-Forwarded-*` only from the network in front of it (the edge or your own web container).
6. Never ship a secret in the image or the repo. Forge cannot pass `--build-arg`, so any
   build-time value must be a non-secret `ARG` default in the Dockerfile.

## Pattern: a web app and an API as two Forge apps from one repo

Typical split: a web container (static build served by nginx) and an API container, each its own
Forge app with its own build source (Dockerfile path and context folder). List them in `app.md`.

- The browser talks to **one origin**: nginx proxies `/api/`, `/health` and `/_forge/rbac/` to the
  API, so no backend URL is compiled into the frontend.
- **Resolve the API per request.** `resolver 127.0.0.11` plus a variable `proxy_pass`, so the web
  container starts before the API and survives an API redeploy. A static upstream makes nginx
  refuse to start when the API is down (a crash-loop).
- Make the upstream an `ENV` default in the Dockerfile (e.g. `API_UPSTREAM=<api-container>:<port>`);
  an unset variable in the nginx config also crash-loops it.
- Set `client_max_body_size` and read timeouts for the largest upload and the slowest endpoint;
  raise the timeout per location for long jobs.
- `add_header` is **not inherited** into a location that defines its own: repeat security headers
  (`X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`) in each such location.
- Run the API server with proxy headers on (uvicorn `--proxy-headers --forwarded-allow-ips='*'`
  or the equivalent): this is safe only because it is reachable from just the edge or the web
  container, never directly.
- Local images (`Dockerfile`) and Forge images (`Dockerfile.forge`) are separate, and local
  compose never reads the `.forge` ones. **Keep the pairs in sync by hand.**
- `forge.yaml` is **root-only** with no per-app section, so **both** apps read it: both get every
  harness (the web app gets a bucket it never uses; RBAC is provisioned for both).

## Getting an app onto Forge

1. The repo is in a GitHub org where the Forge GitHub App is installed.
2. Each Dockerfile meets "What every app's container must do" above.
3. `forge.yaml` at the **repo root** declares what the app needs (e.g. `harnesses: [blob]`,
   `needs: { rbac: true }`). A key the manifest omits (sign-in, port, health path) falls back to
   the build source's setting, which a Forge Admin registered *(inferred)*.
4. A Forge Admin registers the build source. The first deploy runs onboarding (catalog, Healer,
   postgres, blob, rbac, `secrets.check`, deploy). A failed non-secret step ships the app and marks
   "onboarding incomplete"; an Admin retries it *(inferred)*.
5. A harness key only arrives on a deploy: after merging a `forge.yaml` change, **Rebuild & deploy**.

## Build source: which branch deploys

- Each app has one **build source**: repo, watched branch, Dockerfile path, context folder, plus
  port, health path and sign-in. **Only a Forge Admin sets it.**
- Forge polls the watched branch every 60 s and builds each new head as `<app>:sha-<full sha>`,
  then an image-only redeploy. A failed build never touches the running app, and a failed commit is
  not retried (push a fix, or Rebuild & deploy).
- **Context folders matter:** a `COPY` path is relative to the context, not the repo root.
- **Check every build source watches `main`.** A web app stuck on an old commit usually means its
  source watches a stale feature branch. The watched branch is **not recorded in the repo**; ask an
  Admin and note it in `app.md`.

## Who can do what

- Assigned developers and Admins can **Rebuild & deploy** (the watched branch head) and
  **Restart**, both audited. Changing the build source, branch, env, secrets or `auth` on a running
  app, and anything on the host, is **Admin only**.
- Forge MCP (`/mcp`) mirrors the developer page (`forge_dev_app`, `forge_dev_build`,
  `forge_dev_logs`, `forge_dev_rebuild`, `forge_dev_restart`) *(inferred)*.
- Being a **Forge** Admin (may deploy) is unrelated to being an Admin **inside** the app.

## Optional platform services

- `needs.postgres` provisions `DATABASE_URL` / `PG*`. An app may instead read its own
  `<APP>_DATABASE_URL` and fall back to `DATABASE_URL` (see `database.md`).
- Healer is on by default and injects `HEALER_ENDPOINT`, `HEALER_APP_KEY`, `HEALER_KEY`. Read them
  and log one "Healer is off" line when unset. `HEALER_KEY` is a server-side secret and never
  reaches the browser.
- End-user guides: a `guides/` folder is published to the Forge wiki and **every Forge user can
  read it**, so never put real records in one *(inferred)*.
- Agents: Healer errors can become agent PRs on `forge/wi-*` branches if an Admin turns intake on.
  Forge never merges or approves *(inferred)*.
