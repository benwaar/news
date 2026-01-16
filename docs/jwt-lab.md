# JWT Starter Lab — Browser Tokens (JS + Angular)

## Table of Contents

- [JWT Starter Lab — Browser Tokens (JS + Angular)](#jwt-starter-lab--browser-tokens-js--angular)
  - [Table of Contents](#table-of-contents)
  - [Goal](#goal)
    - [Dev URLs (HTTPS)](#dev-urls-https)
  - [Assumptions](#assumptions)
  - [Vocabulary (Fast)](#vocabulary-fast)
  - [What You Should Measure](#what-you-should-measure)
  - [Threat Model (Browser Reality)](#threat-model-browser-reality)
  - [Token Types and Lifetimes](#token-types-and-lifetimes)
  - [Refresh Strategies](#refresh-strategies)
    - [A) Refresh Token in Secure HttpOnly Cookie](#a-refresh-token-in-secure-httponly-cookie)
    - [B) Refresh Token in JS Storage](#b-refresh-token-in-js-storage)
    - [C) No Refresh Token (Re-auth Only)](#c-no-refresh-token-re-auth-only)
  - [Storage Options (Tradeoffs)](#storage-options-tradeoffs)
  - [Idle vs Expiration vs Session](#idle-vs-expiration-vs-session)
  - [Angular Implementation Notes](#angular-implementation-notes)
    - [HTTP Interceptor: attach access token](#http-interceptor-attach-access-token)
    - [HTTP Interceptor: 401 → refresh → retry](#http-interceptor-401--refresh--retry)
    - [Route Guards and “auth state”](#route-guards-and-auth-state)
    - [Multi-tab sync](#multi-tab-sync)
  - [Keycloak Notes (If You Use It)](#keycloak-notes-if-you-use-it)
  - [JWT Validation and Debugging](#jwt-validation-and-debugging)
  - [Common Failure Modes](#common-failure-modes)
  - [Practical Experiments (Do These)](#practical-experiments-do-these)
  - [Checklists](#checklists)
    - [Dev Checklist](#dev-checklist)
    - [Prod Checklist (Baseline)](#prod-checklist-baseline)
  - [Resources](#resources)
  - [Glossary](#glossary)

---

## Goal
Experiment with JWT access tokens in **browser apps** (plain JS + Angular):
- Refresh flows
- Idle vs expiration behavior
- Security properties and tradeoffs in real front-end code
- Failure modes (multi-tab, race conditions, token replay, XSS)
- libraries to experiment with
  - **oidc-client-ts** 
   Simplest way to learn the OIDC Code+PKCE principles
  - **angular-auth-oidc-client**
   Opinionated OIDC-first Angular library with higher-level services, guards, and built-in flows for modern Code+PKCE.
   10.0.15 (ang 15) - 18 in 18
  - **angular-oauth2-oidc**
   Flexible, lower-level OAuth2/OIDC toolkit for Angular; you compose behavior with OAuthService and config.

### Dev URLs (HTTPS)
- Keycloak Admin: https://localhost:8443/admin
- News UI: https://localhost
- Portal UI: https://localhost:4443
- API Health: https://localhost/api/healthz
- RSS Health: https://localhost/mcp/healthz


---

## Assumptions
- Browser-only client (SPA): **no secrets in the browser**
- You can call an API that requires `Authorization: Bearer <access_token>`
- You can run locally over HTTPS (recommended), or accept dev-only relaxations

Optional (nice):
- Keycloak / OIDC provider available
- A demo API endpoint that returns 401/403 properly

---

## Vocabulary (Fast)
- **JWT**: a signed token containing claims (header + payload + signature).
- **Access token**: short-lived token sent to APIs.
- **Refresh token**: longer-lived credential used to obtain new access tokens.
- **ID token**: identity assertion for the client (not for APIs).
- **`exp`**: expiration time in seconds since epoch.
- **`aud`**: intended recipient (the API). APIs should validate this.
- **`iss`**: issuer (the auth server/realm URL).
- **PKCE**: protects browser code flow; required for public clients.

---

## What You Should Measure
- Average time until forced re-login (with and without refresh)
- How often refresh occurs and why (timer vs 401-driven)
- Multi-tab behavior (do tabs fight over refresh?)
- How logout propagates (per tab, across tabs, and server-side)
- What happens when system clock is skewed (client clock tolerance)
- UX: do users get “random logouts” or clear prompts?

---

## Threat Model (Browser Reality)
The browser is hostile by default. Your biggest risks:
- **XSS** (token theft if tokens are accessible to JS)
- **Token replay** (stolen access token reused until exp)
- **CSRF** (mainly relevant when you rely on cookies for auth)
- **Malicious extensions / compromised device** (hard to defend against)
- **Leaky logs** (tokens printed to console / stored in error tooling)

Rules of thumb:
- If your access token is readable by JS, **assume XSS = account takeover**.
- If you use cookies, mitigate **CSRF** and make sure you understand CORS.
- Prefer shortest workable token lifetime for access tokens.

---

## Token Types and Lifetimes
Typical starting point (tune later):
- Access token: **5–15 minutes**
- Refresh token: **hours–days** (depending on device trust + UX)
- Session idle timeout: **15–60 minutes** (if you enforce “idle logout”)
- Max session lifetime: **8–24 hours** (forced re-auth eventually)

Claims to care about:
- `iss`, `aud`, `exp`, `iat`
- `sub` (stable user id)
- roles/permissions (often `realm_access.roles` or `groups`)
- an “auth_time” or equivalent if you do step-up auth

---

## Refresh Strategies

### A) Refresh Token in Secure HttpOnly Cookie
**Best baseline when you can involve an API/BFF** (even minimal):
- Refresh token stored in **HttpOnly + Secure + SameSite** cookie
- Browser JS cannot read it (reduces XSS token theft)
- Refresh endpoint uses the cookie, returns a new access token
- Access token can be in memory (or short-term storage if needed)

Tradeoffs:
- Requires server endpoint (BFF or lightweight refresh proxy)
- Must design for CSRF if cookie is sent automatically

Good for:
- Real production SPA security posture

### B) Refresh Token in JS Storage
Simplest pure SPA approach:
- Keep refresh token in memory/sessionStorage/localStorage
- Call token endpoint from SPA

Tradeoffs:
- XSS can steal refresh token = long-lived compromise
- localStorage persists across sessions; sessionStorage per-tab session

Good for:
- Dev labs, prototypes, low-risk apps, or when you accept the tradeoff

### C) No Refresh Token (Re-auth Only)
Simplest and safest in pure browser sense:
- Access tokens expire quickly
- App re-auths when needed

Tradeoffs:
- More frequent login prompts unless you rely on SSO session at IdP
- Still possible to do “silent re-auth” (if IdP supports) but complexity rises

Good for:
- High-security contexts, or when refresh is too risky/complex

---

## Storage Options (Tradeoffs)
- **In-memory (recommended for access token)**:
  - ✅ best against token theft via persistence
  - ❌ tab refresh loses token unless you rehydrate
- **sessionStorage**:
  - ✅ survives reload in the same tab session
  - ❌ readable by JS → XSS risk
- **localStorage**:
  - ✅ persists across browser restarts
  - ❌ highest risk for token theft; commonly discouraged for tokens
- **HttpOnly cookies**:
  - ✅ not readable by JS (mitigates XSS token theft)
  - ❌ CSRF considerations; CORS and SameSite need care

Rule of thumb:
- Access token: **in-memory** if possible
- Refresh token: **HttpOnly cookie** if you can, otherwise accept risk knowingly

---

## Idle vs Expiration vs Session
These are different timers that often get mixed up:

- **Access token expiration (`exp`)**: cryptographic validity ends.
- **User session idle**: “logged out if inactive” (UX/security policy).
- **SSO session**: IdP’s session cookie; may silently re-auth.
- **Refresh token idle/max**: server-side policies may expire refresh tokens.

If you want “idle logout” in the SPA:
- Track user activity (mouse/keyboard/visibility)
- When idle threshold reached:
  - clear local auth state
  - optionally call logout endpoint
  - show “session expired due to inactivity” message

---

## Angular Implementation Notes

### HTTP Interceptor: attach access token
- Add `Authorization: Bearer ...` to API calls
- Do NOT attach tokens to third-party domains
- Keep a strict allowlist of API base URLs

### HTTP Interceptor: 401 → refresh → retry
Core behaviors you should implement:
- Only one refresh in-flight at a time
- Queue concurrent requests while refreshing
- If refresh fails: clear auth state, redirect to login

Avoid:
- Infinite loops (refresh call itself returns 401 → interceptor retries)
- Refresh storms (every request triggers refresh)

### Route Guards and “auth state”
- Guard protected routes by “authenticated and token not expired”
- If expired: attempt refresh OR force login depending on strategy
- Keep a single source of truth (AuthService state)

### Multi-tab sync
Decide:
- Per-tab sessions (simpler) OR shared sessions (better UX)
If shared:
- Use `BroadcastChannel` (preferred) or `storage` events
- Ensure refresh is coordinated so tabs don’t race

---

## Keycloak Notes (If You Use It)
- SPA client should be **public** with **PKCE S256 required**
- Your API should validate:
  - signature (JWKS)
  - `iss` matches realm
  - `aud` contains API client id
  - `exp` not expired
- Consider adding:
  - audience mapper if your API expects `aud=<api-client>`

---

## JWT Validation and Debugging
What to inspect:
- Decode payload (never trust decode-only for validation)
- Check:
  - `exp` and clock skew
  - `aud` includes your API
  - roles/claims are present as expected
- Log safely:
  - never print full tokens in production logs
  - redact tokens in error tools

Useful debugging patterns:
- Show “token expires in X seconds” in dev UI
- Add a dev-only page that prints selected claims (not the full token)

---

## Common Failure Modes
- **401 loop**: interceptor retries forever
- **Refresh storm**: multiple requests cause multiple refresh calls
- **“works in one tab, fails in another”**: state not synced
- **CORS confusion**: cookies not sent, or preflight blocks auth
- **aud mismatch**: API expects `aud=api` but token doesn’t include it
- **Clock skew**: token “expired” due to local clock drift
- **Logout doesn’t log out**: local state cleared but IdP session remains (SSO)

---

## Practical Experiments (Do These)
1) **Short access token** (60–120s):
   - Observe refresh frequency
   - Verify interceptor doesn’t storm

2) **Simulate refresh failure**:
   - revoke refresh token or break endpoint
   - ensure app cleanly routes to login

3) **Multi-tab race test**:
   - open 3 tabs
   - force token expiration
   - watch that only one refresh happens

4) **XSS thought experiment (dev)**:
   - confirm whether tokens are readable via DevTools storage
   - decide if your strategy is acceptable

5) **Idle logout UX**:
   - set idle to 1 minute
   - verify you clear state and show a message
   - verify you don’t keep silently refreshing while “idle”

6) **Audience validation**:
   - intentionally use a token with wrong `aud` against API
   - ensure API rejects reliably

---

## Checklists

### Dev Checklist
- [ ] Access token expiry displayed somewhere (dev only)
- [ ] Single refresh-in-flight guard is implemented
- [ ] Refresh call is excluded from interceptor recursion
- [ ] Errors do not print full token
- [ ] Multi-tab behavior chosen and tested

### Prod Checklist (Baseline)
- [ ] Prefer refresh token in HttpOnly cookie (if feasible)
- [ ] CSP baseline enabled (reduce XSS risk)
- [ ] Strict API origin allowlist for attaching Authorization header
- [ ] Logout clears SPA state AND invalidates server session as appropriate
- [ ] CSRF protections in place if you rely on cookies
- [ ] Token lifetimes are short and justified
- [ ] API validates `iss`, `aud`, signature, `exp` (no decode-only)

---

## Resources
- OAuth 2.0 for Browser-Based Apps (IETF BCP) — search: “OAuth browser-based apps BCP”
- OWASP Cheat Sheets:
  - XSS Prevention
  - CSRF Prevention
  - JWT Security Cheat Sheet
- Angular HttpInterceptor docs
- Your IdP docs (Keycloak: clients, mappers, token lifetimes, sessions)

---

## Glossary

- Access token: Short-lived bearer token sent to APIs (e.g., `news-api`). Must validate signature, `iss`, `aud`, and `exp`.
- Audience (`aud`): Intended recipient(s) of the token (e.g., `news-api`). APIs should reject tokens with wrong `aud`.
- Backend-for-Frontend (BFF): Small server tailored to a SPA that owns OAuth/OIDC exchanges and refresh; keeps refresh tokens in HttpOnly+Secure+SameSite cookies and issues short-lived access tokens to the browser (or proxies calls server-side). Reduces XSS token theft risk.
- BroadcastChannel: Browser API to sync auth state across tabs and coordinate refresh.
- Clock skew: Time differences cause premature “expired” tokens; allow small tolerance.
- CSRF: Relevant when relying on cookies; protect state-changing endpoints with CSRF tokens or SameSite settings.
- HttpOnly cookie: Cookie not readable by JS; use for refresh token with `Secure` and `SameSite` configured correctly.
- ID token: Identity assertion for the client (not for APIs); useful for profile and UI state.
- In-memory storage: Keep access token only in memory for less persistence risk; expect token loss on reload.
- Interceptor (Angular): Attaches `Authorization: Bearer ...` only to allowlisted API origins and coordinates 401→refresh→retry.
- Issuer (`iss`): URL of the realm that issued the token (e.g., `https://localhost:8443/realms/news`).
- JWKS: JSON Web Key Set published by the issuer; used to verify JWT signatures (e.g., Keycloak `/protocol/openid-connect/certs`).
- JWT: JSON Web Token with header (`alg`,`kid`), payload (claims), and signature; verify with the issuer’s JWKS.
- PKCE: Proof Key for Code Exchange; protects SPA code flow using `code_verifier`/`code_challenge` (S256).
- Refresh token: Longer-lived credential used to obtain new access tokens; ideally stored in HttpOnly cookie by a BFF, not readable by JS.
- Route Guard (Angular): Protects routes based on auth state and token expiration.
- Silent re-auth (`prompt=none`): Re-auth in the background if IdP session is valid; requires proper IdP/config and careful iframe/CORS handling.
- Single refresh in-flight: Guard to ensure only one refresh happens at a time; queue requests while refreshing.
- SSO session: IdP session cookie; can enable silent re-auth even without a refresh token.
- Token replay: Stolen access token reused until `exp`; mitigate with short lifetimes and server checks.


