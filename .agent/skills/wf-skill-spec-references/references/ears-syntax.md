# EARS-light Syntax

Easy Approach to Requirements Syntax (Mavin). Five canonical forms. "Light" means
we use the forms but don't enforce verbose template variants.

## The five forms

### 1. Ubiquitous

Always applies, no trigger or condition.

> **The system shall** `<response>`.

*The system shall persist user credentials in encrypted form.*

### 2. Event-driven

Fires when a specific trigger occurs.

> **When** `<trigger>` **occurs, the system shall** `<response>`.

*When the user submits the login form, the system shall validate the credentials within 200ms p95.*

### 3. State-driven

Applies continuously while a state holds.

> **While** `<state>`, **the system shall** `<response>`.

*While a sprint pipeline is running, the system shall reject new sprint dispatch requests.*

### 4. Unwanted-behavior

Handles abnormal conditions explicitly. Always paired with the corresponding
event-driven or state-driven requirement (the "complementary pair" rule).

> **If** `<unwanted-condition>`, **then the system shall** `<response>`.

*If the credential validation service is unreachable, then the system shall return
error code AUTH_UPSTREAM_UNAVAILABLE and not retry automatically.*

### 5. Optional-feature

Applies only when an optional feature is enabled.

> **Where** `<feature-enabled-condition>`, **the system shall** `<response>`.

*Where the audit-logging feature is enabled, the system shall emit a structured event for every authentication attempt.*

## Complementary-pair rule

For every event-driven or state-driven requirement, ask: "What if the trigger
doesn't occur, or the state doesn't hold?" If "nothing happens" — fine. If
there's a real unwanted condition — write the unwanted-behavior counterpart.

Missing complementary pairs are the most common state-coverage gap.

## NFR five-element rule

Non-functional requirements (performance, security, reliability, etc.) must be
measurable. Each NFR carries:

1. **Subject** — what is being measured (`response time`, `throughput`).
2. **Metric** — the unit (`milliseconds`, `requests-per-second`).
3. **Threshold** — the numeric bound (`≤200`, `≥1000`).
4. **Condition** — the operating point (`under load X`, `with N concurrent users`).
5. **Source** — where the threshold came from (`SLA contract`, `engineering judgment`).

If any element is missing, the NFR isn't yet measurable. Mark with `[DEFER-NUMERIC: <reason>]`
inline — don't fabricate a number.

In COMPONENTS.yaml, NFRs carry the structured `nfr_elements:` sub-block:

```yaml
- id: REQ-AUTH-002
  type: nfr
  statement: "While serving traffic, the system shall keep token-validation
    latency at or below 50ms p95 under 200 concurrent requests."
  acceptance_criteria:
    - "p95 < 50ms during a 5-minute load test at 200 RPS."
  nfr_elements:
    subject:   "token-validation latency"
    metric:    "wall-clock milliseconds, p95"
    threshold: "≤ 50ms"
    condition: "200 concurrent requests, 5-minute window"
    source:    "engineering judgment + SLA target"
  traces_to: [REQ-AUTH-001]
```

## Acceptance criteria — per-type policy

`acceptance_criteria` is a list of test handles — what a test must demonstrate
for the requirement to be considered satisfied. Whether it's required depends
on the REQ type. The principle: every REQ has a verification handle, but the
handle isn't always a separate AC list — for some types, another field already
provides it.

| REQ `type`             | AC policy   | Verification handle                                          |
|------------------------|-------------|--------------------------------------------------------------|
| `functional`           | **Required** | The AC bullets themselves.                                  |
| `nfr`                  | Optional    | `nfr_elements` (subject, metric, threshold, condition, source). |
| `invariant`            | Optional    | The statement itself — invariants are written as testable predicates. |
| `data`                 | Optional    | The statement plus the declared shape (struct fields, types). |
| `interface`            | Optional    | The matching `exposes:` entry's DbC clauses (preconditions, postconditions, typed_errors, invariants). |
| `inherited-constraint` | Optional    | The cited source plus AC if the local manifestation needs specifics. |

**When AC is required (functional):** A downstream test author must be able to
write a failing test from each AC bullet alone, without re-reading the
statement.

Good: *"For 1,000 concurrent users, the median response time is ≤180ms and p99 is ≤250ms over a 5-minute window."*

Bad: *"The system performs well under load."*

**When AC is optional, write it only when it adds specifics** the primary
handle doesn't carry:

- *NFR* — write AC only when you need to verify a related property the
  `nfr_elements` block doesn't capture (e.g., a warm-up exclusion, a
  fail-open behavior under load).
- *Invariant* — write AC when the invariant decomposes into more than one
  distinct check that a single statement can't carry cleanly (e.g., an
  append-only audit invariant decomposes into "every mutation writes a row"
  + "no UPDATE/DELETE path exists" + "queryable by ID + time range").
- *Data* — write AC when the shape constraint has specifics not in the
  statement (path, import threshold, field shape).
- *Interface* — write AC when there's a behavioral guarantee the DbC clauses
  don't capture (e.g., side-effect ordering, observable telemetry).

**Anti-pattern: AC that paraphrases its handle.** If your AC bullet restates
the statement, repeats `nfr_elements.threshold`, or paraphrases a DbC
postcondition, drop it. Redundancy creates drift — the two phrasings will
fall out of sync.

Examples of redundant AC the arbitrator warns on:

```yaml
# Redundant — AC paraphrases nfr_elements
- id: REQ-API-001
  type: nfr
  statement: "While serving traffic, the system shall keep p95 latency ≤ 50ms."
  acceptance_criteria:
    - "p95 < 50ms under load."        # already in nfr_elements.threshold
  nfr_elements:
    threshold: "≤ 50ms"

# Redundant — AC paraphrases invariant statement
- id: REQ-DOM-007
  type: invariant
  statement: "The User type is defined once and imported by every component."
  acceptance_criteria:
    - "User is defined in one place and imported by every component."   # same sentence

# Redundant — AC paraphrases DbC postcondition
- id: REQ-AUTH-009
  type: interface
  statement: "..."
  acceptance_criteria:
    - "Returns a User object with id matching the token's sub claim."   # already in exposes[*].postconditions.on_success
```

## What NOT to write

- **Compound requirements.** One statement, one obligation. If your sentence has
  "and" between two obligations, split them.
- **Smuggled design.** No requirement names a library, framework, algorithm, or
  specific technology. *"The system shall use PostgreSQL"* is design, not
  requirement — that belongs in an ADR.
- **Subjective adjectives.** No "fast", "scalable", "secure", "user-friendly"
  without a measurable handle.
- **Per-statement rationale.** No paragraph of "we chose this because...". That
  belongs in ADRs. At most a one-line `intent:` field if absolutely needed for
  disambiguation.
- **Conventions disguised as REQs.** If your "shall" sentence describes how the
  code is organized — *"shall route every call through X"*, *"shall use raw Y"*,
  *"shall not call Z directly"*, *"all migrations shall use .up.sql"* — it is a
  convention, not a behavior the system promises to its users or callers. Put
  it in the top-level `conventions:` block. See `conventions.md`.

## Inherited constraints

If a requirement is purely a re-statement of an external constraint (carrying down
a rule without modifying it), mark it `type: inherited-constraint` and link via
`traces_to` to the source (ADR id, roadmap external-constraint id `EXT-NNN`,
or external standard).

## Where REQs live in wf — two tiers

`COMPONENTS.yaml` carries requirements in **two tiers**. Both follow EARS
syntax; what differs is scope and namespace.

### Tier 1 — `system_requirements:` (top-level block)

ID space `SYS-REQ-NNN`. Lives at the top of `COMPONENTS.yaml`, before
`components:`. Used for requirements whose obligation cannot be honoured by
any single component alone:

- **User/operator-visible behavior** crossing more than one component
  (login flow, validation flow, search flow — the user does not care which
  module returns the result, only that the system returns it).
- **Cross-cutting NFRs** (end-to-end latency, throughput, system uptime,
  data durability). Allocation across components becomes a budget exercise.
- **System-wide invariants** that every component must respect (canonical
  type definitions, security posture, audit-log presence, glossary terms).

Each SYS-REQ carries an `allocated_to:` field naming the components that
implement (some slice of) it.

```yaml
system_requirements:
  - id: SYS-REQ-001
    type: functional                     # functional | nfr | invariant
    statement: "When an operator submits credentials, the system shall return
      a session token within 200ms p95."
    acceptance_criteria: [...]
    allocated_to: [api-gateway, auth]    # one or more components
    traces_to: [CAP-001]                 # roadmap capabilities, external constraints, and/or ADRs
```

### Tier 2 — `components[*].requirements` (per-component)

ID space `REQ-<COMP>-NNN`. Lives under each component. Used for:

- **Interface contracts** (what this component promises to its callers).
- **Component-local obligations** that one component owns end-to-end and
  whose failure mode is internal to that component.
- **Allocation slices** of a SYS-REQ — the portion of a system requirement
  this component is responsible for. The allocation is marked with
  `derives_from: [SYS-REQ-NNN]`.

```yaml
components:
  auth:
    requirements:
      - id: REQ-AUTH-001
        type: functional
        statement: "When given a valid bearer token, the system shall return the
          decoded user identity."
        acceptance_criteria: [...]
        derives_from: [SYS-REQ-001]      # mirror of allocated_to on SYS-REQ-001
        traces_to: [CAP-002]
```

### `traces_to` vs `derives_from` vs `allocated_to`

- `traces_to` — upward link to **roadmap capabilities (CAP-NNN)**, **external constraints (EXT-NNN)**, **ADRs**, or **peer REQs**
  (the rationale or causal driver). Every REQ at either tier has at least one.
  **On a component REQ, SYS-REQ ids are forbidden in `traces_to`** — they go
  in `derives_from`, which carries stronger semantics (formal allocation). On
  a SYS-REQ, peer-lineage references to other SYS-REQs in `traces_to` are
  allowed (e.g., an NFR SYS-REQ that traces to the functional SYS-REQs whose
  behavior it qualifies). The arbitrator blocks on SYS-REQ ids appearing in
  component-REQ `traces_to`.
- `derives_from` — link from a **component REQ** to a **SYS-REQ** that it
  allocates. Optional; present only when the component REQ is implementing
  a system-level promise. This is the formal allocation link.
- `allocated_to` — link from a **SYS-REQ** to the **components** that implement
  it. Mirror of `derives_from` aggregated upward. The arbitrator checks
  symmetry — if SYS-REQ-001 lists `allocated_to: [auth]`, then `auth` must
  have at least one REQ with `derives_from: [SYS-REQ-001]`.

### Tier placement decision tree

When you write a new REQ, ask in order:

1. **Is the obligation honoured by a single component end-to-end?** — Yes → Tier 2 (component REQ). Done.
2. **Does at least one user/operator/external system observe the outcome directly?** — Yes → Tier 1 (SYS-REQ functional).
3. **Is it a measurable cross-component NFR (end-to-end latency, total throughput, system-wide reliability)?** — Yes → Tier 1 (SYS-REQ nfr).
4. **Is it a rule every component must respect (canonical type, glossary term, security posture)?** — Yes → Tier 1 (SYS-REQ invariant).
5. Otherwise → Tier 2.

Most REQs land in Tier 2. Tier 1 stays small — a healthy system has roughly
0.5–2 SYS-REQs per top-level roadmap capability. If Tier 1 grows faster than
the component count, you're using it for things that belong in Tier 2.

### Anti-patterns

- **Allocating an invariant to one component without any cooperating party.** If
  only one component is involved, it's a component REQ. Don't elevate it.
- **SYS-REQ that names a specific implementation detail.** "The system shall use
  RS256 for token signing" is a decision (ADR), not a requirement.
- **Duplicating a SYS-REQ as a near-identical component REQ.** The component
  REQ should describe the *slice* (this component's piece), not restate the
  system promise. The system promise lives at Tier 1 once.
- **Tier 1 NFR without `allocated_to`.** Cross-cutting NFRs that aren't
  allocated cannot be tested or budgeted. Either allocate to specific
  components, or downgrade to component REQ.

### Where reasoning lives

Spec files describe **current** state — what the system promises now.
Historical narration ("we used to require X, then ADR-019 changed it to Y
because Z") belongs in commit messages, resolved design-issue entries, and
ADR bodies — not inline in the REQ/AC/exposes block. If a future reader of
the spec needs the rationale, they get a **pointer** to where it lives
(`# see DI-NNN`, `# rationale: ADR-NNN`), never the prose itself. One-line
pointers are fine; multi-line prose comments are not. The arbitrator
surfaces multi-line inline comments as a warn so the discipline holds
across sessions.
