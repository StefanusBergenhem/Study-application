---
name: wf-skill-spec-references
description: Canonical spec-layer language — EARS-light requirement syntax (incl. two-tier placement and per-type AC policy), Design-by-Contract clause shape, ADR threshold rules, the conventions-block shape, and the design-issue / fix_kind taxonomy. Read on demand by any skill that authors, verdicts, or routes spec-layer artifacts.
---

# Skill: Spec-Layer References

This skill is **pure reference material**. It owns no procedure and produces no
artifacts. Its job is to be the single source of truth for the *language* of
the spec layer and the routing artifacts that respond to it — the rules a
producer must follow when writing requirements, contracts, and decisions, the
rules a verdicter must apply when judging them, and the shared taxonomy a
build / review / SwA / SA / orchestrator pipeline uses to route design-issue
resolutions.

Primary consumers:

- `wf-skill-sa` — Solution Architect, who *writes* the spec layer.
- `wf-skill-arbitrator-review` — Arbitrator, who *verdicts* the spec layer.
- `wf-skill-build` / `wf-skill-review` — populate `fix_kind` when raising a DI.
- `wf-skill-swa` (fix mode) — consumes contract-amendment DIs.
- `wf-skill-orchestrate` — routes DESIGN_ISSUE verdicts by `fix_kind`.

All consumers cite the canonical paths below. No skill ships its own copy. One
document, no drift.

---

## When to load which reference

| If you are working on… | Load |
|:--|:--|
| Writing or judging a requirement (`SYS-REQ-*` or `REQ-*`) — EARS form, tier placement, AC policy per type | `references/ears-syntax.md` |
| Writing or judging a contract-worthy `exposes:` entry — preconditions, postconditions, typed errors, style | `references/dbc-clauses.md` |
| Deciding whether a decision earns an ADR, or judging an existing ADR's threshold | `references/adr-threshold.md` |
| Writing or judging a `conventions:` entry — repository-hygiene rule shape, slot boundary vs REQ/ADR/dependency_rules | `references/conventions.md` |
| Writing a design issue (build / review / SA / SwA) or routing one (orchestrator) — DI artifact shape, `fix_kind` taxonomy, classification check | `references/design-issues.md` |

Load lazily, not all up-front. The SKILL.md of the consuming skill is the entry
point; this skill is the dictionary it reaches for.

---

## What this skill does NOT do

- Does not author or modify any artifact.
- Does not run any check or script.

The boundary: **shared language → here; private procedure → owning skill.**

---

## References

- `references/ears-syntax.md` — EARS-light requirement syntax, two-tier
  placement (`system_requirements:` vs `components[*].requirements`),
  per-type acceptance-criteria policy, NFR five-element rule, complementary
  pairs, anti-patterns.
- `references/dbc-clauses.md` — Design-by-Contract clause shape for
  contract-worthy `exposes:` entries: preconditions, postconditions, invariants,
  typed errors, style (`demanding` vs `tolerant`), test-mapping.
- `references/adr-threshold.md` — Three-condition ADR threshold (load-bearing,
  ≥2 real options, contingent), ADR file shape, `governs_components` symmetry,
  expected density, status transitions.
- `references/conventions.md` — Conventions block shape (id, rule, rationale,
  enforced_by, applies_to, traces_to), slot boundary vs REQ / ADR /
  dependency_rules, anti-patterns.
- `references/design-issues.md` — Design-issue artifact shape, `fix_kind`
  taxonomy (`contract_amendment | spec_amendment | unknown`), the producer's
  mechanical classification check, and the orchestrator's routing table.
