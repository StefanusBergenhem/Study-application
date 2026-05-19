# Default mode — Sprint Planning Workflow

Triggered when no DI routing context is present. The job: take the next sprint cut from `paths.master_backlog`, dig into the actual source code of affected components, and produce a detailed `paths.sprint` with full task contracts ready for the automated pipeline.

The universal contract-authoring discipline (grouped testing, traceability, scope-consistency, behavior-level mandate wording, etc.) lives in `SKILL.md` and applies throughout this flow. The procedure below covers the planning-specific steps only.

---

## Step 1 — Identify Next Sprint

1. Read `paths.master_backlog`.
2. Find the first sprint with status not `done` — this is the next sprint to detail.
3. Read all items in that sprint group.
4. Read `paths.components`. For each component touched by the sprint, note its `requirements` (REQ-NNN ids + acceptance criteria) and `exposes` (DbC clauses where present). These are the spec-layer handles your task contracts will reference.
5. Read the ADRs governing the touched components — follow each component's `governed_by_adrs:` list to find files under `paths.adrs`. ADRs hold the original reasoning for design decisions; use them when writing `implementation_notes` so the developer respects the rationale, not just the current code.

---

## Step 2 — Source Code Analysis

For each backlog item in the sprint:

1. **Read the component's source code.** Navigate to the component's `path` from `paths.components`. Read entry points, key interfaces, type definitions, and test files.

2. **Validate the SA's assumptions.** Does the backlog item's `rough_scope` match reality? Are the interfaces the SA assumed actually there? Are there hidden complexities?

3. **Identify files to touch.** Based on the actual code structure, determine exactly which files need to be created or modified. Apply the sizing rules from `task_sizing` in config (defaults shown):
   - Max `task_sizing.max_files_to_touch` files per task (default: 3)
   - Max `task_sizing.max_estimated_lines` lines of net new code per task (default: 150)
   - Max `task_sizing.max_context_files` context files per task (default: 5)

4. **Split if necessary.** If a backlog item exceeds sizing limits, split it into sub-tasks (e.g., `S1.1.1`, `S1.1.2`). Each sub-task must be independently completable and verifiable.

5. **Check cross-component impacts.** Does this change affect other components through shared types, interfaces, or imports? If yes:
   - If the impact is within dependency rules: include affected files in `files_to_touch` or note as a separate task.
   - If the impact violates dependency rules: flag as a design issue (see Step 5).

---

## Step 2b — Consult Memory

If `paths.memory` exists, read it. Apply relevant lessons when producing task contracts:

1. **`contract_patterns` lessons** — apply universally. Rules about contract quality learned from past failures.
2. **`component_rules` lessons** — apply per-component. Match the lesson's component against the task's component.
3. **`rejection_patterns` lessons** — use to tighten acceptance criteria and out_of_scope boundaries.
4. **`architecture_signals` lessons** — inform risk ratings and implementation notes.

If the memory file doesn't exist, proceed without it — do not fail or warn.

---

## Step 3 — Produce Task Contracts

For each task (including splits), produce a full contract. The contract references the persistent spec layer by id — `requirements_extract` quotes the relevant REQ statements + acceptance criteria, `parent_interface` quotes the relevant DbC block from the component's `exposes`. Build and review agents work from the slice, never the whole spec layer.

For the complete field list and field-level comments, see `assets/sprint.yaml.tmpl` (full schema for a task entry inside `sprint.yaml.tasks`).

Minimal example showing the spec-layer slice and AC↔REQ tracing (the parts most easily gotten wrong):

```yaml
- id: "S1.1"
  title: "Validate bearer tokens in auth middleware"
  component: "auth"

  # Slice of the persistent spec layer. Verbatim from components.<name>.
  requirements_extract:
    - id: REQ-AUTH-001
      statement: "When given a valid bearer token, the system shall return the decoded user identity within 50ms p95."
      acceptance_criteria:
        - "Tokens signed with the project's RS256 key are accepted."
        - "Expired tokens are rejected with AuthExpiredError."
        - "Tampered tokens are rejected with AuthInvalidError."

  parent_interface:
    - name: AuthMiddleware.Validate
      postconditions:
        on_success:
          - "Returned User.id matches the token's `sub` claim."
        on_AuthExpiredError:
          - "Token's `exp` claim is in the past."
        on_AuthInvalidError:
          - "Signature verification failed."
      typed_errors:
        - { name: AuthExpiredError, when: "Token's exp claim is in the past." }
        - { name: AuthInvalidError, when: "Signature verification failed." }
      style: tolerant

  # Each AC carries a (REQ-NNN) handle that traces into requirements_extract.
  acceptance_criteria:
    - "AC-1 (REQ-AUTH-001): RS256-signed tokens return User with id == sub claim."
    - "AC-2 (REQ-AUTH-001): Expired tokens return AuthExpiredError; user store unchanged."
    - "AC-3 (REQ-AUTH-001): Tampered tokens return AuthInvalidError; user store unchanged."

  implementation_notes: |
    Implements parent_interface AuthMiddleware.Validate per REQ-AUTH-001.
    ADR-007 (governs auth) constrains us to RS256 — do not introduce new
    signing algorithms.
```

Apply every rule in `SKILL.md` § Universal contract-authoring discipline — grouped testing for multi-target tasks, scope-consistency between `testing_mandate` and `files_to_touch`, per-field assertions for enumerated ACs, defensive-branch coverage, stored-data-integrity rules, behavior-level mandate wording.

---

## Step 4 — Validate Component Boundaries

For each task contract:

1. Verify all `files_to_touch` belong to the declared component per `paths.components`.
2. Verify no `files_to_touch` are in a component the task doesn't own.
3. Verify import directions comply with `dependency_rules`.
4. Verify the task doesn't force modification of a stable component's internals when an extension point exists or could be introduced (Open/Closed).
5. Verify interface changes don't bloat an existing interface with unrelated methods (Interface Segregation).
6. If any validation fails, flag as a design issue (Step 5) rather than silently adjusting.

---

## Step 5 — Flag Design Issues

If you discover design-level problems during source analysis, **classify the defect** before writing. Load `wf-skill-spec-references/references/design-issues.md` and apply the mechanical classification check. Then write a DI entry to `paths.design_issues`:

```yaml
issues:
  - id: "DI-NNN"
    detected_by: "software_architect"
    task_id: "S1.3"
    fix_kind: "contract_amendment"    # or spec_amendment | unknown
    level: "software_architect"       # advisory; or solution_architect for spec_amendment
    summary: "<one-line description>"
    impact: "Task S1.3 blocked"
    status: "open"
```

**Detection criteria** (orient classification — final routing is `fix_kind`):

- A task requires importing from a component that dependency rules forbid → likely `spec_amendment` (dependency_rules need updating) or `contract_amendment` (task wrongly scoped).
- The component's `requirements` or `exposes` in `paths.components` conflict with the backlog item → `spec_amendment`.
- The actual code structure doesn't match `paths.components` declarations → `spec_amendment`.
- A shared type change would cascade beyond the 3-file limit and cannot be reasonably split → `contract_amendment` (task needs splitting differently) or `spec_amendment` (boundary needs revising).
- An interface declared in `exposes` doesn't actually exist in the source code → `spec_amendment` (spec drift).
- A task requires modifying a stable component's internals when an extension point would fit → `spec_amendment` (architectural decision).
- A task adds unrelated methods to an existing interface (ISP violation) → `spec_amendment`.
- A task's scope spans multiple unrelated responsibilities (SRP violation) → `spec_amendment` (component boundary).

Design issues do NOT block sprint creation. Mark affected tasks with `status: "blocked"` and a note referencing the DI id. Other tasks proceed normally.

---

## Step 6 — Determine Task Dependencies

For each task, determine which other tasks in the sprint must complete before it can start. Populate `depends_on` with those task IDs.

**Dependency exists when:**
- Task B modifies a file that Task A creates (B depends on A).
- Task B's `context_to_load` includes a file that Task A creates or modifies in `files_to_touch`.
- Task B extends an interface or type that Task A introduces.
- Task B's tests require functionality that Task A implements.

**Dependency does NOT exist when:**
- Tasks touch different files in the same component (parallel within component is fine).
- Tasks share read-only context files (both loading the same existing file).
- The relationship is merely thematic (same feature area but independent work).

**Rules:**
- Check every pair of tasks — do not assume independence.
- Keep the graph as shallow as possible. If A and B are truly independent, leave `depends_on: []` so they run in parallel.
- Detect cycles — if you find a circular dependency, split one of the tasks to break it.

**Atomic type dependency detection:**

When a task **narrows, removes, or renames** a type member (union member, enum value, struct field, interface method), scan for all consumers across the codebase. If consumers exist in files outside the task's `files_to_touch`, those consumer updates MUST be either:

1. Included in the same task (request a sizing waiver if this exceeds `max_files_to_touch`), OR
2. Placed in a task that `depends_on` the type-change task — **but only if the type-change task leaves the codebase in a compilable state** (e.g., the type is widened first, then consumers migrate, then the type is narrowed).

**If neither option preserves compilability at every stage boundary, merge the type change and all its consumers into a single task.** A sizing waiver is preferable to a broken intermediate state. Document the waiver reason in `implementation_notes`.

If the consumer count makes a single task impractical (10+ files), flag as a design issue — the type boundary may need refactoring (e.g., introduce an adapter layer) before the removal can proceed safely.

The orchestrator uses `depends_on` to compute parallel execution stages via topological sort.

---

## Step 7 — Assemble sprint.yaml

Combine all task contracts into `paths.sprint`:

```yaml
sprint_id: "S1"
goal: "Sprint goal from master backlog"
source_backlog_sprint: "S1"
created_at: "YYYY-MM-DDTHH:MM:SS"

tasks:
  - id: "S1.1"
    # ... full contract
  - id: "S1.2"
    # ...
```

---

## Step 8 — Present for Approval

Present to the human:

- Sprint summary (goal, task count, total scope estimate).
- Per-task summaries (what, why, approach, scope, risks).
- Any design issues found.
- Any tasks that were split and why.
- Dependency graph showing `depends_on` relationships.
- **Stage preview**: group tasks into stages (Stage 1 = no deps, Stage 2 = depends only on Stage 1, etc.) so the human can verify the parallelization plan before the orchestrator computes it.

Wait for human approval before writing.

---

## Step 9 — Write Artifacts

On approval:

1. Write `paths.sprint`.
2. Append any new DIs to `paths.design_issues`.

Then proceed to commit per `SKILL.md` § Commit hygiene. Subject convention:

```
<project-prefix> SwA — detail Sprint <id> (<N> tasks, <M> stages)

• <brief rationale for any task splits, sizing waivers, or design issues>
• Design issues: <DI-id list or "none">
```

Suggested next step on report: typically `/wf-skill-orchestrate` if the sprint is ready to execute, or the human's own next move if design issues block it.
