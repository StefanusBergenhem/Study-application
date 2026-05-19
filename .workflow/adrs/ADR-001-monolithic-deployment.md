---
id: ADR-001
status: accepted
date: "2026-05-19"
title: "Monolithic deployment topology"
governs_components: [api-tokens, auth, cards, database, export, libraries, mindmaps, study, ui]
supersedes: null
superseded_by: null
traces_to: [EXT-001]
---

# Monolithic deployment topology

## Context

EXT-001 constrains deployment to Railway Hobby tier (512 MB RAM, limited CPU,
no persistent disk outside managed volumes). Multiple services would fragment
the already-small resource budget and incur cold-start penalties on low-traffic
services. The system must serve auth, cards, libraries, study, mind maps, and
API endpoints within these limits.

## Decision

Deploy the entire application as a single monolithic Next.js process on Railway
Hobby, with a managed Railway Postgres database for persistence. Logical
component boundaries are enforced at the code level via COMPONENTS.yaml, not
at the process level.

## Alternatives

- **Multiple microservices (one per component)** — Each domain auth/cards/libraries/
  study/mindmaps/api-tokens as a separate Railway service. Trade-off: stronger
  runtime boundary enforcement, independent scaling, isolated failures. But
  Railway Hobby tier limits make this impractical: 512 MB RAM split across N
  services means each gets ~50-100 MB; Postgres connection pools fragment;
  low-traffic services experience cold starts on every request.

- **Two-service split (web + worker)** — UI/API in one service, a background
  worker for reminders (CAP-017) and export (CAP-019) in a second service.
  Trade-off: slightly better isolation for async work, but adds deployment
  complexity for features that ship in Phase 4. The worker could be added as
  a secondary service later if needed.

- **Monolithic deploy (chosen)** — Single Next.js process handles all HTTP
  requests and any inline async work. Trade-off: simplest deploy, zero
  inter-service latency, single connection pool. Risk: component boundaries
  must be enforced by discipline (conventions + review), not by the runtime.

## Consequences

### Positive

- Maximum resource efficiency — 512 MB RAM serves all components.
- Single connection pool to Postgres respects Railway Hobby connection limits.
- No inter-service latency or serialization overhead.
- Simplest CI/CD pipeline: one build, one deploy.

### Negative

- No runtime enforcement of component boundaries — discipline relies on code
  review and import conventions.
- Blast radius is larger: a memory leak in one component affects all.
- Scaling is all-or-nothing — cannot scale study independently of mind maps.
- Future extraction of a component into its own service requires careful
  interface extraction (mitigated by the already-specified `exposes:` contracts).

## Reversibility

To reverse: extract one or more components into separate Railway services. Each
extraction requires (a) converting in-process calls to HTTP, (b) duplicating
auth middleware per service, (c) splitting the Prisma schema or introducing a
per-service data access layer. Estimated cost: 1-2 weeks per extracted component.
The `exposes:` interfaces in COMPONENTS.yaml are designed as future service
boundaries — the extraction surface is pre-defined.
