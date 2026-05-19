# Design Issues — Canonical Shape and `fix_kind` Taxonomy

This document defines the shared shape of a design-issue (DI) entry and the
`fix_kind` taxonomy that drives orchestrator auto-routing on DESIGN_ISSUE
verdicts. Every skill that writes or reads DIs cites this canonical text;
none ships its own copy.

Consumers:

- `wf-skill-build` and `wf-skill-review` — populate `fix_kind` when raising a DI.
- `wf-skill-swa` (fix mode) — consumes DIs with `fix_kind: contract_amendment`.
- `wf-skill-sa` (fix mode) — consumes DIs with `fix_kind: spec_amendment`.
- `wf-skill-orchestrate` — routes DESIGN_ISSUE verdicts by reading `fix_kind`.

Canonical DI artifact template: `wf-skill-sa/assets/design-issues.yaml.tmpl`.

---

## DI entry shape

```yaml
issues:
  - id: "DI-NNN"                       # zero-padded, monotonic per file
    detected_by: "developer"           # developer | reviewer | software_architect | solution_architect
    task_id: "<sprint task id>"        # the task whose contract or spec slice triggered the DI
    fix_kind: "contract_amendment"     # see "fix_kind taxonomy" below
    level: "software_architect"        # advisory: who is expected to author the fix
    summary: "<one-line problem statement>"
    impact: "<scope of what the DI blocks>"
    status: "open"                     # open | routing | resolved | overridden
    # Optional fields populated by the orchestrator:
    routed_to: "<wf-swa | wf-sa>"      # filled when status flips to routing
    routed_at: "<ISO-8601>"
    resolution_commit: "<sha>"         # filled when status flips to resolved
```

`level` is a backward-compatible advisory field; `fix_kind` is the
load-bearing routing field. When both are present, `fix_kind` wins for
orchestrator routing decisions. When only `level` is present (legacy DIs
written before the schema migration), the orchestrator HALTs for human
triage rather than guessing the route.

---

## `fix_kind` taxonomy

Three values. The producer (build / review / SwA / SA) selects one by
applying the **mechanical classification check** below before writing the
DI.

### `contract_amendment`

The defect lives in `paths.current_task` (or its source in `paths.sprint`):
a defective AC text, a wrong `testing_mandate` target, a missing entry in
`files_to_touch`, a malformed `parent_interface` slice, etc. The parent
REQ/AC/DbC in `paths.components` reads correctly; the task contract has
diverged from it.

- **Detection**: the producer compares the relevant `requirements_extract`
  / `parent_interface` slice in `paths.current_task` against the source
  REQ/AC/DbC in `paths.components`. If the spec reads correctly and the
  contract slice has the defect, this is a `contract_amendment`.
- **Routes to**: `wf-swa` fix-mode. SwA amends `paths.sprint` only and
  commits.
- **Examples**:
  - AC mandates an assertion on field X but no merged code path writes
    field X.
  - `testing_mandate.unit_tests[i].target` names a file not in
    `files_to_touch`.
  - `parent_interface` quotes a DbC clause that doesn't exist in the
    component's `exposes`.

### `spec_amendment`

The defect lives in the upstream REQ/AC/DbC itself in `paths.components`,
or in an ADR under `paths.adrs`. The task contract correctly reflects what
the spec says; the spec says something unsatisfiable, contradictory, or
wrong.

- **Detection**: the producer reads the REQ/AC/DbC in `paths.components`
  and confirms the task contract slice matches it verbatim. If the defect
  is in the spec itself, this is a `spec_amendment`.
- **Routes to**: `wf-sa` fix-mode. SA amends the spec layer. SA's
  fix-mode session runs the three-condition ADR threshold; if earned,
  SA writes an ADR alongside the spec amendment in the same commit. The
  builder does **not** emit `adr_required` — ADR-vs-no-ADR is SA's
  call at fix time.
- **Examples**:
  - Two REQs in the same component place jointly-unsatisfiable demands
    on a single operation.
  - A DbC `postconditions.on_success` asserts an outcome that contradicts
    a typed-error case.
  - A SYS-REQ's `acceptance_criteria` is missing the measurable handle
    the component-level REQ needs.

### `unknown`

The producer hit a defect it cannot mechanically classify. Either the
classification check is inconclusive (both contract and spec look
plausible, or the defect is downstream of both) or the producer lacks the
information to compare the two.

- **Routes to**: HALT for human triage. The orchestrator does **not**
  guess.
- **Examples**:
  - The component's source code contradicts both the contract slice AND
    the parent REQ in the same way — the spec MAY be wrong, but the code
    may also be wrong; classification needs human judgement.
  - The DI is raised by a reviewer based on a violation type not in the
    classification check criteria (e.g., a cross-component dependency
    rule violation surfaced after build).

---

## The classification check (for producers)

When raising a DESIGN_ISSUE, before writing the DI artifact:

1. Identify the defective assertion in `paths.current_task`'s
   `requirements_extract` or `parent_interface` slice.
2. Locate the source assertion in `paths.components` (or `paths.adrs` if
   the assertion is ADR-derived).
3. Compare the two:
   - **Spec reads correctly, contract slice diverges** → `contract_amendment`.
   - **Contract slice matches spec verbatim, spec itself is the defect** → `spec_amendment`.
   - **Cannot determine, or neither alone explains the defect** → `unknown`.
4. Populate `fix_kind` with the chosen value and write the DI.

The check is intentionally cheap — a single source-text comparison. It is
not a substitute for human judgement on hard cases; producers SHOULD emit
`unknown` rather than guess.

---

## Orchestrator routing (informational; canonical procedure lives in `wf-skill-orchestrate`)

On DESIGN_ISSUE verdict from a build or review agent, the orchestrator
reads the most-recent DI entry's `fix_kind` and dispatches accordingly:

| `fix_kind`            | Dispatched agent            | Human gate? |
|-----------------------|-----------------------------|-------------|
| `contract_amendment`  | `wf-swa` (mode: fix)        | No          |
| `spec_amendment`      | `wf-sa` (mode: fix)         | No          |
| `unknown` or absent   | (none — orchestrator HALTs) | Yes         |

After the dispatched fix-mode session commits and flips the DI status to
`resolved`, the orchestrator re-dispatches the original task at its
current attempt count. ADR creation, if earned, is part of the
`spec_amendment` path — never a separate routing value at the builder
layer.
