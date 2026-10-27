# RBAC: central user management from Forge

## Any app

- Forge asks every hosted app to adopt its federated RBAC harness (es-app-dev/Healer
  `clients/rbac/CONTRACT.md`): declare `needs: { rbac: true }` in `forge.yaml` and serve the
  contract API at `/_forge/rbac/v1`. The vendored `es_platform` library implements it.
- On the next deploy Forge writes `FORGE_RBAC_ISSUER`, `FORGE_RBAC_AUDIENCE`, `FORGE_RBAC_JWKS_URL`,
  opens `/app/<name>/_forge/rbac/` past the sign-in, then runs `rbac.probe` (conformance),
  `rbac.admins` (grants Forge admins and the app's developers the RBAC admin role) and `rbac.align`.
  Until those env vars exist the route answers 503.
- Forge seeds its default roles **once**: a store onboarded earlier keeps old grants until changed
  in Forge.

## Adopting it additively

Pattern for an app that already has its own users and roles, which stay the record:

- **Mount `/_forge/rbac/v1` outside the app's sign-in middleware**: the edge sign-in never sees
  Forge's token, which is verified by the library.
- **Store grants in their own tables** (the library's shape: roles, role permissions,
  assignments), via a migration.
- **Declare only assignable capabilities**, as `resource:action`, plus `rbac:manage`. Typical roles:
  viewer = read-only capability; editor = every assignable one; admin = the same plus `rbac:manage`.
- **Reserved or admin-only keys are never declared**, so Forge can never grant them (user and role
  management, query console, backups, email controls). Re-check what Forge's `editor` role gets
  whenever the capability list changes.
- **What a grant does:** it ADDS capabilities to an existing active **admin-experience** account,
  read fresh on every request (by `oid`, or by the token's `groups`). Nothing for a standard account
  or a person with no account. A Forge revoke removes only what Forge granted. A **store read
  failure fails closed**.
- **Two Forge apps, one store.** The web container's nginx forwards `/_forge/rbac/` to the API, which
  accepts tokens for its own slug plus extra audiences (the web app's slug). Both cards then show
  the same grants.
- **Audit:** RBAC changes go to Healer when `HEALER_KEY` is a service key, else to the log; **not**
  to the app's own audit log (its payloads may be forbidden from carrying an object id).
- **Verify locally** with the Healer conformance kit (`Healer.Rbac.ContractTests`), against the API
  directly and against the web container through the Forge nginx config.
- Open question for each app: whether accounts and roles later move onto RBAC entirely.
