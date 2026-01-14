# Identity & Authentication UX - CIAM SSO Lab (Trying out Keycloak)

The first part of this project explores **Identity & Authentication UX** from a hands-on, integration-focused perspective.  
It focuses on how real users experience login, SSO, and federation flows — and how those UX decisions intersect with security, protocols, and platform constraints.

Built as a practical CIAM lab using **Keycloak**, this repo walks through OIDC & SAML login patterns as they are commonly implemented in modern web applications, with an emphasis on **secure-by-design UX** rather than theory.

### Topics / Keywords
Identity UX, Authentication UX, Secure UX, CIAM, SSO  
OIDC, OAuth2, PKCE, SAML, Federation  
MFA, WebAuthn, Passkeys, Passwordless, Step-up  
Account Linking, Social Login, Role-based Auth  
SPA Security, Audience (aud), JWT, JWKS  
Keycloak, Quarkus, Docker Compose

## Phase 1: OIDC Brokering → Phase 2: SAML Brokering

---

## Assumptions
- Keycloak running locally (e.g. https://localhost:8443)
- Two realms already exist:
  - `portal` = primary / home realm
  - `news` = relying realm
- Two UIs:
  - Portal UI (https://localhost:4443)
  - News UI (https://localhost)

---

## Quick Start (Local)

1) Bootstrap core (Keycloak + DB + services):

```bash
bash tools/bootstrap.sh
```

2) Configure brokering (run manually after bootstrap):

```bash
# OIDC broker + IdP
bash tools/configure-phase1-oidc.sh
# Optional: auto-redirect to IdP
bash tools/configure-phase1-redirector.sh
# Trust email, map claims, create news:admin
bash tools/configure-phase1-5.sh
```

3) Verify:
- Admin: https://localhost:8443/admin (admin/admin)
- News UI: https://localhost (expect portal login or auto-redirect)
- Portal UI: https://localhost:4443
- Portal Account Console: https://localhost:8443/realms/portal/account (Security → Authenticator)
- API health: http://localhost:9000/healthz | RSS: http://localhost:9002/healthz

Note: bootstrap intentionally does not run Phase 1/1.5; execute them as above.

### Troubleshooting: Account Console spinner (dev)
- Use a fresh private window and ensure you trust the local CA cert.
- Make sure you are using HTTPS: https://localhost:8443/realms/portal/account
- Quick fix (recommended): run [tools/fix-account-console-spinner.sh](tools/fix-account-console-spinner.sh)

```bash
bash tools/fix-account-console-spinner.sh
```

What the fixer does (minimal):
- Ensures `account-console` access tokens include `aud=account` by adding an OIDC audience mapper.

Notes:
- Seed users already include `default-roles-portal`/`default-roles-news`, which grant Account Console permissions.
- No origin/redirect/URL relaxations are applied; those are unnecessary for the validated fix path.

---

# PHASE 0 ✅ — BASELINE
## Goal
Make sure each UI is a proper OIDC client and you can validate tokens locally.

### 0.1 Create OIDC clients for the UIs
In **each realm**, create a client for the UI that belongs to it.

- Realm: `portal`
  - Client ID: `portal-web` (preconfigured)
  - Type: OIDC
  - Public client: ON (typical for SPA)
  - Standard flow: ON
  - PKCE: S256 required (preconfigured)
  - Redirect URIs: `https://localhost:4443/*`
  - Web Origins: `https://localhost:4443`

- Realm: `news`
  - Client ID: `news-web` (preconfigured)
  - Same settings (preconfigured), with `https://localhost/*`

### 0.2 API client + JWT validation
In realm `news`:
- Create client: `news-api`
- Type: OIDC
- Access type: bearer-only (preconfigured)
- Your API validates:
  - issuer = `https://localhost:8443/realms/news`
  - audience = `news-api` (or whatever you set)
  - signature + exp
  - Test endpoint: `GET https://localhost/api/token/validate` returns a JSON report of these checks
  - Tip: Use `tools/test-news-api.sh` to obtain a PKCE token for `news-web` and call the protected API.

### 0.3 Session & Storage Guidance `[✓]`
- SPA clients are public: no client secrets are embedded in the browser.
- Token storage (dev): UI stores `access_token` in sessionStorage for convenience. Production: prefer in-memory storage or backend-managed `httpOnly` secure cookies to reduce XSS risk.
- Idle/expiration: Configure Keycloak realm session timeouts (SSO Session Idle/Max). UI detects token `exp` and prompts re-login when expired.
- Confidential clients: The broker client `news-broker` in `portal` is confidential; its secret is stored in Keycloak only and not exposed to UIs.

---

# PHASE 1 ✅ — OIDC REALM-TO-REALM BROKERING (FAST PROOF)
## Goal
User hits `news` → redirected to `portal` login → authenticated → returned to `news` → `news` issues its own tokens.

---

## 1. PORTAL REALM (acts as OIDC IdP)

### Create OIDC Client (REQUIRED)
- Realm: `portal`
- Clients → Create
- Client ID: `news-broker`
- Client type: OpenID Connect
- Access type: Confidential
- Standard flow: ON
- Direct access grants: OFF
- Root URL: (leave empty)

### Redirect URIs (REQUIRED)
- Temporarily allow (for local testing):
  - `https://localhost:8443/realms/news/broker/*`
- Save

### Copy (REQUIRED)
- Client ID
- Client Secret

---

## 2. NEWS REALM (acts as OIDC Broker)

### Add Identity Provider (REQUIRED)
- Realm: `news`
- Identity Providers → Add → OpenID Connect v1.0

#### Settings
- Alias: `portal-oidc`
- Issuer: `https://localhost:8443/realms/portal`
- Client ID: `news-broker`
- Client Secret: (from portal realm)
- Default Scopes: `openid profile email`
- First Login Flow: `review profile`
- Store Tokens: OFF
- Trust Email: ON (for local testing)

Save.

---

## 3. AUTO-REDIRECT (OPTIONAL, NICE-TO-HAVE)
### Identity Provider Redirector
- Authentication → Flows
- Copy `browser` flow → name it `browser-with-idp`
- In copied flow:
  - Add execution: **Identity Provider Redirector**
  - Set default IdP: `portal-oidc`
- Bind this flow as:
  - Realm Settings → Login → Browser Flow = `browser-with-idp`

Configured via script:
- Run [tools/configure-phase1-redirector.sh](tools/configure-phase1-redirector.sh) to copy the flow, set `defaultProvider=portal-oidc`, and bind `browser-with-idp` as the Browser Flow.
- Revert (optional):
  - Set Browser Flow back to `browser` if you want to disable auto-redirect.

---

## 4. TEST OIDC SSO (REQUIRED)
- Open fresh browser session
- Visit NEWS UI
- Expect:
  - Redirect to PORTAL login
  - Login once
  - Return to NEWS UI
- Visit PORTAL UI:
  - Already logged in

✅ OIDC brokering confirmed

---

## Scripts Cheat Sheet

- tools/bootstrap.sh: Build/start infra, import realms, start services, health checks
- tools/drop.sh: Tear down stack, remove images/volumes (full reset)
- tools/configure-realm.sh: Import `news` realm (used by bootstrap)
- tools/configure-phase1-oidc.sh: Create `news-broker` in `portal`, add `portal-oidc` IdP in `news`
- tools/configure-phase1-redirector.sh: Copy `browser` → `browser-with-idp`, set redirector, bind flow
- tools/configure-phase1-5.sh: Trust email, first-broker-login, mappers, create `news:admin`
- tools/check-health.sh: Endpoint checks for Keycloak/UI/API/MCP
- tools/test-news-api.sh: Obtain token and call API helpers (dev convenience)

---
Dev backchannel note (local HTTPS):
- Front-channel stays HTTPS for the browser (redirects and login at `https://localhost:8443`).
- For the broker’s backchannel token exchange, we use Keycloak’s internal HTTP endpoint to avoid mkcert trust issues inside the container:
  - authorizationUrl: `https://localhost:8443/realms/portal/protocol/openid-connect/auth`
  - tokenUrl: `http://localhost:8080/realms/portal/protocol/openid-connect/token`
  - useDiscovery: `true`, useJwksUrl: `true`, disableTrustManager: `true` (dev-only)

Configured via script:
- We apply this automatically with [tools/configure-phase1-oidc.sh](tools/configure-phase1-oidc.sh). It creates `news-broker` in `portal` and adds the `portal-oidc` IdP in `news` with the above settings.

Manual steps parity (if configuring in the console):
- Portal realm → Clients → `news-broker` (confidential), Redirect URIs: `https://localhost:8443/realms/news/broker/*`.
- News realm → Identity Providers → OpenID Connect:
  - Alias: `portal-oidc`
  - Issuer: `https://localhost:8443/realms/portal`
  - Client ID/Secret: from `news-broker`
  - Default Scopes: `openid profile email`
  - For local dev only: set Authorization URL (above), Token URL to the internal HTTP (above), enable Discovery + JWKS, and consider `disableTrustManager=true`.
  - Production: import the mkcert (or real) CA into Keycloak’s truststore, keep HTTPS for tokenUrl, and remove `disableTrustManager`.
---

# PHASE 1.5 ✅ — CIAM “APP FUNDAMENTALS”

## 1.5.1 Account linking + duplication controls
- Ensure broker maps **email**
- First Login Flow: `review profile`
- Be explicit about Trust Email

## 1.5.2 Claims & token design
- Add mappers:
  - `email`
  - `preferred_username`
  - (optional) `groups` / `roles`

## 1.5.3 Authorization baseline 
- Create role: `news:admin` (or similar)
- Protect at least one API endpoint
  - In News API, [services/news-api/src/index.js](services/news-api/src/index.js) exposes `/api/admin/ping` which requires realm role `news:admin`.

Configured via script:
- Run [tools/configure-phase1-5.sh](tools/configure-phase1-5.sh) to set `trustEmail=true`, bind First Login Flow `review profile`, add an IdP email mapper, and create realm role `news:admin` in `news`.

Manual steps parity (if configuring in the console):
- Realm: `news` → Identity Providers → `portal-oidc`
  - Trust Email: ON
  - Default Scopes: include `openid profile email`
  - First Login Flow: `first broker login` (contains “Review Profile”)
  - Mappers:
    - Email: add “User Email” IdP mapper (IdP email → user email)
    - Username: add “Identity Provider Username” mapper with `Claim=preferred_username`
    - Optional: add groups/roles mappers if you need those claims
- Realm Roles → Create: `news:admin`
- Assign to user: Users → select user → Role Mappings → Assign `news:admin`
- Validate API protection: `GET https://localhost/api/admin/ping` returns 200 only when token has realm role `news:admin`


---

# PHASE 1.6 ✅ — CIAM “APP FUNDAMENTALS” (NICE-TO-HAVE)

Starting again from Phase 1

## 1.6.1 Self-service lifecycle
- SMTP (dev): Mailpit configured for outbound email in `portal`.
- Login with email: Enabled (`loginWithEmailAllowed=true`) in `portal` (test user created).
- Forgot password: Enabled (`resetPasswordAllowed=true`) in `portal`.
- Email verification: Not enabled (optional).
- Required actions (update profile): Not enabled (optional).

Configured via script:
- [tools/configure-phase1.6a-enable-email.sh](tools/configure-phase1.6a-enable-email.sh) — set SMTP (Mailpit) for target realms.
- [tools/configure-phase1.6b-login-with-email.sh](tools/configure-phase1.6b-login-with-email.sh) — enable login with email; optional `--create-test-user`.
- [tools/configure-phase1.6c-reset-password.sh](tools/configure-phase1.6c-reset-password.sh) — enable self-service reset password.

## 1.6.2 MFA + step-up 
- OTP policy is present in `portal`.
- Enable OTP and optionally scope enforcement to admin users.

Configured via script:
- [tools/configure-phase1.6d-mfa-stepup.sh](tools/configure-phase1.6d-mfa-stepup.sh) — enable OTP policy and enforcement
  - Enforce all users: `bash tools/configure-phase1.6d-mfa-stepup.sh` (sets default required action CONFIGURE_TOTP for everyone)
  - Admin-only step-up: `bash tools/configure-phase1.6d-mfa-stepup.sh --admin-only` (keeps default action off; leverages existing Conditional OTP so only targeted users are challenged)
  - Custom role: `bash tools/configure-phase1.6d-mfa-stepup.sh --role <realm-role>`
  - Seed existing users (role mode): add `--seed-existing` to mark users with the role to configure OTP at next login
- Optional helper (quick test):
  - [tools/grant-portal-admin.sh](tools/grant-portal-admin.sh) — grant `admin` to `portal` user, then seed:
    - `bash tools/grant-portal-admin.sh`
    - `bash tools/configure-phase1.6d-mfa-stepup.sh --admin-only --seed-existing`


---

## 1.6.3 WebAuthn (MFA/Passwordless) — Dev Simulation

- What: Use WebAuthn with platform authenticators (Touch ID/Windows Hello) or a virtual key for local testing.
- Configure (script):

```bash
bash tools/configure-phase1.6e-webauthn.sh
```

- Enroll a key: Open the Account Console → Security → Signing In → Register Security Key.
- Simulate a key (Chrome):
  - Open DevTools → More tools → WebAuthn → Enable virtual authenticator environment
  - Add Virtual Authenticator (Platform or Cross-platform), User verification = required/preferred
  - Register/Authenticate in the Account Console; the virtual key will satisfy prompts
  - If you don’t see “Register Security Key”, enable the virtual authenticator and reload, or rerun the script (it now allows both platform/cross‑platform by setting attachment to “not specified”).

### 1.6.4 WebAuthn Passwordless — Browser Flow

- Switch Browser flow to passwordless (RP ID must be `localhost` as configured earlier):

```bash
bash tools/configure-phase1.6f-webauthn-passwordless.sh
```

- Test:
  - Log out and start a new session in Chrome at https://localhost:8443/realms/portal/account
  - The login screen will prompt for a passkey; use your registered platform/cross‑platform key or the virtual authenticator.
- Revert:
  - Restore the default Browser flow:

```bash
docker exec infra-keycloak-dev /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin
docker exec infra-keycloak-dev /opt/keycloak/bin/kcadm.sh update realms/portal -s browserFlow=browser
```

# PHASE 2 — SWITCH BROKER TO SAML (REQUIRED)
## Goal
Replace OIDC broker with SAML while keeping behavior identical.

---

### Scripted Setup (Recommended)
- Run [tools/configure-phase2-saml.sh](tools/configure-phase2-saml.sh) to configure Portal↔News SAML brokering end-to-end.
- What it does:
  - Portal realm: creates/updates a SAML client for News SP with Redirect URIs = News ACS, NameID Format = email, Sign Assertions = ON, and adds `email`, `firstName`, `lastName` mappers.
  - News realm: creates/updates SAML IdP `portal-saml` (Trust Email = ON, First Login Flow = first broker login) and sets both POST/Redirect Single Logout URLs.
  - SLO: configures Logout Service URLs on the Portal SAML client(s) to point to the News broker endpoint.
- Show both flows: ensure the News realm’s Browser Flow is `browser` (no auto-redirect). If you previously enabled the redirector, revert it via Realm Settings → Login.

## 5. NEWS REALM — CREATE SAML IDP (SP METADATA) (REQUIRED)
- Identity Providers → Add → SAML v2.0
- Alias: `portal-saml`
- Save, then copy:
  - Entity ID
  - ACS URL

---

## 6. PORTAL REALM — CREATE SAML CLIENT (IdP SIDE) (REQUIRED)
- Clients → Create → SAML
- Client ID: (Entity ID)
- Valid Redirect URIs: ACS URL
- NameID Format: email
- Sign Assertions: ON
- Mappers:
  - email → email
  - firstName → given_name
  - lastName → family_name

---

## 7. NEWS REALM — IMPORT PORTAL METADATA (REQUIRED)
- Import IdP metadata from portal SAML client
- Trust Email: ON (local testing)
- First Login Flow: review profile
- Want AuthnRequests Signed: OFF (initially)
- Validate Signatures: ON (once keys are correct)

---

## 8. TEST SAML SSO (REQUIRED)
- New browser session
- Visit NEWS UI
- Expect:
  - Redirect to PORTAL login
  - Login once
  - Return to NEWS UI
- Revisit NEWS UI:
  - No login prompt
  
news → portal login → back to news, no prompt on revisit

---

# PHASE 2.5 — SAML HARDENING + PARITY CHECKS
## Goal
Make sure SAML behaves like OIDC did (and learn what differs).

## 2.5.1 Attribute mapping parity (REQUIRED)
- Email + names mapped correctly
- Same user reused

## 2.5.2 Signing & validation tightening (OPTIONAL, NICE-TO-HAVE)
- Sign AuthnRequests
- Require client signatures
- Intentionally break certs and observe errors

## 2.5.3 Logout behavior learning (OPTIONAL, NICE-TO-HAVE)
- Test logout flows
- Document what propagates and what doesn’t

---

## SUCCESS CHECKLIST
- [ ] News auto-redirects to portal (optional)
- [ ] Single login works across reloads
- [ ] Same user reused (no duplicates)
- [ ] News realm issues its own access token and API validates it
- [ ] Roles/scopes enforced on at least one API endpoint
- [ ] SAML broker flow works end-to-end

---

## Token Verification Flow (This Repo)

- Issuer publishes keys (JWKS): Keycloak exposes signing keys at
  - External: https://localhost:8443/realms/news/protocol/openid-connect/certs
  - In-cluster (used by API): http://keycloak:8080/realms/news/protocol/openid-connect/certs
- API verification: [services/news-api/src/index.js](services/news-api/src/index.js) fetches JWKS, selects the key by `kid` from the JWT header, and verifies RS256 signature.
- Critical checks: issuer (`iss` = `https://localhost:8443/realms/news`), audience (`aud` contains `news-api`), expiration (`exp` > now). Small clock tolerance applied.
- Authorization: API reads realm roles from `realm_access.roles`; endpoint `/api/admin/ping` requires realm role `news:admin`.
- Front-channel vs back-channel: Browser redirects/login happen over HTTPS; scripts use internal HTTP for token endpoints only during IdP setup. The API never calls token endpoints—only JWKS for signature verification.
- Common failures: unknown `kid` (stale JWKS cache), wrong `iss`/`aud`, expired token, or missing required role.


### Quick Flow Explanation for Account SPA in Keycloak

1) The browser client completes the OIDC code flow and receives an `access_token` for its client (e.g., `news-web` or `account-console`).
2) The client calls a protected API with `Authorization: Bearer <access_token>`.
3) The API fetches the realm JWKS, verifies the JWT signature and checks:
  - `iss` matches the realm URL, `exp` not expired
  - `aud` contains the API’s identifier (e.g., `news-api` or `account`)
  - required roles/scopes are present (e.g., realm role `news:admin`)
4) If all checks pass, the API returns 200; otherwise it rejects with 401/403.

In Keycloak’s Account Console (SPA), the UI obtains a token as `account-console` but then calls the Account REST API (`account`). That API authorizes by audience, so without `aud=account` those calls fail (spinner with 401/403). The audience mapper adds `account` to `aud`, making the token valid for the API and eliminating the spinner.

---

## RESOURCES

- Identity Brokering (OIDC IdP, mappers): https://www.keycloak.org/docs/latest/server_admin/#_identity_broker
- Authentication Flows (incl. Identity Provider Redirector): https://www.keycloak.org/docs/latest/server_admin/#_authentication-flows
- Protocol Mappers (token claims shaping): https://www.keycloak.org/docs/latest/server_admin/#_protocol-mappers
- Clients (OIDC: public, confidential, bearer-only): https://www.keycloak.org/docs/latest/server_admin/#_clients
- JWKS and token validation (OIDC): https://www.keycloak.org/docs/latest/securing_apps/#_oidc_json_web_keys
- SAML Identity Provider and Clients: https://www.keycloak.org/docs/latest/server_admin/#_saml-identity-provider

## GLOSSARY

- Identity Provider (IdP): The system that authenticates users and issues identities (e.g., realm `portal`).
- Broker (Keycloak): A realm that delegates user login to an external IdP and then issues its own tokens (e.g., realm `news`).
- Realm: A partitioned namespace in Keycloak containing users, clients, roles, and flows.
- Client (OIDC): An application registered in a realm. Public clients (SPAs) use PKCE; confidential clients have a secret (e.g., `news-broker`).
- Bearer-only client: API-style client that never performs browser login, only validates incoming bearer tokens (e.g., `news-api`).
- Mapper (IdP): Transforms attributes from the external IdP into Keycloak user attributes on first login/link (e.g., map `email`, `preferred_username`).
- Mapper (Protocol): Shapes claims in tokens issued to a specific client (add/rename/remove claims in `access_token`/`id_token`).
- Browser Flow: Authentication flow executed for browser-based logins (e.g., `browser`, `browser-with-idp`).
- Binding (Flow): Selecting which flow the realm uses for Browser login (Realm Settings → Login → Browser Flow).
- Identity Provider Redirector: Authenticator step that forwards users directly to a chosen IdP (auto-redirect); configured with `defaultProvider`.
- First Broker Login flow: Flow run on a user’s first brokered login; includes “Review Profile” and account linking.
- Trust Email: Accept IdP-provided email as verified. Useful for dev; assess risk before enabling in prod.
- Default Scope (OIDC): Scopes requested by default (e.g., `openid profile email`) which influence included claims.
- OIDC: Modern auth protocol. Key terms: issuer (`iss`), audience (`aud`), scopes, claims, `access_token`, `id_token`, JWKS, PKCE.
- SAML: XML-based federation protocol. Key terms: IdP, SP (service provider), Entity ID, ACS URL, Assertions, NameID, Attributes, Metadata.
- JWKS: JSON Web Key Set used to publish signing keys so clients can verify token signatures.
- JWT: JSON Web Token carrying signed claims; header has `alg`/`kid`, body includes claims like `iss`, `aud`, `exp`; verified with issuer’s public key from JWKS (e.g., RS256).
- PKCE: Proof Key for Code Exchange; protects public clients (SPAs) during the OAuth2/OIDC code flow.
- Role (Realm vs Client): Realm roles apply across the realm (e.g., `news:admin`); client roles apply only to a specific client.
- Audience (`aud`): Intended recipient(s) of a token (e.g., `news-api`). APIs should verify audience.
- Issuer (`iss`): The URL identifying the token’s issuing realm (e.g., `https://localhost:8443/realms/news`).

