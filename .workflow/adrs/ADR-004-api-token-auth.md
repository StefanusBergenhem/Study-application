---
id: ADR-004
status: proposed
date: "2026-05-19"
title: "API token authorization model — token scoped to issuing user"
governs_components: [api-tokens, auth, export]
supersedes: null
superseded_by: null
traces_to: [CAP-011, CAP-012]
---

# API token authorization model — token scoped to issuing user

## Context

CAP-011 and CAP-012 define a personal API token system: users generate tokens,
and external agents use them to create cards via REST API. OPQ-003 asks how
the token maps to a target user and library. The token identifies the calling
agent — but does it need per-user targeting capability, or is the token-owner's
identity sufficient?

## Decision

API tokens are scoped to the user who created them. A token authenticates
requests as that user — the token owner's identity is the effective user for
all API operations. External agents specify a `library_id` in the request body;
the system validates that the library belongs to the token owner.

## Alternatives

- **Token scoped to issuing user (chosen)** — Simple. The user's personal agent
  creates cards for the user. No cross-user authorization. Token management is
  straightforward: create, revoke, regenerate. Limitation: one integration per
  token, and the user cannot delegate card creation to another user's account.

- **Token with target-user field** — Token carries a `target_user_id` field,
  allowing one user's token to create cards in another user's account.
  Trade-off: enables collaborative AI-generated deck deployment, but introduces
  cross-user authorization complexity (consent flow, scope management, audit
  trail). Over-engineered for a personal study app.

- **OAuth 2.0 with user consent** — Full OAuth flow where external agents
  request scoped access and users approve. Trade-off: standard protocol, but
  far too complex for an MVP personal token system. Only warranted if the app
  grows a third-party integration ecosystem.

## Consequences

### Positive

- Minimal authorization surface — token == user. No cross-user permission model
  to design, test, or secure.
- Token lifecycle is simple: generate, list metadata, revoke, regenerate.
- Card creation endpoint validates `library_id` against the token owner's
  libraries — no new authorization concepts.

### Negative

- Cannot delegate card creation to another user's account via API. If the user
  wants an AI agent to create cards for a study group, each member must issue
  their own token and the agent must manage multiple tokens.
- Token has full user-level access — a compromised token can create/read all
  of that user's cards. Future token scoping (read-only, library-scoped) would
  require a schema change.

## Reversibility

To reverse: add a `scope` or `target_user_id` field to the ApiToken model.
The token validation path would check the scope in addition to the user
identity. Existing tokens default to the current behavior (full user scope).
Estimated cost: 1 week for schema migration + auth middleware update + token
management UI changes. This ADR is held at `proposed` until at least one REQ
in the api-tokens or auth components traces back to it and OPQ-003 is resolved.
