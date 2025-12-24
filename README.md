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

---

## Spec Kit Artifacts

/specs/news-brief/
- spec.md  (contracts, invariants, definitions)
- plan.md  (architecture, components, data flow)
- tasks.md (implementation steps + acceptance checks)

Definition of authority:
- SQLite + files are the system of record
- MCP tools are capabilities only (fetch/parse/scan), not stateful owners
- LLM outputs are advisory and never authoritative

---

## Phase 0 — Spec Baseline (core)

Deliverables:
- spec.md: definitions of “new”, “duplicate”, “novel”, output format, non-goals
- plan.md: components + boundaries (FastAPI server, storage, MCP client, embeddings)
- tasks.md: first implementation sequence

Acceptance:
- Specs exist and are readable
- A change to behavior requires a spec change

---

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

---

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

---

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

---

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

---

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

---

## Phase 6 — Quality + Security Extensions (optional)

Scope ideas (choose based on interest):
- MCP security scanner tools (SAST/DAST) to enrich brief with “security-relevant” items
- Source trust scoring and allow/deny lists
- Email/Slack output
- Scheduling (cron/systemd/GitHub Actions), not “agent autonomy”

Acceptance:
- Extensions don’t break determinism of the core pipeline
- Failures degrade gracefully (best-effort enrichment)

---

## Summary

This project deliberately builds “agent capability” in layers:

1) deterministic system of record
2) MCP tool usage (typed RPC)
3) embeddings as memory + novelty
4) agent loop (planning + stopping)
5) optional LLM synthesis

At every stage, the system remains usable and testable.
