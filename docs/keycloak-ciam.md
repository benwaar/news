# CIAM SSO Learning Plan (Trying out Keycloak)
## Phase 1: OIDC Brokering → Phase 2: SAML Brokering (REQUIRED) → Phase 3: Social Login

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

## 1.5.1 Account linking + duplication controls (REQUIRED)
- Ensure broker maps **email**
- First Login Flow: `review profile`
- Be explicit about Trust Email

## 1.5.2 Claims & token design (REQUIRED)
- Add mappers:
  - `email`
  - `preferred_username`
  - (optional) `groups` / `roles`

## 1.5.3 Authorization baseline (REQUIRED)
- Create role: `news:admin` (or similar)
- Protect at least one API endpoint

## 1.5.4 MFA + step-up (OPTIONAL, NICE-TO-HAVE)
- Enable OTP in `portal`
- Optionally require it only for admin users

## 1.5.5 Self-service lifecycle (OPTIONAL, NICE-TO-HAVE)
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
  
✅ news → portal login → back to news, no prompt on revisit

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

# PHASE 3 — SOCIAL LOGIN (PORTAL REALM)
## Goal
Aggregate social IdPs in `portal`, then broker users into `news` exactly as before.

---

## 10. ADD SOCIAL IDENTITY PROVIDER TO PORTAL (REQUIRED)
Pick **one** to start (GitHub easiest; Google also common).

- Realm: `portal`
- Identity Providers → Add (GitHub / Google / etc.)
- Register Keycloak redirect URI with the provider
- Request scopes that return **email**
- Map:
  - email
  - firstName
  - lastName

---

## 11. ACCOUNT LINKING RULES FOR SOCIAL (REQUIRED)
- Decide linking strategy:
  - link by verified email (typical CIAM)
- Keep First Login Flow: `review profile`

✅ Test:
- Local user + social user with same email
- Confirm expected linking behavior

---

## 12. END-TO-END SOCIAL → SAML TEST (REQUIRED)
- Visit NEWS UI
- Redirect to PORTAL
- Choose social login
- Authenticate at provider
- Return to NEWS UI
- NEWS realm issues access token

✅ Social → Portal → SAML → News confirmed

---

## OPTIONAL SOCIAL HARDENING (NICE-TO-HAVE)
- Domain allowlist (B2B-style)
- Disable local registration, keep social-only
- Require MFA after social login for privileged roles

---

## EXPECTED GOTCHAS (NORMAL)
- Some providers don’t return email without extra scopes
- Email may be unverified (provider-dependent)
- Logout across social + brokered SAML can be inconsistent

---

## SUCCESS CHECKLIST
- [ ] News auto-redirects to portal (optional)
- [ ] Single login works across reloads
- [ ] Same user reused (no duplicates)
- [ ] News realm issues its own access token and API validates it
- [ ] Roles/scopes enforced on at least one API endpoint
- [ ] SAML broker flow works end-to-end
- [ ] Social login works through portal into news
