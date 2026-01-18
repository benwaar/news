# Project Plan — Local lab - News Briefing Agent (MCP + Embeddings + Optional LLM)

This project is a deliberate, local-first lab exploration of modern “agentic” system design without hype or hidden magic. The goal is to understand how agents are actually built by layering deterministic systems, MCP-based tool access (typed RPC), semantic memory via embeddings, and optional LLM-based judgment and synthesis. Each phase isolates one capability—state ownership, tool usage, retrieval, planning, and reasoning—so their roles and trade-offs are explicit, testable, and observable. The result is not just a news reader, but a practical reference implementation for building trustworthy, inspectable agents.

Goal: Cretae a local lab for security experiments. Then build a news briefing system that (1) ingests from RSS via MCP tools, (2) deduplicates and stores items, (3) ranks novelty against “what I know” using local embeddings, and (4) optionally uses an LLM/agent layer for synthesis.

🧠 Vector DB learning goal (explicit):
Understand embeddings systems as hybrid databases that combine:
- structured relational data
- semi-structured jsonb metadata
- vector similarity search
- deterministic + approximate retrieval trade-offs

Non-goals (initially):
- No paywalled scraping
- No auto-posting to social platforms
- No “autonomous” changes to notes without review
- No reliance on cloud services by default

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

## Phase 0 — Lab Baseline

Deliverables:
- setup-notes.md: setup a fresh local environment
- keycloak-ciam-lab.md: Keycloak CIAM tests and setup notes
- jwt-lab.md: JWT experiments

🧠 Add:
- Notes on when SQLite stops being sufficient and why Postgres + vectors are introduced later

## Phase 1 — Deterministic Core

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

🧠 Add (conceptual groundwork):
- Identify which fields are true schema vs future metadata
- Document which attributes are expected to become jsonb later

## Phase 2 — MCP Integration

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

🧠 Add:
- Store feed-specific or tool-specific artifacts as opaque metadata blobs (future jsonb fields)

## Phase 3 — Embeddings “Memory”

Scope:
- Local embedding model (no API key required)
- Store vectors for:
  - items (title + summary)
  - “known” notes (known.md or notes/ chunks)
- Novelty score based on similarity to known + recent history

🧠 Vector DB design decisions (explicit):
- Embedding dimensionality and model choice
- Distance metric (cosine / dot / L2) and why
- Chunking strategy:
  - title-only vs summary-only vs combined
  - fixed vs semantic chunking
- Deterministic brute-force similarity vs indexed ANN search

Deliverables:
- Indexing endpoints or commands:
  - POST /index/items (embed items missing vectors)
  - POST /index/known (embed notes)
- GET /brief/today?novel=1&top=N (top N by novelty)
- Optional clustering into themes (by similarity)

🧠 Add:
- Persist similarity scores and novelty scores alongside items
- Record embedding model name and chunking strategy used

Acceptance:
- Novelty ranking changes as known.md grows
- System works fully offline
- Results are reproducible given same model + data
- 🧠 Similarity scores are inspectable and logged (not opaque)

## Phase 4 — Agent Loop (no LLM required)

Scope:
- Add a simple “agent runner” that orchestrates:
  ingest → index → rank → generate brief
- This is an agent in the “decision loop” sense, not necessarily LLM-based.

Deliverables:
- CLI: python -m news.agent_runner --daily
- Stopping rules:
  - if no new items, stop
  - if novelty below threshold, skip expensive steps
- Structured run report (what happened and why)

🧠 Add (agent + vector transparency):
- Persist agent decisions per item:
  - novelty score
  - threshold applied
  - skip / select reason
- Store this trace as structured metadata (jsonb-friendly)

Acceptance:
- One command produces the daily brief end-to-end
- Logs explain decisions (why items were selected/skipped)
- 🧠 Agent behavior is auditable after the fact

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

🧠 Add:
- Store LLM outputs and prompts as non-authoritative metadata
- Explicitly separate semantic memory (embeddings) from advisory synthesis

Acceptance:
- System still works without LLM enabled
- AI output is clearly marked as advisory
- Cost controls exist if using a cloud key (top-N only)

## Phase 6 — Quality + Security Extensions (optional)

Scope ideas (choose based on interest):
- MCP security scanner tools (SAST/DAST) to enrich brief with “security-relevant” items
- Source trust scoring and allow/deny lists

🧠 Add:
- Attach security findings, trust scores, and provenance as evolving jsonb metadata
- Query vector similarity with metadata filters (e.g., security-relevant only)

## Summary

This project deliberately builds “agent capability” in layers:

1) deterministic system of record  
2) MCP tool usage (typed RPC)  
3) embeddings as memory + novelty  
4) agent loop (planning + stopping)  
5) optional LLM synthesis  

🧠 Throughout, the system explicitly practices:
- hybrid relational + jsonb + vector design
- inspectable similarity and novelty scoring
- deterministic vs approximate retrieval trade-offs
- auditable agent decisions

At every stage, the system remains usable and testable.


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

