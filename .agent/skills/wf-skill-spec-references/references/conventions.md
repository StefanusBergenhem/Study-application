# Conventions

Repository-hygiene rules that aren't user-visible behavior but should be visible
alongside the spec layer. Each carries an id, a rule, a rationale, and an
enforcement handle. Conventions live in `COMPONENTS.yaml` under a top-level
`conventions:` block, peer to `system_requirements:` and `dependency_rules:`.

## Why the block exists

Without a dedicated slot, conventions land in one of three bad places:

- **Smuggled into EARS REQs.** *"The system shall route every HTTP call through
  the api wrapper layer."* The "shall" form misrepresents code-organization
  rules as user-visible behavior. The REQs block bloats and tests can't
  meaningfully assert it.
- **Promoted to full ADRs.** A one-line rule like *"all migrations are up-only"*
  gets the full Context / Decision / Alternatives / Consequences / Reversibility
  template. The substance-to-ceremony ratio is poor and the ADR set fills with
  low-signal entries.
- **Buried in `notes:`.** Free-form prose with no id, no enforcement handle, no
  way to reference from elsewhere. Invisible at review time.

The `conventions:` block is the destination for the rules these three patterns
were trying to capture.

## Lane boundaries

| Slot                         | What it describes                                                                          | Test handle                          |
|------------------------------|--------------------------------------------------------------------------------------------|--------------------------------------|
| `system_requirements`        | What the **system** promises to a user / operator / external caller. Behavior.            | AC bullets or `nfr_elements`         |
| `components[*].requirements` | A component's slice of a SYS-REQ, or a contract its callers can rely on. Behavior.        | AC bullets, DbC clauses              |
| `conventions`                | How the **codebase** is organized. Maintainers' rules — reviewable, sometimes lintable.   | `enforced_by` field (linter / CI / review) |
| `dependency_rules`           | Structural import constraints between components.                                          | Import-graph check                   |
| ADRs                         | Load-bearing decisions where ≥2 real alternatives existed and the assumption is contingent.| Reversibility section                |

A convention may trace to an ADR (when one exists). Most conventions stand
alone — promoting every convention to an ADR is the bloat pattern this block
was introduced to relieve.

## Where REQ ends and convention begins

The destination test, in order:

1. *Does an end user, operator, or external caller observe the outcome?* — REQ.
2. *Does it describe a directional import edge between components?* —
   `dependency_rules`.
3. *Does it describe how the code is organized — file layout, naming, error
   handling style, where a kind of call goes, what's allowed inline?* —
   convention.
4. *Is it a load-bearing decision where reversal would ripple beyond local
   scope AND ≥2 alternatives were genuinely evaluated?* — ADR (the convention,
   REQ, or `dependency_rule` it ratified, if any, traces back to it).

Phrasing tells: *"shall route"*, *"shall use raw"*, *"shall not call inline"*,
*"all migrations are"*, *"no \<technology\> dependency"* — these are
convention-shaped, not behavior-shaped. If the sentence answers *how the
project's code is organized*, it's a convention.

## Field shape

```yaml
conventions:
  - id: CONV-001
    rule: "All HTTP calls to the backend go through the api wrapper layer — no inline fetch() inside components."
    rationale: "Single seam for auth headers, error normalisation, and mocking."
    enforced_by: "review"
    applies_to: ["frontend/src/components/**", "frontend/src/pages/**"]
    traces_to: [ADR-030]
```

### Fields

| Field         | Required | Notes                                                                                                  |
|---------------|----------|--------------------------------------------------------------------------------------------------------|
| `id`          | yes      | `CONV-NNN`. Sequential within the project. Stable across edits — never renumber.                       |
| `rule`        | yes      | One sentence stating the rule. Imperative or declarative — not EARS "shall" form (this isn't a REQ).   |
| `rationale`   | yes      | One sentence on *why*. Cites the driver — past bug, maintenance pain, regulatory rule, architectural posture. |
| `enforced_by` | yes      | One of: `lint` \| `ci-script` \| `review` \| `nothing`. "nothing" is acceptable but flagged for follow-up. |
| `applies_to`  | yes      | List of paths or globs scoping the rule. Use `["**"]` for repo-wide.                                  |
| `traces_to`   | no       | List of ADR ids that ratified or document the convention. Empty when the convention stands alone.     |

### `enforced_by` semantics

- **`lint`** — a linter (eslint, golangci-lint, ruff, clippy, …) flags the rule. State which one in `rationale` or `notes`.
- **`ci-script`** — a project-specific CI check (custom script, drift detector, snapshot diff) enforces the rule.
- **`review`** — humans / reviewer agent enforce. Acceptable for rules too local-context-dependent to mechanize.
- **`nothing`** — recorded but not enforced. Acceptable for transitional rules; the arbitrator emits a warn so the rule gets a real handle on the next iteration.

## Anti-patterns

- **REQ-as-convention.** A `conventions[*].rule` that uses "shall" or describes
  user-observable behavior. Move it to `requirements:` and rephrase.
- **Convention-as-ADR.** A one-line code rule expanded into a full ADR. Use the
  block; if an ADR genuinely ratifies the convention (load-bearing, alternatives
  weighed), keep the ADR thin and let the convention carry the operational text.
- **Duplicate paraphrase.** A REQ statement and a convention rule covering the
  same ground. Pick the right slot, delete the other side. The arbitrator
  warns on near-paraphrases.
- **Missing rationale.** *"All migrations are up-only."* — no *why*. Conventions
  without a rationale rot when the next contributor doesn't know why the rule
  exists.
- **Unscoped `applies_to`.** Every convention scopes to *somewhere*. `["**"]`
  is fine when the rule is genuinely repo-wide; an empty or missing
  `applies_to` is a finding.

## Relationship to `paths.conventions` docs

`paths.conventions` (set in `.workflow/config.yaml`, per-domain) points at
prose convention documents — naming patterns, error-handling style, file
layout — read by the builder and reviewer. Those docs are the *detailed*
home for code-style rules.

`COMPONENTS.yaml`'s `conventions:` block is the *spec-layer summary* of the
rules that have project-wide architectural significance. A convention with an
`id` can be referenced from an ADR's `Context` or from a component's `notes`;
a paragraph in a prose conventions doc cannot.

Use both:

- Project-architectural rules with ids → `conventions:` block.
- Detailed style and pattern catalogue → `paths.conventions` documents.
- Cross-references between them are encouraged.

## Arbitrator checks

Beyond the field-shape checks above:

- Every `traces_to` ADR id exists on disk.
- `id` is unique within the conventions block.
- No REQ statement paraphrases a convention rule (heuristic; warn-level).
- `enforced_by: "nothing"` produces a warn per occurrence (acceptable but
  surfaced for follow-up).
