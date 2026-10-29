# First deploy: from a repo to a running Forge app

The order that works, start to finish. Each step names who does it and where the detail is.
**Dev** = an assigned developer; **Admin** = a Forge Admin. Record the answers in `app.md`.

## 1. In the repo (Dev)

1. **Pick the features** the app needs: Postgres, blob storage (S3), email (SMTP), RBAC,
   scheduler/backups. Entra sign-in and Healer apply to every app. List them in `app.md`.
2. **One `Dockerfile.forge` per Forge app** that meets the six container rules (`platform.md`):
   one HTTP port, all config from env, works under `/app/<name>/`, an unauthenticated health path,
   no state on disk, no secret in the image (build-time values are non-secret `ARG` defaults).
3. **`forge.yaml` at the repo root** with only the harnesses and `needs` the features call for
   (e.g. `harnesses: [blob]`, `needs: { rbac: true }`). Every Forge app built from this repo reads it.
4. **Edge sign-in in the API** (`sign-in-and-first-admin.md`): verify the bearer token on every
   request, refuse a dev-auth bypass in edge mode, and add the first-Admin bootstrap list.
5. **Config validated at startup**, naming the setting and never the value (`env-and-secrets.md`).
6. **The env and secrets list** in `app.md`: every name, why, secret or not, who sets it.
7. **A smoke script** that takes no secrets: health answers, anonymous requests get a 302 to
   Microsoft, the base path serves assets.
8. Merge to `main`.

## 2. On Forge (Admin; ask for each by name)

1. Install the Forge GitHub App on the repo's org, if it is not already there.
2. **Register a build source per Forge app**: repo, **watched branch `main`**, Dockerfile path,
   context folder, port, health path.
3. **Set sign-in to `auth: entra`** on every app of the product, API included.
4. **Set the env and the secrets** from `app.md` (Containers ▸ app ▸ Env & secrets). Secrets go in
   the secret field only; harness values (`S3_*`, `FORGE_RBAC_*`, `HEALER_*`) are injected, never set.
5. The first deploy runs onboarding (catalog, Healer, postgres, blob, rbac, `secrets.check`,
   deploy). A failed step marks "onboarding incomplete"; the Admin retries it.

## 3. After the first deploy (Dev)

1. **Read the log** for a startup refusal (it names the setting).
2. Open `/app/<name>/` in an **InPrivate** window: Microsoft sign-in, then the app.
3. The bootstrap Admins sign in; then remove them from the list and **Rebuild & deploy**.
4. Run the smoke script on the box, then work through `release-checklists.md` before go-live.
5. Any failure: a Symptom / Cause / Fix row in `app.md` (`troubleshooting.md` first).

**Every env change after this needs Rebuild & deploy**; a Restart keeps the old env.
