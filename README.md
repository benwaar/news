# PPR Project Plan — Local lab & Pre-Pull Request Tool (MCP + Embeddings + Optional LLM)

This project is a deliberate, local-first lab exploration of modern “agentic” system design without hype or hidden magic. The goal is to understand how agents are actually built by layering deterministic systems, MCP-based tool access (typed RPC), semantic memory via embeddings, and optional LLM-based judgment and synthesis. Each phase isolates one capability—state ownership, tool usage, retrieval, planning, and reasoning—so their roles and trade-offs are explicit, testable, and observable. The result is not just a news reader, but a practical reference implementation for building trustworthy, inspectable agents.

## KERNEL-Inspired “Vibe Coding” (Fluency Mode)

This project is being created in “Python Fluency Mode”. The goal is learning the language, not enforcing specs.
Refactors are allowed. Mistakes are expected.

This project uses a KERNEL-inspired approach while coding interactively via chat.

The goal is language fluency and understanding, not formal specification or locked behavior.

### What “vibe coding” means here
- Build one small, runnable step at a time
- Use the chat window to propose the next step
- Run the code immediately
- Debug from real errors and outputs
- Refactor freely as understanding improves

This is interactive co-building, not copy-pasting large solutions.


## Local Git Hooks

Enable repository hooks to guard against committing sensitive files and large artifacts:

- Enable hooks: `tools/enable-githooks.sh`
- Confirm path: `git config --get core.hooksPath` (should be `.githooks`)

The pre-commit hook blocks staged files matching `*.pem`, `*.key`, `*.crt`, `*.env*`, files larger than 5MB, and runs quick lint checks:

- JS services: syntax check (`node --check`) on staged files in [services/news-api/src](services/news-api/src) and [services/rss-mcp/src](services/rss-mcp/src).
- Angular UI: TypeScript typecheck (`tsc --noEmit`) using the UI’s local compiler.

Skip temporarily with `--no-verify` if needed.


## Production Hardening (Notes)

This repository is optimized for local experimentation. For production, consider:

- **ESLint/Formatting:** Add ESLint/Prettier for `services/news-api`, `services/rss-mcp`, and Angular UI; enforce in CI.
- **CORS/Rate Limits:** Restrict CORS to known origins and add basic rate limiting to public endpoints.
- **Container Hardening:** Run as non-root (done), pin images (done), and for k8s set `readOnlyRootFilesystem`, drop capabilities, and add resource requests/limits.
- **Secrets Management:** Use environment injection (not bake-in) and a secrets manager; keep `.env*` and certs out of VCS (enforced).
- **TLS:** Replace mkcert with trusted certificates in production; configure HSTS carefully.
- **DB Migrations:** Introduce a migration tool and process; the `schema_migrations` table is present for future use.

## Local TLS Certs

- Purpose: local HTTPS for UI and Keycloak. Certs are generated locally and not committed.
- Paths (ignored by git): [services/ui-news/certs](services/ui-news/certs), [services/ui-portal/certs](services/ui-portal/certs), [infra/keycloak/certs](infra/keycloak/certs)
- Quick setup (macOS):

```bash
brew install mkcert
mkcert -install

# Keycloak (HTTPS on 8443)
mkcert -cert-file infra/keycloak/certs/localhost.pem -key-file infra/keycloak/certs/localhost-key.pem localhost

# UI (HTTPS on 443)
# UI certs (news and portal)
mkcert -cert-file services/ui-news/certs/localhost.pem -key-file services/ui-news/certs/localhost-key.pem localhost
mkcert -cert-file services/ui-portal/certs/localhost.pem -key-file services/ui-portal/certs/localhost-key.pem localhost
```

- Or run: `tools/bootstrap.sh` (builds services and provisions certs if needed)

Compose mounts these certs automatically for [infra/keycloak](infra/keycloak), [services/ui-news](services/ui-news), and [services/ui-portal](services/ui-portal).

## Dev Credentials

- Keycloak Admin: admin / admin
- News Realm User: news / news
- Portal Realm User: portal / portal

Login URLs:
- News UI: https://localhost
- Portal UI: https://localhost:4443

Clients (OIDC):
- News: `news-web` (PKCE S256, redirect `https://localhost/*`)
- Portal: `portal-web` (PKCE S256, redirect `https://localhost:4443/*`)

Reset stack (drop and bootstrap):

```bash
tools/drop.sh
tools/bootstrap.sh
```

