# Email on Forge: the SMTP relay

Everything about sending mail from a Forge app: what the relay accepts, what to set, what the code
must do, how to test without mailing real people, and how to tell what went wrong. The relay rules
hold for every app. Each app picks its own variable names (`<APP>_` placeholders below).

## 1. The relay (IT's, shared by every Forge app)

| Fact | Value | Consequence |
|---|---|---|
| Host | `smtp` | A Docker-network name: it **resolves only on Forge's network**. Nothing sends from a laptop or a local stack. |
| Port | `587` | |
| Auth | **none** | The relay authorises by sending host. There is no username or password, so an app holds **no mail credential**. Never add one. |
| TLS / STARTTLS | **off** | Plain SMTP on 587. Turning STARTTLS on fails the handshake. |
| From | must be `@energysolutions.com` | Any other sender domain is refused with **554**. |
| Size | 25 MB per message | Link to files; do not attach them. |
| Recipients | company addresses | Keep an allow-list in the app; the relay is not your fence. |

## 2. What to set

Set by a Forge Admin in Containers ▸ app ▸ Env & secrets, then **Rebuild & deploy** (a Restart
keeps the old env). Until the SMTP host and From are set, no mail leaves: the app should fail
closed (a `503 email_not_configured` on an admin test, `failed` outbox rows otherwise).

| Setting (own name) | Forge value | Notes |
|---|---|---|
| `<APP>_EMAIL_TRANSPORT` | leave unset (`smtp`) | An HTTP-based transport is a stopgap only; its flow URL is a credential (below). |
| `<APP>_SMTP_HOST` | `smtp` | Required to send. |
| `<APP>_SMTP_PORT` | `587` | Set it: the library default 25 is wrong for the relay. |
| `<APP>_SMTP_FROM_ADDRESS` | `<no-reply name>@energysolutions.com` | Required to send. **Startup fails** unless its domain equals the allowed domain, because the relay would answer 554. |
| `<APP>_SMTP_USE_STARTTLS` | leave unset (`false`) | The relay has TLS off. When `true`, verify chain and hostname. |
| `<APP>_SMTP_TIMEOUT_SECONDS` | leave unset (about 10) | An unresponsive relay must never hold a worker. |
| `<APP>_EMAIL_ALLOWED_DOMAIN` | leave unset (`energysolutions.com`) | The only recipient (and From) domain. |
| `<APP>_APP_BASE_URL` | `https://<forge-host>/app/<name>` | Base of every emailed link and the CSRF own-origin. **Startup fails** on a relative or scheme-less value; warn if the path is not `/app/<name>`. |
| `<APP>_EMAIL_TEST_MODE` | `true` until sign-off | A **filter** (section 4). |
| `<APP>_EMAIL_TEST_RECIPIENTS` | the testers, comma-separated | Required while test mode is on; each one address at the allowed domain, or startup fails. Remove both at sign-off. |
| `<APP>_ENVIRONMENT` | leave unset (`prod`) | `dev` turns on the **redirect** (section 4). Not for a live Forge app. |
| `<APP>_DEV_EMAIL_RECIPIENT` | leave unset | Required when the environment is `dev`. |
| `<APP>_EMAIL_CONTACT_LINE` | optional | Footer "Questions? ..." line; plain text, escaped. |
| `<APP>_LINK_TOKEN_TTL_HOURS` | leave unset | Link lifetime from **issuance** (mail scanners fetch links on delivery). |

**None of these is a secret.** A flow or webhook URL with a signature (an HTTP-based mail flow) is a
credential: **secret field only**, never logged. Use SMTP on Forge.

Startup refusals all name the variable and the rule and **never an address**: From at the wrong
domain; test mode on with an empty or malformed list; `dev` without a valid redirect address; an
HTTP transport without a plausible URL; a non-absolute base URL.

## 3. What the code must do to comply

1. **One choke point.** Every message goes through one outbox module (`enqueue` then
   `attempt_delivery`). Nothing else calls the send function, and nothing but one module calls
   `smtplib`. Kill switch, hourly cap, test mode, redirect and the recipient check all live there,
   so a new caller cannot skip them.
2. **Record before send.** Commit the outbox row (and any link token) **before** the attempt. A
   committed row for undelivered mail is a queryable to-do; delivered mail with no row cannot be
   proven sent.
3. **A dead relay never blocks the business action.** Commit, return, then send in a background task
   with its own DB session. Catch `smtplib.SMTPException`, `OSError` and the not-configured error,
   and record `failed` with a `last_error`. Decide on retry explicitly: a `pending` row left by a
   crash is not resent unless you build that.
4. **Re-check at send time**, not only at enqueue: token unspent, row still `pending`, the business
   step still current, test mode, allowed domain. A stale one is `suppressed`.
5. **Recipients:** exactly **one address per message**, at the allowed domain. Pass the envelope
   explicitly (`to_addrs`), never re-derived from headers.
6. **From** is the single configured address at the allowed domain; **startup refuses** anything else.
7. **No credentials, stdlib only.** `smtplib` + `email.message`; no Graph, no OAuth, no new
   dependency.
8. **Always set a timeout**, and do **not** use `with smtplib.SMTP(...)`: its `__exit__` calls
   `quit()`, and a relay that accepts DATA (250) then answers QUIT oddly would raise and record a
   delivered mail as `failed`. Only what is raised before `send_message` returns means "not sent";
   the goodbye is best effort.
9. **Format:** `multipart/alternative`, plain text first and HTML second, so a client that will not
   draw HTML still shows the link. Escape every variable going into HTML.
10. **Links** are built from an absolute base URL and carry the secret **in the fragment**
    (`/page#<token>`), never the path or query (paths are logged). The token is never stored,
    logged or put in `last_error`; the stored body has the link redacted.
11. **Logging:** event names only (`email_sent`, `email_handoff_failed`). Never a recipient, subject,
    body, token or flow URL. Build `last_error` from the exception type and status, never `str(exc)`.
12. **Copy carries no business detail** (no names, amounts or ids): the link leads to the record,
    which enforces sign-in.

## 4. Testing without mailing real people

| | Test mode | Dev redirect (environment `dev`) |
|---|---|---|
| What it does | **Filters**: only mail whose real recipient is on the list is sent; the rest is `suppressed` before any transport | **Redirects**: every message goes to the dev recipient, subject prefixed `[DEV to <real recipient>]` |
| Outbox row | real recipient, `suppressed` or `sent` | keeps the real recipient; the per-recipient cap counts the real one |
| Use it for | Forge before sign-off, with real recipients set up | one tester walking a flow through every recipient from one mailbox |
| On the live Forge app | yes, until sign-off | **no** |

With both on, test mode checks the redirect target (that is who receives it).

**Local stacks:** the relay does not resolve, so SMTP sends fail harmlessly. **Any HTTP-based
transport DOES reach real mailboxes from a laptop**: a developer `.env` with a real flow URL and
test mode off has mailed real people. Keep test mode on locally, or pause sending in the app.

## 5. Operating it

- **Kill switch:** an admin screen, stored **in the database**, read on every send, so it works with
  **no redeploy**. A missing row reads as paused.
- **Per-recipient hourly cap** (e.g. 20, admin-editable): a loop guard.
- Stopped mail is **`held`** (paused or cap), not dropped. Unpausing releases nothing: re-send is one
  row at a time, with a fresh link.
- A restore keeps the switch as it was and turns automatic reminders **off**.
- Outbox statuses: `pending`, `sent`, `failed`, `suppressed`, `held`, `handed_off` (an HTTP
  transport accepted it; not proof of arrival).

## 6. Verifying on Forge

1. Set the settings (section 2), **Rebuild & deploy**, read the API log for a startup refusal.
2. With test mode on and yourself on the list, send the admin test email (rate-limit it) and
   **click its link**: it must open under `/app/<name>`.
3. Check the outbox row: `sent` means the relay accepted DATA. `failed` → read `last_error`.
4. Open an emailed `/page#<token>` link in an InPrivate window: it must still open the page after
   Microsoft sign-in.
5. A real send can only be tested from inside the Forge network, and only with the owner's go.

## 7. When mail does not arrive

| Symptom | Likely cause | Fix |
|---|---|---|
| Service will not start, log names the From setting | From is not at the allowed domain | Use an `@energysolutions.com` address. |
| `503 email_not_configured`, details list host / From | not set, or set but not redeployed | Set; **Rebuild & deploy**. |
| `failed`, `last_error` names a connection/timeout error | wrong host or port, STARTTLS on, or not on Forge's network | `smtp`, `587`, STARTTLS off; test only on Forge. |
| `failed` with 554 | sender domain refused | From at `energysolutions.com`. |
| `suppressed` | test mode on and recipient not listed, or a stale step/spent link | Expected; add the tester or ignore. |
| `held` | kill switch on or hourly cap hit | Unpause in the admin screen, then re-send per row. |
| `sent` but the link 404s | base URL missing `/app/<name>` | Fix the base URL; links already sent stay wrong. |
| `sent` but never arrives | relay or mailbox side | Ask IT with the time sent; the app has no further record. |
