# `ppr` — Local-First Code Review CLI (Learning Lab)

`ppr` is a **local-first code review CLI** designed to be genuinely useful *and* to serve as a hands-on learning lab for modern agentic system design — without cloud dependence, hype, or opaque behavior.

The project deliberately layers:
- deterministic review signals,
- MCP-based tool access (typed RPC),
- PostgreSQL as a **hybrid database** (relational + JSONB + vectors),
- optional LLM synthesis behind strict guardrails,

so each capability is **understood, inspectable, and auditable**.

---

## Learning Objectives

This project is structured to learn:

- Deterministic systems as the system of record  
- PostgreSQL as a **hybrid data store** (tables + JSONB + vectors)  
- Local semantic memory tied to *your* repository  
- MCP as a clean, replaceable tool boundary  
- Agent pipelines **without requiring LLMs**  
- Tool-driven analysis vs model-driven judgment  
- LLMs as optional, advisory synthesis layers  
- Auditability: every claim traceable to evidence  

---

## Non-Goals

- No cloud dependency by default  
- No autonomous code changes  
- No hidden prompts or opaque decisions  
- No PR-host or SaaS integration (for now)

---

## Project Phases

### Phase 0 — Foundations
CLI skeleton, project layout, provider interfaces, JSON-first internal contracts.

**Learning focus:** deterministic boundaries, explicit state ownership.

---

### Phase 1 — Deterministic Review Signals
Dependency diffs, TODO diffs, change stats, risk tags, structured JSON output.

**Learning focus:** facts before heuristics; reproducible baselines.

---

### Phase 2 — Hybrid Database & Semantic Index
PostgreSQL schema design:
- relational tables for stable entities  
- JSONB for evolving metadata  
- vector columns for embeddings  

Local embedding model, chunking, incremental indexing.

**Learning focus:** hybrid DB design; JSONB evolution; embedding lifecycle.

---

### Phase 3 — Retrieval API
Vector similarity search with metadata filters, “similar code elsewhere,” policy/docs lookup, debug queries.

**Learning focus:** inspectable relevance; deterministic vs approximate retrieval.

---

### Phase 4 — Review Assembly (No LLM)
Assemble diffs, deterministic signals, semantic retrieval, and tool outputs into a cited review.

**Learning focus:** agent pipelines without LLMs; evidence-based assembly.

---

### Phase 5 — MCP Tool Reuse (Core)
Wrap git, fs, and search via MCP; replace shell calls with typed RPC.

**Learning focus:** MCP as a stable abstraction boundary.

---

### Phase 6 — MCP Quality & Accessibility Tools
Integrate MCP-backed tools for:
- static analysis / linters  
- formatting and style checks  
- security and dependency scanners  
- **accessibility audits** (HTML, UI, contrast, ARIA)

Tool outputs are:
- captured as structured JSON  
- stored as JSONB metadata  
- cited directly in reviews  

**Learning focus:**
- Tool-driven analysis vs heuristic judgment  
- Normalizing heterogeneous tool outputs  
- Treating quality and accessibility as first-class signals  
- Auditable, replaceable quality checks

---

### Phase 7 — Optional Local LLM Reviewer
Local LLMs only, bounded context, citations required, advisory output only.

**Learning focus:** synthesis without authority; LLMs layered *after* tools.

---

### Phase 8 — Policy & Gates
Configurable warn/fail rules across:
- deterministic signals  
- quality tools  
- accessibility findings  

CI-friendly exit behavior.

**Learning focus:** explicit policy encoding; deterministic enforcement.

---

## Philosophy

If `ppr` produces an output, you should always be able to answer:

> **Where did this come from, and why?**

That includes code quality and accessibility findings — not just “AI says so.”
