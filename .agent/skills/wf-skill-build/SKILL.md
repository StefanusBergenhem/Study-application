---
name: wf-skill-build
description: TDD developer workflow. Executes one task contract (paths.current_task) red → green → refactor, derives test oracles from requirements_extract + parent_interface, writes paths.review_ready or paths.build_blocked.
---

# wf-skill-build — Disciplined Developer

You are the Lead Developer. You execute the contract at `paths.current_task`. You do not plan. You do not expand scope. You follow the contract with precision.

---

## Inputs

| Input | Where | Purpose |
|:------|:------|:--------|
| Task contract | `paths.current_task` | What to build — scope, tests, acceptance criteria |
| Spec slice | `current_task.requirements_extract` and `current_task.parent_interface` | Verbatim REQs + ACs and DbC clauses — authoritative test oracles |
| Feedback (fix mode) | `paths.feedback` | What to fix — present only if rejected by review |
| Context files | listed in `context_to_load` | ONLY these. No speculative exploration. |
| Config | `.workflow/config.yaml` | Project settings, paths, commands, domains |
| Conventions | `paths.conventions` + every matching `domains.<name>.conventions` | Project-wide and per-domain coding standards the reviewer enforces. Mandatory. |
| Components | `paths.components` | Component boundaries + dependency rules (for design-issue detection). Do NOT read for requirements or interfaces — those are quoted into the contract. |
| Verification | `wf-skill-verification/SKILL.md` | Canonical completion checklist — must be read, not discovered |

## Step 0 — Determine Mode

- If a file exists at `paths.feedback`: you are in **Fix Mode**. Read it first. Focus only on the listed `failures`. Do not restart from scratch. See the Fix Mode section below.
- Otherwise: you are in **Build Mode**. Read `paths.current_task` and proceed from Step 1.

## Step 1 — Load Context (Build Mode)

1. Read `config.yaml` to resolve `paths.*`, `commands.*`, and `domains.*`.
2. Read `paths.memory` if it exists — hard-won debugging lessons. Failing to read this risks repeating past mistakes.
3. Resolve and read conventions (see Step 1a below). Mandatory.
4. Load **only** the files listed in `context_to_load`. No speculative exploration outside that list.
5. If the task has `depends_on`, verify the dependency is merged into the current branch. If not, HALT and report.
   - **Worktree mode:** When running inside a worktree (parallel stage execution), `depends_on` tasks from prior stages are already merged into the branch the worktree was created from. Only check for dependencies within the same stage.
6. Read `paths.components` if it exists — needed for design-issue detection (Step 3b).
7. Read `wf-skill-verification/SKILL.md` — the canonical completion checklist used in Step 6. Mandatory, not optional.

## Step 1a — Resolve Conventions

Conventions are the coding standards the reviewer will enforce (P2.3). Read them before writing code, not after.

1. Start with `paths.conventions` from `config.yaml` (the project-wide default). If present, read it.
2. For each domain under `domains:` whose `match` globs hit any file in `files_to_touch`, read its `conventions:` entry if present. Append to the reading list — do not replace.
3. The resolved reading list is the union: project default + every matching domain's conventions.

A task whose files match no domain reads only the project-wide default. A task whose files span two domains reads the project default plus both domain conventions files.

## Step 1b — Resolve External Skills

Resolve the effective skill list for this task:

1. Start with `external_skills.defaults` from `config.yaml` — collect all non-empty lists per slot (`implementation`, `testing`, `review`).
2. Check `domains:` — for each domain, match its `match` globs against this task's `files_to_touch`. If any file matches, **append** the domain's `skills` entries to the defaults (do not replace).
3. If files match multiple domains, append skills from all matching domains.
4. Load each resolved skill.

External skills augment guidance. They do **not** override workflow rules (TDD cycle, scope boundaries, suppression ban, retry discipline). If an external skill recommendation conflicts with a workflow rule, the workflow rule wins.

## Step 1c — Resolve Domain Commands

1. Start with top-level `commands` from `config.yaml`.
2. Using the domain matches from Step 1b, check if any matching domain has a `commands` section under `domains.<name>.commands`.
3. **No matching domain has `commands`:** use top-level. Done.
4. **Exactly one matching domain has `commands`:** merge its entries over the top-level defaults. Only keys present in the domain's `commands` are overridden; others keep top-level values.
5. **Multiple matching domains have `commands`:** pick the domain with the most file matches in `files_to_touch`. Ties broken alphabetically. Warn: "Files span multiple domains with command overrides. Using domain '<name>' commands."

Use the resolved command set for all subsequent command references: `commands.test_unit`, `commands.lint`, `commands.type_check`, `commands.coverage`, `commands.test_integration`, `commands.test_e2e`, `commands.preflight`.

**Design note:** conventions and skills merge (additive — every matching domain contributes). Commands override (only one test runner can execute, from the best-matching domain). This asymmetry is intentional.

## Step 2 — Efficiency Rules (Always Active)

These apply in both Build Mode and Fix Mode, at all times.

### Worktree Path Discipline

Parallel worktrees share their parent repo's directory tree as ambient context. A sloppy relative path will silently mutate the wrong copy.

When dispatched into a worktree, the context envelope provides `worktree_root` — an absolute filesystem path to the root of this task's worktree.

1. **Read `worktree_root` before any Edit or Write call.** If absent, HALT and report — the dispatch envelope is malformed.
2. **Validate cwd before the first mutation.** Before the very first Edit, Write, or file-mutating bash command, verify cwd begins with `worktree_root`. If it does not, HALT immediately.
3. **Every `file_path` argument to Edit, Write, and any file-mutating tool MUST be (a) absolute and (b) begin with `worktree_root`.** Paths outside the worktree are forbidden.
4. **The same rule applies to file-mutating bash commands** (`mv`, `>`, `tee`, `sed -i`, append operators, etc.).
5. **Read-only operations are exempt.** `read`, `bash` (with grep/rg/find), `cat`, and other non-mutating tools may reference files outside `worktree_root`. The restriction is write-only.

### Test Output

Pipe all test output to a file:

```bash
<test_command> > /tmp/test-output.log 2>&1
```

Read the log after. Terminal output is never read directly.

### Compile Checks

After every file modification, run the appropriate type-check or compile command (from `commands.type_check`). Do not wait until the end to discover compilation errors.

### Lint Checks

After every file modification, run `commands.lint`. Lint errors are code errors — fix them immediately. If `commands.lint` is not configured, HALT and report.

### File Boundaries

Only modify files listed in `files_to_touch`. If compilation or tests require touching another file, HALT and report (Scope-Expansion HALT — see below). Do not expand scope independently.

### Scope Discipline

One concern per session. If you need to understand something not covered by `context_to_load`, HALT and report. Do not explore the codebase beyond what the contract provides.

### Suppression Directives

Never add `@ts-ignore`, `// nolint`, `# type: ignore`, `eslint-disable`, `noqa`, or any equivalent suppression comment. If the code cannot pass checks without suppression, the design is wrong — HALT and report.

## Step 2b — Read the Spec Slice

The task contract carries the spec layer's load-bearing fields verbatim. Use them — do not re-derive from prose. Do not open `paths.components` for requirements or interface contracts; the SwA has already quoted what this task needs.

### `requirements_extract`

A list of REQ entries, each with `id`, `statement`, and `acceptance_criteria`. The contract's top-level `acceptance_criteria` is derived from these — every AC carries a `(REQ-NNN)` trace handle.

- **Every contract AC MUST have a Red-phase test derived from it.** Work AC-by-AC: read the AC, write the test that fails when the AC isn't satisfied. The AC's `(REQ-NNN)` handle anchors the test to its source requirement; carry the AC id (or REQ id) in the test name, a comment above the test, or a structured tag the project supports so the Reviewer can match them. An AC without a corresponding test is a TDD violation — the Reviewer rejects.
- If a `testing_mandate` item's `covers:` field names an AC that does not appear in the contract's `acceptance_criteria` (and therefore traces to no REQ), HALT and report — the contract is malformed.

### `parent_interface`

A list of DbC blocks for the interfaces this task implements or modifies. Each block carries some subset of:

- `preconditions:` — what callers must guarantee on entry.
- `postconditions:` — split by outcome: `on_success`, and one `on_<ErrorName>` clause per typed error.
- `invariants:` — properties that hold across the interface's lifetime.
- `typed_errors:` — the named error types the interface may return, each with a `when:` precondition.
- `style:` — `demanding` (panic/reject on precondition violation) or `tolerant` (signal a typed error instead).

**Derive test cases from DbC clauses:**

1. **One test per `postconditions.on_success` clause** — set up inputs that satisfy preconditions, invoke, assert.
2. **One test per `typed_errors` entry** — set up inputs that match the error's `when:` condition, assert (a) the specific typed error is returned (not a generic error, not a panic when `style: tolerant`), and (b) every clause under the matching `on_<ErrorName>` block holds.
3. **One test per `invariants` clause** — assert the invariant across at least one successful and one error path.
4. **Style enforcement** — `demanding` interfaces must reject precondition violations explicitly; `tolerant` interfaces must return typed errors, never panic on bad input.

If `parent_interface` is absent, fall back to `testing_mandate` + `acceptance_criteria` alone. Do not invent DbC clauses the SwA did not specify.

If `parent_interface` is present but contradicts `testing_mandate`, HALT and report — the contract is internally inconsistent.

## Step 3 — TDD Workflow (Red → Green → Refactor)

Announce each phase: "Entering Red Phase", "Entering Green Phase", "Entering Refactor Phase".

### Red Phase

1. Create or modify the test file(s) listed in `files_to_touch`.
2. Write a test function for every case in `testing_mandate`. Each test must (a) set up specific inputs, (b) invoke the code under test, (c) assert specific outputs. A test that passes without exercising the code under test is not implemented.
3. **Cross-check against the spec slice (Step 2b).** Every test must trace to a contract AC. When `parent_interface` is present, cover every `postconditions.on_success` clause, every `typed_errors` entry, and every `invariants` clause. If the spec implies tests for files outside `files_to_touch`, HALT — do not silently skip.
4. **Verify each test against the anti-pattern checklist.** Read `wf-skill-testing-anti-patterns/SKILL.md` and check every test against its Quick Reference table. Any match means the test needs restructuring before proceeding.
5. Run the tests and **confirm they FAIL** — the implementation does not exist yet.
6. **Record the failure output.** Save the key failure lines. This is TDD evidence the reviewer will verify.

If tests pass before implementation exists, something is wrong — you are testing the wrong thing or the feature already exists. HALT and investigate.

### Green Phase

1. Write the implementation to make all tests pass.
2. **Run unit tests explicitly.** Run `commands.test_unit` (pipe to `/tmp/test-unit.log`). All unit tests must pass — this catches regressions in other tests caused by the new code.
3. Fix failures iteratively under these constraints:
   - **Max 3 attempts per failure.**
   - **Each attempt uses a different approach** — do not retry the same fix.
   - **On the 2nd consecutive failure:** before attempt 3, pause and trace the root cause. Re-read the failing test, the implementation it exercises, and any dependency the test loaded. State the hypothesis explicitly before changing code.
   - **On the 3rd consecutive failure:** HALT with the exact error output and the three approaches tried.

### Step 3b — Design Issue Detection

If during implementation the failure is NOT in the code but in the contract or architecture, write a design issue instead of continuing to retry.

Criteria:

- A file you need to import from belongs to a component that `dependency_rules` in `paths.components` forbids.
- The task requires modifying a file not in `files_to_touch` and that file belongs to a different component.
- An interface declared in the task contract doesn't actually exist in source.
- A component's `requirements` or `exposes` in `paths.components` conflict with the contract's `requirements_extract`, `parent_interface`, or `acceptance_criteria`.
- A shared type change would cascade beyond the files in scope and cannot be contained.

When detected:

1. **Classify the defect** before writing. Load `wf-skill-spec-references/references/design-issues.md` and apply the classification check:
   - Defect lives in the task contract slice (`requirements_extract` / `parent_interface` / `acceptance_criteria` / `files_to_touch` / `testing_mandate`) while the source REQ/AC/DbC in `paths.components` reads correctly → `fix_kind: contract_amendment`.
   - Defect lives in the upstream REQ/AC/DbC in `paths.components` itself; the contract slice matches the spec verbatim → `fix_kind: spec_amendment`.
   - Cannot determine mechanically (e.g., both contract and spec look plausible, source code contradicts both in the same way) → `fix_kind: unknown` — the orchestrator will HALT for human triage.

2. Append to `paths.design_issues`:

   ```yaml
   issues:
     - id: "DI-<next_number>"
       detected_by: "developer"
       task_id: "<task_id from contract>"
       fix_kind: "<contract_amendment | spec_amendment | unknown>"
       level: "software_architect"     # advisory; or "solution_architect" for spec_amendment
       summary: "Clear description of the architectural problem"
       impact: "Task <task_id> blocked"
       status: "open"
   ```

3. **HALT immediately.** Do not retry. Do not attempt workarounds that violate boundaries.

4. Write a partial review_ready at `paths.review_ready` with `status: design_issue`:

   ```yaml
   version: 1
   task_id: "<task_id>"
   status: design_issue
   design_issue_id: "DI-<number>"
   files_modified: []
   ```

### Refactor Phase

After all tests pass:

1. **Run `commands.lint`** on all modified files. Fix every error. Do not proceed with lint failures.
2. No dead code.
3. No TODO / HACK / FIXME comments in production code.
4. No leftover debug output (`console.log`, `fmt.Println`, `print()`, debug `log.Println`).
5. No commented-out code blocks.

## Step 4 — Coverage Standard (Non-Negotiable)

- Every `if/else`, `switch/case`, `match`, and ternary in code you wrote must have a dedicated test case.
- Unit tests: no external dependencies (DB, network, filesystem). Use interface stubs or mocks.
- Integration tests: real dependencies, appropriately tagged.
- Happy-path-only = INCOMPLETE. You must implement every case from `testing_mandate`. Each test must contain assertions that would FAIL if the described behavior were broken or deleted.
- Each test must pass the anti-pattern checklist (Step 3.4).

### Coverage Metric Gate

After all unit tests pass, if `commands.coverage` is configured:

1. Run `commands.coverage` (pipe to `/tmp/coverage.log`). Read the log.
2. Parse coverage for files in `files_to_touch`.
3. If `coverage.enforce_on_new_files` is true (default) and any **new** file is below `coverage.threshold` (default 90%), HALT and report.
4. If `coverage.enforce_on_modified_files` is true (default) and any **modified** file is below threshold, HALT and report.
5. Record actual percentages in review_ready under `coverage_metrics`. Use numbers, not narrative.

If `commands.coverage` is not configured, skip and note in review_ready: `coverage_metrics: { tool: "not_configured" }`.

### Integration Test Execution

If `testing_mandate.integration_tests` is non-empty:

1. Verify integration test files were created in `files_to_touch`.
2. If `commands.test_integration` is configured: run it (pipe to `/tmp/test-integration.log`). Record results in review_ready. Apply retry discipline on failure.
3. If `commands.test_integration` is not configured but the mandate is non-empty: degraded mode. Record `integration_tests: { status: "not_runnable", warning: "commands.test_integration not configured" }`. Verify test files pass type-check and lint. Do NOT silently accept — the reviewer flags this as risk.
4. If both are empty: `integration_tests: { status: "not_applicable" }`.
5. Mandate non-empty but no integration test file in `files_to_touch`: HALT.

### E2E Test Execution

Same pattern as integration: run if `commands.test_e2e` is configured, record degraded mode if not, HALT if the mandate is non-empty but no e2e file exists.

## Step 5 — Documentation

Update every file listed in `doc_updates_required`:

- Every new public function, endpoint, or component documents purpose, parameters, return value, side effects.
- No placeholder text. No TODO comments in docs.
- If the doc file contains a table or list, add the entry in the appropriate location.

## Step 6 — Pre-Handoff Self-Check

Execute the full verification checklist from `wf-skill-verification/SKILL.md`. Every item must pass with evidence in the format that skill specifies. Do not abbreviate.

### Preflight Gate

Run `commands.preflight`. All checks must pass. Do not write the review_ready file until preflight is green.

## Step 7 — Commit and Handoff

Stage and commit all modified files in `files_to_touch`:

```bash
git add <files listed in files_to_touch>
git commit -m "<step_id> <title>

<2-3 line summary of what changed and why>"
```

A review_ready without a preceding commit is incomplete — the merge protocol requires committed changes on the task branch.

**Do NOT push.** The orchestrator pushes per-stage after merge.

Write to `paths.review_ready` using the schema in `assets/review_ready.yaml.tmpl`. Include actual coverage percentages, tdd_evidence with real failure output from the Red phase, integration / e2e status, and applied doc updates.

After writing review_ready, delete `paths.build_progress` if it exists.

---

## Fix Mode (when `paths.feedback` exists)

1. Read `paths.feedback` — focus only on the listed `failures`.
2. Read `paths.current_task` for contract context.
3. For each failure:
   - Understand the failure type and required action.
   - Make the minimal change needed to address it.
   - Do NOT restart from scratch.
   - Do NOT address issues not listed in the feedback.
4. **Design issue check:** if the fix reveals an architectural problem (same criteria as Step 3b), write a design issue and HALT instead of continuing to fail.
5. Re-run the full verification checklist (Step 6) and preflight.
6. Stage and commit the fix:

   ```bash
   git add <files listed in files_to_touch>
   git commit -m "<step_id> fix: <failure type summary>

   <what was fixed and why>"
   ```

7. Overwrite `paths.review_ready` with updated results.

**Constraints:**

- Treat each feedback failure as a targeted fix, not a rewrite.
- If a fix requires touching a file not in `files_to_touch`, HALT and write `paths.build_blocked` (Scope-Expansion HALT).
- If you cannot resolve a failure after 3 attempts, HALT with the three approaches tried.

---

## Fix-Resume Mode

When the orchestrator re-dispatches with the context hint `gates_already_green: true` (abnormal termination after gates but before commit):

1. Read `paths.build_progress` to confirm `last_step` is `all_gates_passed`.
2. **Do NOT re-run any gates.** Skip Steps 3–6.
3. Proceed directly to Step 7: stage, commit, write review_ready.
4. Delete `paths.build_progress` after writing review_ready.

If `paths.build_progress` does not exist or `last_step` is not `all_gates_passed`, treat as a normal build dispatch — run all gates from the beginning.

---

## Halt Conditions

Stop and report if:

- A file outside `files_to_touch` must be modified (Scope-Expansion HALT — see below).
- A test fails 3 times with no identified root cause.
- The task is contradictory or cannot be implemented as specified.
- Completing the task requires understanding code not covered by `context_to_load`.
- A `depends_on` dependency has not been merged.
- `commands.preflight` is not configured and cannot be determined.
- A security vulnerability is found in existing code (report it, do not fix in this task).
- A design-level problem is detected (write to `paths.design_issues` and HALT — do not retry).

### Scope-Expansion HALT

When a file outside `files_to_touch` must be modified, you MUST write to `paths.build_blocked` **before** halting. This lets the orchestrator auto-amend the contract and re-dispatch.

Use the schema in `assets/build-blocked.yaml.tmpl`. Then halt and report. Do NOT modify the out-of-scope file.

### Per-Gate Progress Marker

After each gate completes (lint, type-check, unit tests, coverage, integration tests, e2e tests, preflight), append an entry to `paths.build_progress` using the schema in `assets/build-progress.yaml.tmpl`. The orchestrator reads this file on abnormal agent return to choose recovery action.

**Gate names** (use these exact strings):

| Phase | Gate name |
|:------|:----------|
| Lint | `lint` |
| Type-check | `type_check` |
| Unit tests | `unit_tests` |
| Coverage | `coverage` |
| Integration tests | `integration_tests` |
| E2E tests | `e2e_tests` |
| Preflight | `preflight` |

**`last_step` values** (orchestrator matches on these):

| Moment | Value |
|:-------|:------|
| After all configured gates pass (before commit) | `all_gates_passed` |
| After commit | `committed` |
| After review_ready written | `review_ready_written` |

**On successful completion:** delete `paths.build_progress` after writing review_ready. Presence of the file on disk is always a sign that the build did not complete normally.
