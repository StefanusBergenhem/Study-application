# Roadmap mode — Phase 3 + Phase 4c

Activated when `paths.roadmap` exists at session start. Job: translate roadmap
capabilities (and any external constraints) into spec-layer additions and a
fresh technical backlog. Every backlog item traces to a roadmap capability;
every new REQ traces to a roadmap capability, an external constraint
(`EXT-NNN`, materialised as `type: inherited-constraint`), or an ADR.

Return to `SKILL.md` for Phase 4a, 4b, 5, 6.

---

## Phase 3 — Design (roadmap variant)

Work **capability-by-capability**, not batch.

### 0. Materialise external constraints first (one pass)

Before walking capabilities, sweep the roadmap's `external_constraints:`
section. For each `EXT-NNN` entry:

- Decide which component(s) carry the constraint. Many external constraints
  are cross-cutting (e.g. "use company OAuth") and become a SYS-REQ allocated
  to multiple components. Some are component-local (e.g. "PostgreSQL only")
  and live as a single component REQ.
- Author a `type: inherited-constraint` REQ at the right tier, with
  `traces_to: [EXT-NNN]` pointing back to the roadmap entry. Acceptance
  criteria are optional unless the local manifestation needs specifics (see
  `wf-skill-spec-references/references/ears-syntax.md` §Per-type policy).
- If the constraint demands an architectural commitment with real alternatives
  (e.g. "must run on-prem" → choose the runtime), mark an
  `<!-- ADR-CANDIDATE: <decision> -->` for sweep in Phase 4a.

This pass produces the constraint scaffolding the capability designs will
build on top of.

### Per-capability flow

For each roadmap capability requiring technical decisions:

### 1. Show where it fits

Generate a **capability placement diagram** — the existing component graph
with the new capability's location highlighted (`[*]` marker). If component
assignment is ambiguous, show both options on separate diagrams.

### 2. Walk through design decisions

For each non-obvious decision, present your reasoning:

> **Decision:** [what you're deciding — component assignment, REQ shape,
>   interface, dependency, etc.]
> **Alternatives considered:**
> - A: [option] — [tradeoff]
> - B: [option] — [tradeoff]
> **Recommended:** [which one] because [1-2 sentences explaining why]
> **Risk of this choice:** [1 sentence]

Cover these concerns per capability, **in this order**:

- **System-level promise (Tier 1).** What does the user/operator/external system
  observe end-to-end when this capability works? Sketch one or more SYS-REQs in
  EARS form. Use the decision tree in
  `wf-skill-spec-references/references/ears-syntax.md` §Tier placement to
  decide whether each promise actually belongs at Tier 1 or is
  really a single-component obligation (Tier 2). Cross-cutting NFRs implied by
  the capability (latency, throughput, durability) go here too.
- **Component assignment & allocation.** Which components must cooperate to
  honour each SYS-REQ? List them in `allocated_to:`. Does this fit existing
  boundaries, or is a new component needed?
- **Component-level slices (Tier 2).** What does each `allocated_to:` component
  actually have to do? Sketch the component REQs in EARS form, each with
  `derives_from: [SYS-REQ-NNN]` pointing back. Also add any component-local
  REQs that don't derive from a SYS-REQ (purely internal contracts).
- **Interface contracts.** What new `exposes:` entries are needed? For
  cross-component or non-obvious interfaces, sketch the DbC block during the
  conversation (preconditions, postconditions, typed errors, style).
- **Dependency impact.** New edges on the graph? Any `dependency_rules` changes?
- **Data flow.** For non-trivial flows, generate a data flow diagram.
- **Risk assessment.** Schema migrations, breaking changes, performance.
- **Decision worth an ADR?** Mark candidates with `<!-- ADR-CANDIDATE: <decision> -->`
  inline in your notes. Sweep them in Phase 4a.
- **SOLID alignment.** Single responsibility per component? Interfaces narrow?
  Dependencies pointing toward abstractions?

### 3. Get human input

Present the design for this capability. Discuss alternatives, change direction
if needed, then move on.

**WAIT** before proceeding to the next capability.

**Efficiency clause:** Simple capabilities where component assignment is
obvious and no new dependencies arrive — batch 2-3 together. Anywhere with
ambiguity, present individually.

---

## Phase 4c — Update the master backlog (roadmap variant)

Translate roadmap capabilities into a technical backlog with sprint groupings,
scoped to the new spec layer.

Roadmap-specific rule: **every backlog item carries `capability_ref`** pointing
to its roadmap capability (or, for plumbing demanded purely by an external
constraint, `capability_ref` may point to the inherited-constraint REQ id
instead). Items without a capability trace do not belong in a roadmap session —
surface them to the human.

Common backlog rules and the sprint-cut visualization live in `SKILL.md`
§Phase 4c.
