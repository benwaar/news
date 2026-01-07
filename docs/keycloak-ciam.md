# CIAM SSO Learning Plan (Trying out Keycloak)
## Phase 1: OIDC Brokering → Phase 2: SAML Brokering (REQUIRED)

---

## Assumptions
- Keycloak running locally (e.g. http://localhost:8080)
- Two realms already exist:
  - `portal` = primary / home realm
  - `news` = relying realm
- Two UIs:
  - Portal UI
  - News UI

---

# PHASE 0 — BASELINE (DO THIS ONCE)
## Goal
Make sure each UI is a proper OIDC client and you can validate tokens locally.

### 0.1 Create OIDC clients for the UIs (REQUIRED)
In **each realm**, create a client for the UI that belongs to it.

- Realm: `portal`
  - Client ID: `portal-ui`
  - Type: OIDC
  - Public client: ON (typical for SPA)
  - Standard flow: ON
  - PKCE: S256 required (if available in your version)
  - Redirect URIs: `http://localhost:<portal-ui-port>/*`
  - Web Origins: `http://localhost:<portal-ui-port>`

- Realm: `news`
  - Client ID: `news-ui`
  - Same settings, with `http://localhost:<news-ui-port>/*`

### 0.2 API client + JWT validation (REQUIRED)
In realm `news` (and/or `portal` if it has APIs):
- Create client: `news-api`
- Type: OIDC
- Access type: bearer-only (or confidential + no login if bearer-only not available)
- Your API validates:
  - issuer = `http://localhost:8080/realms/news`
  - audience = `news-api` (or whatever you set)
  - signature + exp

---

# PHASE 1 — OIDC REALM-TO-REALM BROKERING (FAST PROOF)
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
  - `http://localhost:8080/realms/news/broker/*`
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
- Issuer: `http://localhost:8080/realms/portal`
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

# PHASE 1.5 — CIAM “APP FUNDAMENTALS” (ADD ON TOP)  
*(These make it feel like real CIAM. Marked required vs optional.)*

## 1.5.1 Account linking + duplication controls (REQUIRED)
Goal: don’t create a new user every time the broker is used.

- In `news` realm:
  - Ensure the broker maps **email** and sets it as a user attribute
  - First Login Flow: `review profile` (already set)
  - Ensure “Trust Email” only if you’re comfortable for the test; otherwise map + verify

✅ Test: login twice via broker → same user is reused.

## 1.5.2 Claims & token design (REQUIRED)
Goal: see what claims you get and intentionally add a few.

- In `news` realm:
  - Add protocol mappers to `news-ui` / `news-api`:
    - `email` claim
    - `preferred_username`
    - (optional) `groups` or `roles` claim

✅ Test: decode access token and ID token and confirm claims appear where expected.

## 1.5.3 Authorization baseline (REQUIRED)
Goal: separate “logged in” from “allowed to do X”.

- In `news` realm:
  - Create a role: `news:admin` (or `editor`)
  - Assign it to a test user
- In your API:
  - Protect one endpoint with role/scope checks

✅ Test: normal user fails, admin succeeds.

## 1.5.4 MFA + step-up (OPTIONAL, NICE-TO-HAVE)
Goal: learn a key CIAM security pattern.

- In `portal` realm:
  - Enable OTP (TOTP) required for a test user (or conditional flow if you want to go deeper)
- Optional: require MFA only for “admin” users or only for certain actions.

✅ Test: broker login triggers MFA at portal, then returns to news.

## 1.5.5 Self-service lifecycle (OPTIONAL, NICE-TO-HAVE)
Goal: common CIAM flows users expect.

- In `portal` realm:
  - enable/verify:
    - forgot password
    - email verification (if you have local SMTP / mailhog)
    - required actions (update profile)

---

# PHASE 2 — SWITCH BROKER TO SAML (REQUIRED)
## Goal
Replace OIDC broker with SAML while keeping behavior identical.

---

## 5. NEWS REALM — CREATE SAML IDP (SP METADATA) (REQUIRED)
- Realm: `news`
- Identity Providers → Add → SAML v2.0
- Alias: `portal-saml`
- Click **Import config from SP metadata** (or save empty first)

### Copy these values AFTER save (REQUIRED)
- Entity ID
- ACS URL
These define the NEWS realm as a SAML Service Provider.

---

## 6. PORTAL REALM — CREATE SAML CLIENT (IdP SIDE) (REQUIRED)
- Realm: `portal`
- Clients → Create
- Client type: SAML
- Client ID: (Entity ID from news realm)
- Name: `news-saml-broker`

### Settings (REQUIRED)
- Valid Redirect URIs: ACS URL from news realm
- NameID Format: email
- Force NameID format: ON
- Sign Assertions: ON
- Sign Documents: OFF (simpler locally)
- Client Signature Required: OFF (can turn ON later)

### Mappers (REQUIRED)
Add mappers:
- email → email
- firstName → given_name
- lastName → family_name

Save.

---

## 7. NEWS REALM — IMPORT PORTAL METADATA (REQUIRED)
- Back to `portal-saml` IdP in news realm
- Import IdP metadata from portal realm SAML client
- Set:
  - Trust Email: ON (local testing)
  - First Login Flow: review profile
  - Want AuthnRequests Signed: OFF (initially)
  - Validate Signatures: ON (once keys are correct)

Save.

---

## 8. SWITCH REDIRECTOR TO SAML (REQUIRED IF USING REDIRECTOR)
- Update Identity Provider Redirector
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

✅ SAML brokering confirmed

---

# PHASE 2.5 — SAML HARDENING + PARITY CHECKS
## Goal
Make sure SAML behaves like OIDC did (and learn what differs).

## 2.5.1 Attribute mapping parity (REQUIRED)
- Ensure email + name attributes arrive from SAML and map correctly in `news`.

✅ Test: same user reused; profile fields populated.

## 2.5.2 Signing & validation tightening (OPTIONAL, NICE-TO-HAVE)
- Turn on AuthnRequest signing (news → portal)
- Require client signature (portal side)
- Confirm signature validation errors are understandable

✅ Test: break certs intentionally and confirm failure modes.

## 2.5.3 Logout behavior learning (OPTIONAL, NICE-TO-HAVE)
- Test front-channel logout from news and portal
- Observe what propagates and what doesn’t (document it)

---

## EXPECTED GOTCHAS (NORMAL)
- Logout may not propagate cleanly (especially brokered + SAML)
- Duplicate users if email mapping is wrong
- Tokens are issued by NEWS realm (not portal)
- “SSO across realms” happens via brokering, not shared realm cookies

---

## SUCCESS CHECKLIST
- [ ] News auto-redirects to portal (optional if you prefer an IdP button)
- [ ] Single login works across reloads
- [ ] Same user reused (no duplicates)
- [ ] News realm issues its own access token and API validates it
- [ ] Roles/scopes enforced on at least one API endpoint
- [ ] SAML broker flow works end-to-end (required)
