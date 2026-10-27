# Sign-in at the edge, and the first Administrator

## Edge sign-in (any app)

- Sign-in is a **Forge deploy setting** (`auth: entra`), not app code. It defaults to `none`: the
  app is open and gets no token. **Every Forge app of a product must be gated**, API included.
- With it on, oauth2-proxy signs the person in and sends `Authorization: Bearer <Entra ID token>`
  on every request, replacing anything the browser sent. The audience is the *Forge Edge Sign-in*
  registration; sessions last 12 h; sign-out is `/oauth2/sign_out` on the host root.
- **Verify the token in the API**; do not trust the `X-Auth-Request-*` headers.
- The app still decides **what** a person may do; the token only says **who** they are.

## Verifying the token

- Check the **RS256** signature against Entra's **JWKS**, the **issuer** built from the tenant id,
  the **audience** = the edge client id, **expiry** with a small leeway (60 s), and require an `oid`.
  Any failure is 401; log a WARNING event name only.
- App env (own names): auth mode `edge`, the edge client id (**required**; startup fails without
  it), the tenant id, and the allowed email domains (default `energysolutions.com`).
- **Refuse to start** in edge mode with a dev-auth bypass switched on.
- The frontend's auth mode, dev-auth flag and base path are build-time `ARG` defaults in the Forge
  Dockerfile (see `env-and-secrets.md`).

## Is the gate on?

- Open `/app/<name>/` in an **InPrivate** window: a Microsoft sign-in means yes. Anonymous requests
  to the web app, its `/api/...` and the API app's health path should all get a **302 to
  Microsoft** (a smoke script can check this from the box).
- **Gate off:** `/api/.../me` returns 401 because no `Authorization` header arrived. A bad token is
  also 401, so read the log to tell them apart.

## A fresh database has no Admin

Migrations create the schema and built-in roles but **no accounts**, so someone has to be made the
first Administrator. Pattern:

- An env list of **emails** (and optionally Entra **object ids**), e.g. `<APP>_BOOTSTRAP_ADMIN_EMAILS`
  / `<APP>_BOOTSTRAP_ADMIN_OIDS` (the app picks its own names). Plain config, not secrets.
- **Promote at every start**: an existing active account is promoted and keeps its other roles; a
  known person with no account gets one; anyone else is made Admin at first sign-in.
- **Never demote.** Because it re-promotes on every start, to demote durably: remove the address,
  Rebuild & deploy, then demote in the app.
- Object ids cannot be reassigned, emails can; an oid is rarely known before first sign-in, hence
  both are useful.
- **Validate entries at startup** (one address at an allowed sign-in domain each) and fail naming
  the **position**, never echoing the address.
- **Remove the entries** once those people have signed in.
- Unknown people are **not auto-provisioned**: they get an access-pending page (403) and a way to
  request access. Provisioning still refuses when the sign-in domain is not allowed.
- An admin who signs in before reference data (e.g. an HR load) exists may get a placeholder
  record; plan how it is merged into the real one by email later.
