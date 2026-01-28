
# BFF + HttpOnly + CSRF Lab (Planned)

Goal: Demonstrate how a Backend-for-Frontend issues HttpOnly cookies and defends state-changing requests with CSRF protections, keeping tokens out of JavaScript while preserving SPA UX.

### Planned Realm & UI for Experimentation
- Create a new Keycloak realm (e.g., `bff-lab`) dedicated to this experiment:
  - Add a confidential client for the BFF with `authorization_code` + PKCE enabled.
  - Add a public client for the experimental UI with proper redirect URIs.
  - Configure audience (`aud`) and scopes for `news-api`; optionally enable Token Exchange.
- Scaffold a new experimental UI app (e.g., `services/ui-bff-lab/`) to keep flows isolated:
  - Minimal Angular app with routes to test login, `/me`, and protected API calls via the BFF.
  - Proxy config pointing to the BFF on the same origin to avoid credentialed CORS.
- Compose integration:
  - Add a compose override profile to include the new realm import and the experimental UI+BFF services.
  - Document start commands and verification steps aligned with the exercises above.

## Architecture
- Browser → UI (Angular)
- UI → BFF (Node/Express)
- BFF → IdP (Keycloak) for OAuth/OIDC
- BFF → API (news-api) with server-side `Authorization`

## JWT-Backed APIs (BFF Usage)
- Access tokens (JWT) are obtained and stored on the BFF only. The browser never sees access or refresh tokens.
- The BFF attaches `Authorization: Bearer <access_token>` to upstream requests to `news-api`.
- Token acquisition patterns:
  - User-scoped: During login (Auth Code + PKCE), request audience/scope for `news-api` and store tokens server-side.
  - Token exchange (on-behalf-of): Exchange the user token for a token targeted to `news-api` (Keycloak Token Exchange).
  - Service-scoped: Use client credentials for system calls that do not require user identity.
- Rotation & retries: Refresh server-side before expiry; on `401`, refresh and retry once.
- UI claims: Expose a BFF `/me` endpoint for profile/roles instead of reading tokens client-side.

## Cookie Model
- `session` (HttpOnly, Secure, SameSite=Lax or Strict, Path=/)
- Optional: non-HttpOnly `csrf` token cookie (per-request header echo)
- Access/refresh tokens remain server-side (not readable by JS)

## Exercises
1) Set cookie flags
  - Add `Set-Cookie: session=...; HttpOnly; Secure; SameSite=Lax; Path=/` in BFF responses.
  - Verify in DevTools → Application → Cookies; confirm not readable via `document.cookie`.
2) CSRF defense (double-submit or header token)
  - BFF sets `csrf` cookie (non-HttpOnly) and expects `X-CSRF-Token` header to match.
  - UI reads `csrf` cookie and sends header on `POST/PUT/DELETE`.
  - Attempt a cross-site form POST from a simple attacker page; expect rejection (403) without correct header.
3) SameSite behavior
  - With `SameSite=Lax`, test top-level GET navigations vs POST form submissions; observe cookie send behavior.
  - Switch to `SameSite=Strict` and note stricter behavior.
4) CORS boundary
  - Keep BFF on same origin as UI to avoid credentialed CORS; contrast with cross-origin setup and required CORS config.

5) JWT-backed API verification
  - Call a protected `news-api` route via the UI; inspect BFF logs to confirm `Authorization: Bearer ...` is added server-side.
  - Temporarily shorten token TTL to observe refresh behavior and single retry on `401`.

## Step-by-step (once BFF stub is added)
1) Start stack with BFF profile (compose override): `docker compose -f docker-compose.yml -f docker-compose.bff.yml up`
2) Login via UI; confirm no access token appears in web storage; cookies present.
3) Call protected API route via UI; check BFF adds `Authorization` to upstream call with a JWT access token; verify browser never sees token.
4) Try CSRF attack page; observe block unless correct `X-CSRF-Token` present.

## Success Criteria
- Tokens never accessible to JavaScript
- CSRF-protected routes reject forged requests
- Normal SPA flows (GET + state-changing requests) succeed with CSRF header

## Next Steps
- Implement a minimal BFF in `services/bff/` with:
  - OAuth code + PKCE flow handling
  - Session issuance (HttpOnly cookie)
  - `/csrf` endpoint to mint/rotate CSRF tokens
  - Proxy routes to `news-api` attaching `Authorization` with user-scoped JWT
  - Server-side token storage, refresh, and single-retry on `401`
- Keycloak setup:
  - Configure client scopes/role mappers and audience/resource for `news-api`
  - Optionally enable Token Exchange for on-behalf-of flows
- Add a tiny attacker page under a different origin in `infra/` to validate CSRF assumptions


