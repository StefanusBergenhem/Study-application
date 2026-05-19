---
id: ADR-002
status: accepted
date: "2026-05-19"
title: "Tech stack — Next.js, TypeScript, Prisma, PostgreSQL"
governs_components: [api-tokens, auth, cards, database, export, libraries, mindmaps, study, ui]
supersedes: null
superseded_by: null
traces_to: [EXT-001, CAP-024]
---

# Tech stack — Next.js, TypeScript, Prisma, PostgreSQL

## Context

The system is a phone-first responsive web application (CAP-024) deployed on
Railway Hobby tier (EXT-001). It needs server-side rendering for fast initial
load, a type-safe data layer, and a relational database for the card-library-SR
state model. The team has not yet been assembled, so the stack decision is also
a hiring/onboarding signal.

## Decision

Use Next.js (App Router) with TypeScript for the full-stack framework, Prisma
as the ORM, and PostgreSQL (Railway managed) as the database. Authentication
uses next-auth or a lightweight custom session implementation.

## Alternatives

- **Remix + TypeScript + Prisma + PostgreSQL** — Trade-off: Remix has stronger
  web-standard alignment and nested routing, but a smaller ecosystem, fewer
  deployment templates, and less PWA documentation. Next.js has broader PWA
  support (next-pwa), more Railway deployment examples, and a larger talent pool.

- **Django + htmx + PostgreSQL** — Trade-off: Rapid backend development, built-in
  admin, mature ORM. But phone-first responsive UI with htmx is less ergonomic
  than React component libraries; PWA support is manual; TypeScript's type safety
  across the full stack is lost.

- **SvelteKit + Prisma + PostgreSQL** — Trade-off: Smaller bundle sizes, simpler
  reactivity model. But a smaller ecosystem for rich-text editing, PWA tooling,
  and UI component libraries. Less hiring pool overlap.

- **Go + templ/HTMX + PostgreSQL** — Trade-off: Excellent Railway Hobby resource
  efficiency (low memory, fast startup). But rich-text editing and phone-first
  responsive UI require significant custom JS; PWA support is fully manual.

## Consequences

### Positive

- Single language (TypeScript) across frontend and backend — lower cognitive
  overhead, shared types via the Card/User/SRState models.
- Next.js App Router provides server components, streaming, and route handlers
  in one framework — the monolithic deploy (ADR-001) maps naturally to it.
- Prisma's type-safe queries eliminate a class of runtime errors and generate
  TypeScript types from the database schema.
- PWA support via next-pwa or manual service worker — proven patterns exist.
- Railway offers a one-click Postgres plugin and documented Next.js deployment.

### Negative

- Next.js on Railway Hobby (512 MB) requires careful bundle optimization —
  large node_modules and serverless-style cold starts can push memory limits.
- Prisma's query engine adds ~10-15 MB to the process memory footprint.
- Full-stack Next.js blurs the server/client boundary — discipline needed to
  avoid shipping server code to the browser (mitigated by 'server-only' imports).
- TypeScript compilation and Prisma generation add to build time on Railway's
  build environment.

## Reversibility

To reverse the framework choice: rewriting the application in another framework
would be a full rewrite. Estimated cost: 3-6 months for a team of 2-3. The
database choice (PostgreSQL) is trivially portable across frameworks. The
component interfaces in COMPONENTS.yaml are framework-agnostic — only the
implementation language changes.
