# ADR Threshold

Most architectural decisions do NOT earn an ADR. The threshold filters routine
choices out so the ADR set stays high-signal — a future reader can trust that
anything in `docs/adrs/` was load-bearing enough to be worth preserving the
reasoning for.

## The three-condition threshold

A decision earns its own ADR if and only if **all three** of these hold.

### 1. Load-bearing

If reversed, the change would ripple beyond local scope.

- Affects multiple components, downstream consumers, or code that's expensive to migrate.
- Or: locks in a vendor / library / protocol whose replacement would be a multi-week project.

A choice between two equivalent libraries that are easy to swap is **not** load-bearing.

### 2. ≥2 real options existed

A genuine alternative was considered, with real trade-offs.

- *"Use Python"* when the project is a Python project: no alternative was on the
  table. Not an ADR.
- *"Compile-time embed.FS vs runtime file loading"* for a Go CLI: two real
  options, trade-offs in startup time, install simplicity, modifiability. ADR.

"Do nothing" is a real alternative only if it was seriously considered.

### 3. Contingent on changeable assumptions

The decision rests on assumptions that could plausibly change.

- Driven by a current scale point (1M users), a current cost structure, a current
  third-party vendor's pricing/availability, a current team skillset.
- If the inputs change, you'd reconsider.

A decision driven by physical laws or hard product constraints isn't contingent —
it's a fact. Not an ADR.

## ADR shape

Per-decision file at `<paths.adrs>/ADR-NNN-short-slug.md`. Template:
`templates/adr.md.tmpl`. Frontmatter carries:

```yaml
---
id: ADR-007
status: accepted            # proposed | accepted | superseded | deprecated
date: 2026-05-16
title: <short noun-phrase>
governs_components: [auth, repository]   # COMPONENTS.yaml entries this ADR shapes
supersedes: null
superseded_by: null
traces_to: []
---
```

Body sections (all required):

```markdown
## Context
<The driver: a specific REQ id, NFR, external constraint, or incident.
 Cited, not generic.>

## Decision
<One sentence stating what was chosen. Crisp.>

## Alternatives
- <Option A> — <one-paragraph trade-off reasoning>
- <Option B> — <one-paragraph trade-off reasoning>

## Consequences

### Positive
- <Concrete>

### Negative
- <Concrete — at least one>

## Reversibility
<Rollback path with cost OR named sign-off authority.>
```

## Status transitions

- `proposed` → `accepted` — approved AND at least one REQ in a governed
  component now traces to this ADR. *Both* halves are required: the human gate
  approves the decision; the REQ trace proves the decision actually shapes the
  spec. An ADR with no inbound REQ trace is a plan, not a ratified decision.
- `accepted` → `superseded` — a later ADR replaces this one. The new ADR's
  `supersedes` field names this one; this one's `superseded_by` field gets filled.
- `accepted` → `deprecated` — no longer applicable but not replaced (feature removed).

ADRs are **immutable once accepted** — supersede, don't edit.

### When `proposed` is the right status

Hold an ADR at `proposed` when any of these are true:

- The decision is ratified by SA judgement but the code (or its specifying REQs)
  does not exist yet. Promote to `accepted` once at least one REQ in a governed
  component has the ADR in `traces_to`.
- The decision is contingent on a future condition that has not yet resolved
  (e.g., "we will adopt vendor X if their pricing remains under threshold Y").
- The human gate has not yet approved.

A `proposed` ADR may carry an aspirational `governs_components` list — the
arbitrator does not require it to be empty. It does require that nothing in
COMPONENTS.yaml's `governed_by_adrs` lists a `proposed` ADR without a comment
explaining the speculative trace, since the back-link normally signals a
ratified design.

## The `governs_components` field (load-bearing traceability)

Every accepted ADR lists which components it shapes. This is the trace that
makes the ADR set discoverable from COMPONENTS.yaml:

- COMPONENTS.yaml entries carry `governed_by_adrs: [ADR-007, ADR-012]`.
- ADR frontmatter carries `governs_components: [auth, repository]`.

The two fields are inverses — keep them in sync. When the SA authors a new ADR,
update both sides. When a component is removed, update or supersede the ADRs that
governed it.

## Anti-patterns

- **ADR for routine choice.** "We use JSON, not XML" when JSON is the default
  and XML was never on the table.
- **Generic rationale.** "This is clean / scalable / idiomatic / best-practice."
  Cite the driver from Context. If you can't, the decision either isn't
  load-bearing or you haven't thought it through.
- **One alternative.** "Option A vs do nothing" where "do nothing" wasn't
  actually a contender. Add genuine alternatives or kill the ADR.
- **Missing Reversibility.** Without an explicit answer, the reversibility of
  the decision is undetermined — fill in the rollback path or named authority.
- **No `governs_components` field.** An ADR that doesn't say which components it
  shapes can't be found from COMPONENTS.yaml — half its leverage is gone.
- **Convention-as-ADR.** A one-line code-organization rule (*"use library X"*,
  *"all calls go through Y"*, *"no down migrations"*) wrapped in the full ADR
  template. If reversal does not pass the load-bearing test, or if no real
  alternatives were weighed, the rule belongs in the `conventions:` block of
  `COMPONENTS.yaml`, not as an ADR. See `conventions.md`. An ADR may still
  ratify a convention when reversal genuinely ripples — in that case keep the
  ADR thin and let the convention carry the operational text.
- **Forward-declaration ADR (status: accepted, no implementing REQ).** An ADR
  that documents a planned design — the code does not yet exist, and no REQ in
  any of its `governs_components` traces back to it — should be `proposed`,
  not `accepted`. Promote to `accepted` only when at least one REQ has the ADR
  in `traces_to`, proving the design actually shapes a specified obligation.
  Forward-declaration ADRs accumulate stale plans: the decision drifts before
  any code can hold it accountable. The arbitrator surfaces this as a warn —
  the SA either adds the missing REQ trace (if the code is imminent) or
  demotes the ADR to `proposed` (if the design is still hypothetical).

## Expected ADR density

Rough order of magnitude for a typical project:

- A small / new project: 2–6 ADRs.
- A mid-size project: 10–30 ADRs.
- A large or long-running project: 30–80 ADRs.

If you author 10+ ADRs in one SA session, the threshold is being applied too
loosely. Tighten — most "decisions" you made were actually defaults or implementation
details, not load-bearing choices.

## When to author or update an ADR

- **During SA Phase 3 (Design)** — as load-bearing decisions emerge in a session,
  mark `<!-- ADR-CANDIDATE: <decision> -->` inline. At the end of the session, sweep
  candidates and apply the threshold; author ADRs for the ones that pass, drop the
  rest.
- **After implementation** — when a sprint ships a decision that turned out to be
  load-bearing in retrospect, author the ADR even though it wasn't anticipated.
- **When an assumption changes** — re-read the ADRs governing the affected components.
  Decide: is the original reasoning still valid? If yes, leave it. If no, author a
  superseding ADR.
