# Local Security Experiment Plan (Nginx + Express + Angular)

## 1. Baseline
- Nginx: no security headers
- Express: default settings
- Angular: default build
- Capture:
  - Browser DevTools → Security tab
  - Response headers
  - Console warnings

## 2. Edge / Proxy Layer (Nginx)
- Configure in: nginx.conf / site config
- Experiments:
  - Add HSTS, X-Content-Type-Options, X-Frame-Options
  - Add CSP (start with `Content-Security-Policy-Report-Only`)
  - Force HTTPS + TLS versions
- Goal:
  - Validate headers applied consistently
  - Observe browser enforcement vs report-only

## 3. Application Layer (Express)
- Configure in: Express middleware
- Experiments:
  - Set/override headers per route
  - Cookie flags: Secure, HttpOnly, SameSite
  - CORS policy variations
- Goal:
  - Compare proxy-set vs app-set headers
  - Test route-specific security behavior

## 4. Frontend Layer (Angular SPA)
- Configure in: Angular build + index.html
- Experiments:
  - CSP via HTTP header vs meta tag
  - Asset loading under strict CSP
  - Trusted Types (optional)
- Goal:
  - Identify CSP breakage points
  - Validate SPA compatibility

## 4.1 XSS Exercises (Hands-on)
- Scenarios:
  - Reflected XSS (simulated route/param echo in dev)
  - DOM-based XSS (dangerous innerHTML sink demo)
  - Token theft via `localStorage`/`sessionStorage`
- Steps:
  1) In the UI, open JWT Lab → Storage Options, switch to `localStorage`, save an access token, and observe it in the preview.
  2) Visit a demo page that reflects a query param (e.g., `/xss?msg=<img src=x onerror=alert('xss')>`). Confirm behavior with/without CSP.
  3) Use a DOM sink demo where untrusted HTML is injected via `innerHTML`. Attempt payloads and note what CSP blocks.
  4) With a token in `localStorage`, run a snippet in DevTools to read `localStorage['token:news:news-web']` and simulate exfiltration. Discuss why HttpOnly cookies mitigate this.
- Mitigations:
  - Prefer BFF + HttpOnly cookies for production.
  - Keep tokens in memory when possible; avoid persistent web storage.
  - Enable strict CSP (no `unsafe-inline`; use nonces/hashes; limit script origins).
  - Consider Trusted Types to prevent DOM-based XSS in large SPAs.
  - Sanitize any dynamic HTML (avoid `innerHTML`; use safe templating).

## 5. Enforcement & Regression
- Switch CSP from report-only → enforced
- Re-test:
  - App functionality
  - Console errors
  - Network requests
- Document:
  - What must live in Nginx vs Express
  - What breaks only in the browser


-----

# Future idea - Turning the Local Stack into a Pentesting Lab
(Nginx + Express + Angular SPA)

## Why this works
- Clear trust boundaries:
  - Browser ↔ Nginx
  - Nginx ↔ Express API
  - Angular SPA ↔ API
- Realistic, common production architecture
- Easy to introduce isolated, reversible misconfigurations

## Lab Structure
- Create security profiles:
  - secure
  - weak-headers
  - broken-cors
  - insecure-cookies
  - mixed-content
- Switch profiles via config or branches

## Intentional Vulnerabilities
- Missing or weak CSP directives
- Overly permissive CORS (`*` with credentials)
- Cookies without `Secure` / `SameSite`
- JWT stored in `localStorage`
- Conflicting headers between Nginx and Express
- Blind trust of `X-Forwarded-*` headers

## Attacker Goals
- Execute injected scripts despite CSP
- Steal auth tokens using browser-only attacks
- Exfiltrate API data via CORS
- Perform clickjacking
- Bypass transport security assumptions

## Observability
- CSP report endpoint
- Nginx access/error logs
- Express request logging
- Browser DevTools (Security + Network tabs)

## Packaging
- Docker Compose with selectable profiles
- README with architecture diagram
- Defined success conditions (flags or proofs)


-----

# BFF + HttpOnly + CSRF Lab (Planned)

Goal: Demonstrate how a Backend-for-Frontend issues HttpOnly cookies and defends state-changing requests with CSRF protections, keeping tokens out of JavaScript while preserving SPA UX.

## Architecture
- Browser → UI (Angular)
- UI → BFF (Node/Express)
- BFF → IdP (Keycloak) for OAuth/OIDC
- BFF → API (news-api) with server-side `Authorization`

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

## Step-by-step (once BFF stub is added)
1) Start stack with BFF profile (compose override): `docker compose -f docker-compose.yml -f docker-compose.bff.yml up`
2) Login via UI; confirm no access token appears in web storage; cookies present.
3) Call protected API route via UI; check BFF adds `Authorization` to upstream call; verify browser never sees token.
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
  - Proxy routes to `news-api` attaching `Authorization`
- Add a tiny attacker page under a different origin in `infra/` to validate CSRF assumptions
