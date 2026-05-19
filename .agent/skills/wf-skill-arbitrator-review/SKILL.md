---
name: wf-skill-arbitrator-review
description: Spec-layer arbiter. Verdicts COMPONENTS.yaml + ADR set as a combined artifact set after an SA session. Emits APPROVED, REJECTED (writes paths.arbitrator_feedback for SA fix mode), or DESIGN_ISSUE (writes paths.arbitrator_escalation when the problem is upstream of SA).
---

# Skill: Spec-Layer Arbitrator

You verdict the project's spec-layer output as a **combined artifact set** —
`COMPONENTS.yaml` (with requirements, exposes/DbC, governed_by_adrs) and every
file under `paths.adrs`. Two artifacts, one verdict. Per-artifact rigor and
cross-artifact consistency are both required to pass.

You are dispatched by `wf-skill-sa` at the end of Phase 5, before SA commits.
You may also be invoked standalone after a manual edit to either artifact.

You are read-only on source code. You write only verdict artifacts to `.workflow/`.
You never modify `COMPONENTS.yaml` or any ADR file — SA does the rewriting in
fix mode.

---

## Scope — mechanical vs judgement-call

Mechanical findings — anything emitted by
`wf-skill-spec-references/scripts/check_spec_links.sh` or `check_ac_policy.sh`
— are the **producer's** pre-flight responsibility. SA Phase 5 step 2
iterates the producer through those scripts (with structured `fix_hint`
lines) until they report `summary: blocks=0`. The arbitrator does **not**
re-run those scripts.

If the producer dispatches before reaching a clean script state, the
arbitrator returns REJECTED with the residual `[BLOCK]` findings cited
verbatim and performs no further judgement-call work — the producer must
reach a clean pre-flight before judgement-call verdicting begins. This is
the consistent posture with mechanical-vs-judgement separation: mechanical
detection belongs to scripts, mechanical resolution belongs to the
producer, and the arbitrator owns the judgement-call categories the scripts
cannot perform.

The six check categories below cover the work the scripts cannot do:
DESIGN_ISSUE preemption (Category 1); the EARS / DbC / convention rigor
that requires reading prose (Category 2 judgement layer); ADR threshold
reasoning (Category 3 and Category 5); cross-artifact consistency on
prose-level inputs the scripts cannot parse (Category 4 judgement layer);
and the Spec Ambiguity Test (Category 6).

---

## Inputs

| Input | Location | Purpose |
|:------|:---------|:--------|
| Components | `paths.components` (e.g. `COMPONENTS.yaml`) | The architecture artifact to verdict |
| ADRs | `paths.adrs` directory (e.g. `docs/adrs/`) | The decision log to verdict |
| Roadmap | `paths.roadmap` (optional) | Upstream features that REQs `traces_to` |
| Master backlog | `paths.master_backlog` (optional) | Cross-check that REQs cover backlog work |
| Memory | `paths.memory` (optional) | Refined lessons from past sprints. Filter to `architecture_signals` — these are design-level patterns and prior boundary mistakes the arbiter should catch if SA repeats them. |
| Config | `.workflow/config.yaml` | Project paths and settings |
| References bundled with this skill | `references/` | Finding taxonomy and verdict decision table |

References to read on demand:
- `references/finding-taxonomy.md` — finding shape, severity rules, anti-pattern catalogue
- `references/verdict-decision-table.md` — APPROVED vs REJECTED vs DESIGN_ISSUE rules

**Shared spec-layer language** (lives in `wf-skill-spec-references` — the same
canonical text the SA writes against, so producer and verdicter cannot drift):
- `wf-skill-spec-references/references/ears-syntax.md` — EARS form, two-tier placement, per-type AC policy, NFR five-element rule
- `wf-skill-spec-references/references/dbc-clauses.md` — DbC clause shape for `exposes:` entries
- `wf-skill-spec-references/references/adr-threshold.md` — three-condition ADR threshold + ADR file shape
- `wf-skill-spec-references/references/conventions.md` — conventions block (repository-hygiene rules) + slot-boundary tests

### Applying memory lessons

If `paths.memory` exists, read it and filter to `category: architecture_signals`. Each lesson is a prior-sprint rule about boundaries, ADR triggers, or component fragility. Use them as **additional finding triggers** during Categories 2–5 — if SA's output repeats a pattern a past lesson warned against, emit a finding citing the lesson id (e.g., `"violates lesson L-007: auth/session boundary previously rejected for cross-component leakage"`).

Memory lessons never *raise* the verdict ceiling — they cannot turn a passing review into an escalation, only into a REJECTED finding. They are guidance, not gates. If memory is absent or has no `architecture_signals` entries, skip silently.

---

## Verdict types

### APPROVED

All check categories pass with no blocking findings. SA output is acceptable for
downstream consumption (SwA can author task contracts).

**Emit:** Print `ARBITRATOR APPROVED — components=<N>, adrs=<M>, warns=<W>` and
exit. **Do not write any file** — the orchestrator and SA infer APPROVED from
the absence of `arbitrator_feedback.yaml` and `arbitrator_escalation.yaml`.

### REJECTED

One or more blocking findings, all fixable inside SA's mandate.

**Emit:** Write `arbitrator_feedback.yaml` at `paths.arbitrator_feedback`
(default `.workflow/.transient/arbitrator_feedback.yaml`). Format per
`assets/arbitrator_feedback.yaml.tmpl` (sibling to this SKILL.md). Print
`ARBITRATOR REJECTED — findings=<N> blocks + <M> warns`. SA fix mode will
consume.

### DESIGN_ISSUE (escalate)

The findings indicate the **upstream input** is the actual problem — the roadmap
is silent on a load-bearing question, or a stakeholder decision conflicts with
itself across features, and SA cannot resolve it without input.

**Emit:** Write `arbitrator_escalation.yaml` at `paths.arbitrator_escalation`
(default `.workflow/.transient/arbitrator_escalation.yaml`). Format per
`assets/arbitrator_escalation.yaml.tmpl`. Print
`ARBITRATOR ESCALATE — target=<layer>`. The human routes from there.

For borderline judgement calls (rigor passes but something feels off) emit
a REJECTED with a `warn`-severity finding rather than escalating — preserve
the verdict's actionability.

---

## Check categories

Six categories, in this order. **Stop at the first DESIGN_ISSUE found** —
escalation preempts in-scope fixes.

Per the Scope section above, you do **not** run the mechanical pre-flight
scripts here — the producer has already iterated them to `blocks=0` before
dispatching. If you nonetheless detect an obvious residual `[BLOCK]`-shape
violation on the artifact set (e.g., a ghost reference, an asymmetric
allocation, a malformed convention id), that is a producer-pre-flight
failure: emit REJECTED with the unresolved finding cited and stop. Do not
substitute your own script run for the producer's responsibility.

### Category 1 — DESIGN_ISSUE preemption

Run this first. Look for indicators that the problem is upstream of SA:

- **Missing roadmap input** — A component's REQs reference a roadmap capability
  id (`traces_to: [CAP-NNN]`) or external constraint id (`traces_to: [EXT-NNN]`)
  that doesn't exist in `roadmap.yaml`.
- **Roadmap gap** — A backlog item or capability requires a decision that no
  REQ or ADR addresses, and the choice rightly lives at the product level (not
  architecture).
- **Conflicting roadmap commitments** — Two roadmap capabilities (or a
  capability vs. an external constraint) imply incompatible architectural
  choices and the SA has no basis to pick.

If any: **escalate immediately** with `target_layer` set. Do not also flag
in-scope findings — they're symptoms, not causes.

### Category 2 — Per-artifact rigor (COMPONENTS.yaml)

#### System requirements (top-level `system_requirements:` block)

For each SYS-REQ:

**Mechanical checks (already covered in producer's Phase 5 pre-flight — listed for reference, not re-run here):**

- `type` is one of `functional | nfr | invariant`
- AC policy per type (functional → AC required; nfr → nfr_elements required;
  invariant → statement non-empty)
- NFR five-element rule (subject, metric, threshold, condition, source — or
  `[DEFER-NUMERIC]`)
- `allocated_to:` non-empty
- `traces_to` non-empty

**Judgement-call checks:**

- **EARS conformance and atomicity** — same rules as component REQs below.
  No compound obligations ("A and B"). No subjective adjectives. No smuggled
  design.
- **Tier discipline.** Flag SYS-REQs that are really single-component
  obligations dressed up as system promises — when `allocated_to` lists one
  component and the obligation does not involve user-visible behavior or
  cross-component cooperation, recommend demotion to component REQ.

#### Per-component requirements

For each component:

**Mechanical checks (already covered in producer's Phase 5 pre-flight — listed for reference, not re-run here):**

- AC policy per type (see `skills/wf-skill-spec-references/references/ears-syntax.md` §Per-type policy)
- NFR five-element rule
- `traces_to` resolution and tier discipline
- `derives_from` resolves to existing SYS-REQ
- `depends_on` declared and resolves

**Judgement-call checks:**

- **Has at least one requirement.** A component with no `requirements` is either
  a registration-only entry (test-only, build-only — declare `status: support`)
  or it's underspecified. Untyped components are findings.
- **REQ EARS conformance.** Every REQ matches one of the five EARS forms, or is
  typed `inherited-constraint`. See `skills/wf-skill-spec-references/references/ears-syntax.md`.
- **REQ atomicity.** No compound statements (no obligation-joining "and").
- **No smuggled design.** No requirement names a specific library, framework,
  algorithm, or technology — those go in ADRs or in the `exposes` block.
- **No smuggled convention.** Flag REQ statements that describe code
  organization rather than observable behavior — phrasing tells like *"shall
  route every"*, *"shall not call inline"*, *"shall use raw"*, *"all
  migrations shall"*. These belong in the top-level `conventions:` block.
  Warn-severity finding with a suggested migration target.
- **No per-statement rationale.** Optional one-line `intent` field; never a paragraph.
- **No multi-line editorial comments.** Spec files describe current state, not history. Inline YAML comments inside `system_requirements` or `components.*.requirements` that span more than one line, OR that contain prose past a date stamp (`# 2026-05-19: ...`), are noise — the rationale belongs in the commit message, the resolved design-issue entry, or an ADR. Emit a warn-severity finding per offending block with the suggested migration target. Single-line pointers (`# see DI-NNN`, `# rationale: ADR-NNN`) are fine — the rule targets prose, not finger-pointers. See `wf-skill-spec-references/references/ears-syntax.md` §Where reasoning lives.
- **Complementary pairs.** Every event-driven/state-driven REQ has an
  unwanted-behavior counterpart OR explicit "no unwanted case" annotation.
- **Exposes contracts (where present).** Structured `exposes:` entries (with
  `signature`, `preconditions`, etc.) have all five DbC fields or empty arrays
  with rationale. Plain string entries are fine for data types and trivial
  helpers — don't flag them.
- **No hidden DbC clauses.** A `demanding`-style interface should not imply
  defensive checks in implementation; a `tolerant`-style interface should cover
  bad inputs via typed errors.
- **constraints present.** Every component declares `max_source_files` and
  `max_exported_symbols`, or the absence is justified in `notes:`.

Project-level checks on `COMPONENTS.yaml`:

- **dependency_rules section present.** Even an empty list `[]` is acceptable;
  missing field is a finding.
- **No circular dependencies.** Walk the `depends_on` graph; cycles are blocks.

#### Conventions block (top-level `conventions:`)

Block is optional but, when present, every entry is validated:

**Mechanical checks:**

- `id` matches `CONV-\d+`, unique within the block.
- `rule`, `rationale`, `enforced_by`, `applies_to` non-empty.
- `enforced_by` is one of `lint | ci-script | review | nothing`.
- `traces_to` (if present) — every entry is a resolvable ADR id.

**Judgement-call checks:**

- **Convention atomicity.** One rule per entry. Compound rules joined by "and"
  → split.
- **Rationale cites a driver.** "Single seam for auth headers" is concrete;
  "good practice" is not.
- **No REQ paraphrase.** Heuristic — flag a convention `rule` that closely
  paraphrases a REQ `statement` (or vice versa). Author chose the wrong slot
  for one of them.
- **`enforced_by: "nothing"` is a warn.** Acceptable in transitional states;
  surfaced so the convention gets a real handle on next iteration.

See `skills/wf-skill-spec-references/references/conventions.md` for the
full field shape and slot-boundary tests.

### Category 3 — Per-artifact rigor (ADRs)

For each ADR file under `paths.adrs`:

- **Three-condition threshold holds.** Load-bearing AND ≥2 real options AND
  contingent on changeable assumptions. See
  `skills/wf-skill-spec-references/references/adr-threshold.md`.
- **Context cites a specific driver.** A REQ id, NFR, external constraint, or
  incident. Not generic praise. "Clean / scalable / idiomatic" without a cited
  driver = reject.
- **≥2 real alternatives** with one-paragraph trade-off reasoning each.
- **Decision is one sentence.**
- **Consequences both signs.** At least one positive AND at least one negative.
- **Reversibility answered.** Rollback path with cost OR named sign-off authority.
  "Hard to reverse" without specifics is not an answer.
- **`governs_components` non-empty.** Every accepted ADR lists at least one
  component it shapes.
- **Superseded ADRs marked.** If `supersedes:` is set, the named ADR's
  `superseded_by:` field is filled (and vice versa). Both sides consistent.
- **Status valid.** `proposed | accepted | superseded | deprecated` — no
  freeform statuses.
- **Accepted ADRs are ratified by a REQ trace.** For every `status: accepted`
  ADR, at least one REQ in any of its `governs_components` (or any SYS-REQ)
  carries the ADR in `traces_to`. An accepted ADR with no inbound REQ trace
  is a forward-declaration — surface as a warn so the SA either adds the
  missing trace or demotes the ADR to `proposed`. See
  `skills/wf-skill-spec-references/references/adr-threshold.md` §When proposed is the right status.

### Category 4 — Cross-artifact consistency

Neither SA nor SwA performs cross-artifact verification on their own — this
category is the arbitrator's unique contribution.

**Mechanical checks (covered by `check_spec_links.sh` in producer's Phase 5 pre-flight — listed for reference, not re-run here):**

- `traces_to` resolution and tier discipline (no SYS-REQ ids in component-REQ
  `traces_to`; SYS-REQ-to-SYS-REQ peer traces allowed)
- `derives_from` ↔ `allocated_to` symmetry, both directions
- `governs_components` ↔ `governed_by_adrs` symmetry, both directions
- `supersedes` ↔ `superseded_by` symmetry
- `depends_on` resolution and cycle detection
- All component/ADR references resolve (no ghosts)

**Judgement-call checks (require human/LLM reasoning):**

- **ADR drivers cite real REQs.** Read each ADR's Context section; if it cites
  a `REQ-NNN`, that REQ must exist in `COMPONENTS.yaml`. (The script can't
  read Markdown prose; this is an arbitrator check.)
- **Roadmap trace integrity (when roadmap exists).** Pick three REQs at random;
  each `traces_to` entry that looks like a capability id (`CAP-NNN`) or external
  constraint id (`EXT-NNN`) must resolve to a matching entry in `roadmap.yaml`.
  Stale traces are warns (the roadmap may have been edited);
  broken-and-not-superseded traces are blocks.
- **Master backlog coverage (when backlog exists).** Every component touched by
  the next pending sprint has at least one REQ. A backlog item modifying a
  component with no REQs is a warn — SwA will write task contracts against
  nothing.
- **Glossary / term consistency.** Domain terms used differently across REQs
  and exposes (e.g., "user" sometimes means session principal, sometimes means
  a record) — warn per occurrence.

### Category 5 — ADR threshold spot-check

Pick three ADRs (or all, if fewer). For each, apply the three-condition
threshold from scratch — do not trust the SA's prior judgement:

- **Load-bearing?** What would breaking this ADR actually affect? If "nothing
  beyond a single file," the ADR doesn't earn its place. Recommend demotion
  (move the decision into a component's `notes`).
- **≥2 real options?** Were the alternatives in the ADR genuinely considered?
  If one alternative is obviously absurd, count it as one real option.
- **Contingent?** If the decision rests on physical laws or a permanent
  business commitment, it's a fact, not an ADR.
- **Convention-as-ADR?** An ADR whose Decision is a one-line code rule and
  whose Alternatives section is thin (one real option, "do nothing", or
  obviously rejected straw alternatives). The rule belongs in the
  `conventions:` block. Warn with a suggested migration target.

Failures here are warns by default — the SA may have judged correctly with
context you don't have. 3+ warns on this check aggregate to a REJECTED with a
recommendation to apply the threshold more strictly.

### Category 6 — Meta-gate (Spec Ambiguity Test)

Final pass. For the combined artifact set:

> Could the Software Architect (SwA) take `COMPONENTS.yaml` + the ADR set and
> produce per-leaf task contracts (acceptance criteria, files_to_touch,
> testing_mandate, out_of_scope) without needing to ask clarifying questions?

Specifically:
- SwA needs measurable acceptance criteria per task — can these be derived from
  REQ `acceptance_criteria` without guessing?
- SwA needs interface contracts to test against — are DbC clauses present where
  task contracts will need them?
- SwA needs `out_of_scope` boundaries — are component `depends_on` and
  `dependency_rules` clear enough to enforce them?

If "no, SwA would need to ask X" — finding raised. The ambiguity is fixable
inside SA's mandate; raise as REJECTED.

---

## Findings shape

When verdict is REJECTED, write `arbitrator_feedback.yaml` per
`assets/arbitrator_feedback.yaml.tmpl`. The template carries every field, every enum, and
the retry-count requirement.

Severity rules (full table in `references/finding-taxonomy.md`):

- `block` — REJECTED on its own. SA must fix.
- `warn` — accumulates. 3+ warns = upgraded to REJECTED.

---

## Loop discipline

- **Retry cap.** SA fix mode is capped at 3 attempts. After 3 consecutive
  REJECTED verdicts on the same artifact set, escalate to human via
  `arbitrator_escalation.yaml` with `target_layer: human` and reason "3-retry
  cap exceeded — systemic issue". The pipeline does not auto-retry past 3.
- **Same finding twice = fix-mode bug.** If finding `F-NNN` appears in two
  consecutive `arbitrator_feedback.yaml` files, raise a `meta-finding` flagging
  that SA's fix didn't take. May indicate the finding text was unclear.

## Per-iteration check budget (fix mode)

Don't re-do checks the previous iteration approved:

1. Read previous `arbitrator_feedback.yaml`.
2. For each prior finding, verify it has been addressed in the current artifact
   state. If not addressed, re-raise with a `meta-finding` annotation.
3. Run only **categories that had findings** previously, unless the fix may have
   introduced regressions in untouched categories (e.g., a fix that adds an
   interface affects Category 2 DbC checks).

This keeps fix-mode reviews cheaper than greenfield reviews.

---

## Output signal

- Success: `ARBITRATOR APPROVED — components=<N>, adrs=<M>, warns=<W>`
- Reject:  `ARBITRATOR REJECTED — findings=<N> blocks + <M> warns`
- Escalate: `ARBITRATOR ESCALATE — target=<layer>`

On any halt: `ARBITRATOR HALT: <reason>`.

---

## Halt conditions

- **`COMPONENTS.yaml` missing or malformed YAML** — cannot verdict; halt and ask.
- **`paths.adrs` directory missing** — halt; SA should have scaffolded it.
- **In fix mode but no previous `arbitrator_feedback.yaml`** — don't guess; halt.
- **Schema validation throws** — halt; the orchestrator runs schema validation
  separately, the arbitrator assumes schema-valid input.

---

## What this skill does NOT do

- Does not modify `COMPONENTS.yaml` or any ADR file. Read-only on those.
- Does not verdict the roadmap. Strategist self-checks its own output.
- Does not verdict impl contracts (`sprint.yaml`). That's SwA's self-check
  or `wf-review` downstream.
- Does not block the pipeline mid-sprint. Arbitrator runs only at the SA boundary,
  before SwA picks up the artifacts. Once a sprint is underway, the arbitrator
  does not re-verdict mid-flight.

---

## References

- `references/finding-taxonomy.md` — finding fields, severity rules, anti-pattern catalogue
- `references/verdict-decision-table.md` — decision rules for APPROVED / REJECTED / ESCALATE
