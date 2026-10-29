# Env and secrets on Forge

## How Forge layers env (later wins)

base (deploy request) → config (Admin) → secrets (Admin, Key Vault, value never shown again) →
managed (written by onboarding: harness keys such as `S3_*`, `AWS_*`, `FORGE_RBAC_*`, `HEALER_*`)
→ platform (`FORGE_APP_NAME`, `BASE_PATH`, `PUBLIC_URL`; cannot be overridden) *(inferred)*.

## Rules that bite every app

- **A Restart keeps the old env.** A change applies only on **Rebuild & deploy** or an Admin's
  **Redeploy now**.
- Only a Forge Admin sets env and secrets (Containers ▸ app ▸ Env & secrets).
- **Build-time values cannot be changed on the running container.** Forge cannot pass
  `--build-arg`, so they are `ARG` defaults in the Dockerfile (typically the frontend's auth mode,
  dev-auth switch and base path); changing one means editing the Dockerfile and rebuilding.
- **Validate config at startup**, so a bad value stops the process with a message naming the
  variable (never echoing the value), and read the log after every deploy.
- Never put values, keys or connection strings in the repo, an image, a log line or a chat.
  Anything that authorises a caller (a DB URL with a password, a signed webhook or flow URL, a
  service key) goes in the secret field only.
- **Recommended: a blank variable means "unset, use the default"** (e.g. pydantic-settings
  `env_ignore_empty`), so an empty line in the Admin form cannot break a default. Set a blank
  only on purpose.
- Harness credentials (S3, RBAC, Healer) are **injected by Forge**; never copy them into config.

## Injected by Forge, never set by hand

`FORGE_RBAC_ISSUER`, `FORGE_RBAC_AUDIENCE`, `FORGE_RBAC_JWKS_URL`, `HEALER_*`, `S3_BUCKET`,
`S3_ENDPOINT`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
and the platform trio `FORGE_APP_NAME`, `BASE_PATH`, `PUBLIC_URL`.

- **S3 credentials are not settings:** boto3 (or the SDK) reads them from its own credential chain,
  so no field in the app's settings class can render them.
- The web container usually takes only its upstream variable, and only if the default is wrong.

## Your app's list

The app's own variable list lives in [app.md](app.md): **names only**, with why, secret or not, and
who sets it. Each app picks its own names (this folder uses `<APP>_` placeholders). Keep one place
in code that reads the environment, a reference file with every variable and its default, and a
short hand-over sheet of only what a person must set. Mark anything to **leave unset on Forge**
where the default is the safe value (dev-auth switch, SQL console, local backup dir, dev
environment flag).
