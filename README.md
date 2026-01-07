# Project Plan — Local News Briefing Agent (MCP + Embeddings + Optional LLM)

This project is a deliberate, local-first exploration of modern “agentic” system design without hype or hidden magic. The goal is to understand how agents are actually built by layering deterministic systems, MCP-based tool access (typed RPC), semantic memory via embeddings, and optional LLM-based judgment and synthesis. Each phase isolates one capability—state ownership, tool usage, retrieval, planning, and reasoning—so their roles and trade-offs are explicit, testable, and observable. The result is not just a news reader, but a practical reference implementation for building trustworthy, inspectable agents.

Goal: Build a local-first news briefing system that (1) ingests from RSS via MCP tools, (2) deduplicates and stores items, (3) ranks novelty against “what I know” using local embeddings, and (4) optionally uses an LLM/agent layer for synthesis.

Non-goals (initially):
- No paywalled scraping
- No auto-posting to social platforms
- No “autonomous” changes to notes without review
- No reliance on cloud services by default

Repository convention:
- /news/ contains the application
- /specs/news-brief/ contains the specs (Spec Kit style)


## KERNEL-Inspired “Vibe Coding” (Fluency Mode)

This project is being created in “Python Fluency Mode”. The goal is learning the language, not enforcing specs.
Refactors are allowed. Mistakes are expected.

This project uses a **KERNEL-inspired approach** while coding interactively via chat.

The goal is **language fluency and understanding**, not formal specification or locked behavior.

### What “vibe coding” means here
- Build **one small, runnable step at a time**
- Use the chat window to propose the next step
- Run the code immediately
- Debug from real errors and outputs
- Refactor freely as understanding improves

This is *interactive co-building*, not copy-pasting large solutions.

### KERNEL principles retained (lightweight)

Even in fluency mode, a few constraints are intentionally kept:

#### 1. Small, inspectable steps
- Each change should be runnable within minutes
- No large, untested jumps
- Prefer visible state (prints, logs, simple outputs)

#### 2. Explicit authority
- The program owns its state (files, SQLite)
- Chat suggestions are advisory, not authoritative
- The code on disk is the source of truth

#### 3. Clear ownership boundaries
- Separate concerns early (db / ingest / brief)
- Avoid “god files” even while experimenting

#### 4. Fast feedback over correctness
- Errors are learning signals, not failures
- Fix what breaks *now*, not what might break later


### What is intentionally **not** enforced
- No formal specs or acceptance gates
- No locked behavior
- No premature optimization
- No obligation to keep early design decisions

This is **fluency mode**, not contract mode.



## Shared Language & Assumptions

This project uses the terminology defined in:
👉 [FOUNDATIONS](https://github.com/benwaar/shaders/blob/main/docs/FOUNDATIONS.md)

In particular:
- specs define behavior
- plans are inspectable intermediates
- execution is substrate-specific
- authority is explicit
- advisory systems do not own state

Any probabilistic behavior is treated as advisory unless explicitly stated otherwise.

## Spec Kit Artifacts

/specs/news-brief/
- spec.md  (contracts, invariants, definitions)
- plan.md  (architecture, components, data flow)
- tasks.md (implementation steps + acceptance checks)

Definition of authority:
- SQLite + files are the system of record
- MCP tools are capabilities only (fetch/parse/scan), not stateful owners
- LLM outputs are advisory and never authoritative


## Phase 0 — Spec Baseline (core)

Deliverables:
- [setup-notes.md](docs/setup-notes.md): setup a fresh local environment
- [keycloak-ciam.md](docs/keycloak-ciam.md): Keycloak CIAM tests and setup notes
- spec.md: definitions of “new”, “duplicate”, “novel”, output format, non-goals
- plan.md: components + boundaries (FastAPI server, storage, MCP client, embeddings)
- tasks.md: first implementation sequence
- lint.md: baseline linting guidance and rules for services and UIs (JS/TS/Angular)


Acceptance:
- Specs exist and are readable
- A change to behavior requires a spec change


## Phase 1 — Deterministic Core (core)

Scope:
- FastAPI server
- feeds.txt management
- SQLite storage
- URL/content dedup
- Basic markdown brief from stored items

Deliverables:
- POST /ingest (stores items, dedups)
- GET /brief/today (lists items grouped by source)
- GET /items (debug visibility)

Acceptance:
- Re-running ingest does not create duplicates
- Brief output is deterministic from DB contents
- Works offline after ingest (reading DB only)


## Phase 2 — MCP Integration (core learning)

Scope:
- Use an external/local RSS MCP server as a tool provider
- Replace direct RSS parsing with MCP tool calls (fetch + parse)

Deliverables:
- mcp_fetch_rss() implemented (client-side)
- Ingest uses MCP for feed retrieval/parsing
- Error handling + timeouts + per-feed failure isolation

Acceptance:
- If one feed fails, ingest continues for others
- MCP server can be swapped without changing storage logic
- Logs show tool calls and failures clearly


## Phase 3 — Embeddings “Memory” (core learning)

Scope:
- Local embedding model (no API key required)
- Store vectors for:
  - items (title + summary)
  - “known” notes (known.md or notes/ chunks)
- Novelty score based on similarity to known + recent history

Deliverables:
- Indexing endpoints or commands:
  - POST /index/items (embed items missing vectors)
  - POST /index/known (embed notes)
- GET /brief/today?novel=1&top=N (top N by novelty)
- Optional clustering into themes (by similarity)

Acceptance:
- Novelty ranking changes as known.md grows
- System works fully offline
- Results are reproducible given same model + data


## Phase 4 — Agent Loop (no LLM required) (core learning)

Scope:
- Add a simple “agent runner” that orchestrates:
  ingest → index → rank → generate brief
- This is an agent in the “decision loop” sense, not necessarily LLM-based.

Deliverables:
- CLI: `python -m news.agent_runner --daily`
- Stopping rules:
  - if no new items, stop
  - if novelty below threshold, skip expensive steps
- Structured run report (what happened and why)

Acceptance:
- One command produces the daily brief end-to-end
- Logs explain decisions (why items were selected/skipped)


## Phase 5 — Optional LLM Synthesis Layer (optional)

Scope:
- Use an LLM only for the top-N novel items:
  - “what changed” (2 bullets)
  - “why it matters” (1 bullet)
  - “follow-ups” (optional)
- Support local-first LLM; optionally allow cloud with a key.

Deliverables:
- GET /brief/today?ai=1 (adds synthesis section)
- Hard guardrails:
  - LLM never mutates DB state
  - LLM suggestions to update known.md are written to a separate “suggestions” file for review

Acceptance:
- System still works without LLM enabled
- AI output is clearly marked as advisory
- Cost controls exist if using a cloud key (top-N only)


## Phase 6 — Quality + Security Extensions (optional)

Scope ideas (choose based on interest):
- MCP security scanner tools (SAST/DAST) to enrich brief with “security-relevant” items
- Source trust scoring and allow/deny lists
- Email/Slack output
- Scheduling (cron/systemd/GitHub Actions), not “agent autonomy”

Acceptance:
- Extensions don’t break determinism of the core pipeline
- Failures degrade gracefully (best-effort enrichment)


## Summary

This project deliberately builds “agent capability” in layers:

1) deterministic system of record
2) MCP tool usage (typed RPC)
3) embeddings as memory + novelty
4) agent loop (planning + stopping)
5) optional LLM synthesis

At every stage, the system remains usable and testable.


## Local Git Hooks

Enable repository hooks to guard against committing sensitive files and large artifacts:

- Enable hooks: `tools/enable-githooks.sh`
- Confirm path: `git config --get core.hooksPath` (should be `.githooks`)

The pre-commit hook blocks staged files matching `*.pem`, `*.key`, `*.crt`, `*.env*`, files larger than 5MB, and runs quick lint checks:

- JS services: syntax check (`node --check`) on staged files in [services/api/src](services/api/src) and [services/rss-mcp/src](services/rss-mcp/src).
- Angular UI: TypeScript typecheck (`tsc --noEmit`) using the UI’s local compiler.

Skip temporarily with `--no-verify` if needed.


## Production Hardening (Notes)

This repository is optimized for local experimentation. For production, consider:

- **ESLint/Formatting:** Add ESLint/Prettier for `services/api`, `services/rss-mcp`, and Angular UI; enforce in CI.
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

### Linting

- API: `npm run lint --prefix services/api`
- RSS MCP: `npm run lint --prefix services/rss-mcp`
- UI-News: `npm run lint --prefix services/ui-news`
- UI-Portal: `npm run lint --prefix services/ui-portal`

Notes:
- Lint uses ESLint v8 with simple configs; TypeScript rules are relaxed to allow temporary `any` and ignore underscore-prefixed unused vars.
- Run all:
  - `npm run lint --prefix services/api && npm run lint --prefix services/rss-mcp && npm run lint --prefix services/ui-news && npm run lint --prefix services/ui-portal`
```
