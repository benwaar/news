# Identity & Authentication UX - CIAM SSO Lab (Trying out Keycloak)

The first part of this project explores **Identity & Authentication UX** from a hands-on, integration-focused perspective.  
It focuses on how real users experience login, SSO, and federation flows — and how those UX decisions intersect with security, protocols, and platform constraints.

Built as a practical CIAM lab using **Keycloak**, this repo walks through OIDC, SAML, and social login patterns as they are commonly implemented in modern web applications, with an emphasis on **secure-by-design UX** rather than theory.

### Topics / Keywords
Identity UX, Authentication UX, Secure UX, CIAM, SSO  
OIDC, OAuth2, PKCE, SAML, Federation  
MFA, Account Linking, Social Login  
Frontend Security, AppSec, Web Security  
Keycloak, Identity Integrations

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


---

# PHASE 1.6 — CIAM “APP FUNDAMENTALS” (NICE-TO-HAVE)

## 1.6.1 MFA + step-up
- Enable OTP in `portal`
- Optionally require it only for admin users

## 1.6.2 Self-service lifecycle
- Forgot password
- Email verification
- Required actions (update profile)

---

# PHASE 2 — SWITCH BROKER TO SAML (REQUIRED)
## Goal
Replace OIDC broker with SAML while keeping behavior identical.

---

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

## 8. SWITCH REDIRECTOR TO SAML (REQUIRED IF USING REDIRECTOR)
- Default IdP: `portal-saml`

---

## 9. TEST SAML SSO (REQUIRED)
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

