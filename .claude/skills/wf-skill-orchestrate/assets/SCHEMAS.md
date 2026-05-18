# Pipeline State Schema

## pipeline_state.yaml

```yaml
# Default path: paths.pipeline_state (.workflow/.transient/pipeline_state.yaml)
current_phase: "idle"
# Valid: idle | creating_sprint_branch | computing_stages | planning_worktrees |
#        executing_stage | stage_complete |
#        e2e_validation | retrospective | escalated

sprint_id: ""                    # Set from sprint.yaml
sprint_branch: ""                # Set during creating_sprint_branch (e.g., "sprint/S1")

stages:
  total: 0                       # Total number of stages
  current: 0                     # Current stage number (1-indexed)
  definitions:
    # Populated during computing_stages. Each stage is a group of independent tasks.
    # 1: { tasks: ["S1.1", "S1.2"], status: pending }
    # 2: { tasks: ["S1.3", "S1.4", "S1.5"], status: pending }
    # 3: { tasks: ["S1.6"], status: pending }

task_states:
  # Per-task state tracking, populated during stage execution.
  # "S1.1": { status: pending, branch: "", worktree_path: "", attempt_counter: 0, scope_amendment_count: 0 }
  # Status: pending | building | reviewing | completed | escalated | blocked | design_issue
  # scope_amendment_count: how many times files_to_touch was amended for this task (see Build Return Protocol in SKILL.md)

blocked_tasks:
  # Tasks in later stages blocked by escalated dependencies.
  # "S1.6": { reason: "depends_on S1.5 which is escalated", blocked_by: "S1.5" }

design_issues:
  # Tasks halted due to design-level problems.
  # "S1.3": { issue_id: "DI-001", summary: "Auth/DB boundary violation", reported_at_stage: 1 }

stage_summaries:
  # Compact summaries written at stage boundaries (context hygiene).
  # 1: { completed: ["S1.1", "S1.2"], escalated: [], design_issues: [], merged_branches: ["s1.1-add-parser"] }

max_attempts: 3                  # Read from review.max_attempts in config (default: 3). Escalate when attempt_counter >= max_attempts.

last_transition:
  from: ""
  to: ""
  timestamp: ""
  reason: ""

history:
  # Append-only log of state-transition events.
  # Minimum fields on every entry: ts, event, from_phase, to_phase.
  # Additional fields (note, reason, dispatched_agents, etc.) are allowed.
  # Never edit or delete prior entries — history is write-once.
  #
  # Standard transition entry:
  - ts: "YYYY-MM-DDTHH:MM:SSZ"
    event: "transition"
    from_phase: "idle"
    to_phase: "computing_stages"
    reason: "Pipeline started by user"
  #
  # Out-of-band revert detected (disk phase earlier than in-context phase):
  # - ts: "YYYY-MM-DDTHH:MM:SSZ"
  #   event: "out_of_band_revert_detected"
  #   from_disk_phase: "phase_a"       # phase read from disk (reverted)
  #   restored_to_phase: "phase_b"     # phase restored from in-context state
  #   note: "Detected out-of-band revert; restored in-context state."
  #
  # Cold resume (disk phase later than in-context phase — stale context adopted):
  # - ts: "YYYY-MM-DDTHH:MM:SSZ"
  #   event: "cold_resume_adopted"
  #   stale_context_phase: "phase_a"   # phase the agent had in context
  #   adopted_phase: "phase_b"         # phase adopted from on-disk state
```

---

## Build Artifacts

These artifacts are written by the build agent during execution. The orchestrator reads them immediately after each build sub-agent returns (see Build Return Protocol in SKILL.md).

Templates: `wf/templates/build-blocked.yaml.tmpl` and `wf/templates/build-progress.yaml.tmpl`.

### `build_blocked.yaml` — Scope-Expansion HALT

Written by the build agent when it discovers that compilation or tests require modifying a file outside `files_to_touch`. Written **before** halting. Deleted by the orchestrator after handling (whether it applies a scope amendment or escalates to the human).

```yaml
# Default path: paths.build_blocked (.workflow/.transient/build-blocked.yaml)
task_id: "S1.3"
attempt: 1
reason: scope_expansion_required
required_files:
  - path: "src/shared/types.ts"
    why: "The new handler's return type references SharedResult which is defined here and cannot be inlined without violating DRY"
  # Add one entry per additional out-of-scope file required
attempted_change: "Implementing the CreateFoo handler required importing SharedResult from src/shared/types.ts. This file is not in files_to_touch and belongs to a different component. The import cannot be avoided — the handler return type is defined by the API contract."
suggested_amendment: "Add src/shared/types.ts to files_to_touch. No new logic is needed there; only the SharedResult type export needs to be verified/updated."
ts: "2026-05-09T14:23:00Z"
```

**Fields:**

| Field | Type | Description |
|:------|:-----|:------------|
| `task_id` | string | Task ID from `current_task.yaml` |
| `attempt` | int | Current attempt number |
| `reason` | string | Always `scope_expansion_required` |
| `required_files` | list | Files that must be modified, each with `path` and `why` |
| `attempted_change` | string | One paragraph: what the agent was doing when it hit the boundary |
| `suggested_amendment` | string | Optional: agent's proposal for amending `files_to_touch` |
| `ts` | ISO-8601 | Timestamp when the artifact was written |

**Orchestrator action:** Read `review.max_scope_amendments` from config (default: 1). If `task_states[id].scope_amendment_count < max_scope_amendments` and `suggested_amendment` is reasonable, apply the amendment and re-dispatch. Otherwise, escalate to the human. Always delete the artifact after handling.

---

### `build_progress.yaml` — Per-Gate Progress Marker

Written by the build agent after each gate completes. Allows the orchestrator to determine how far the agent progressed if it terminates abnormally. Deleted by the build agent on successful completion (after writing `review_ready.yaml`). If abnormal termination occurs, the file remains on disk.

```yaml
# Default path: paths.build_progress (.workflow/.transient/build-progress.yaml)
task_id: "S1.3"
attempt: 1
gates:
  - gate: "lint"
    status: passed
    ts: "2026-05-09T14:25:01Z"
  - gate: "type_check"
    status: passed
    ts: "2026-05-09T14:25:18Z"
  - gate: "unit_tests"
    status: passed
    ts: "2026-05-09T14:26:42Z"
  - gate: "coverage"
    status: passed
    ts: "2026-05-09T14:26:50Z"
  - gate: "preflight"
    status: passed
    ts: "2026-05-09T14:28:05Z"
last_step: "all_gates_passed"
```

**`last_step` values and orchestrator recovery actions:**

| `last_step` value | Meaning | Orchestrator action |
|:------------------|:--------|:--------------------|
| `review_ready_written` | Agent finished; return signal lost | Treat as completed; proceed to review |
| `committed` | Committed but didn't write `review_ready.yaml` | Treat as completed; proceed to review |
| `all_gates_passed` | Gates green; died before commit | Re-dispatch in fix-resume mode (`gates_already_green: true` context hint) |
| anything earlier | Gates not fully green | Restart from scratch; increment attempt counter |
| (absent) | File missing | Restart from scratch; increment attempt counter |

**Gate name reference** (matches build skill):

| Gate name | Corresponds to |
|:----------|:---------------|
| `lint` | Lint check after refactor |
| `type_check` | Type-check / compile check |
| `unit_tests` | Unit test suite |
| `coverage` | Coverage metric gate |
| `integration_tests` | Integration test suite |
| `e2e_tests` | E2E test suite |
| `preflight` | Full preflight command |

---

## Stage Definitions Example

After `computing_stages` completes:

```yaml
stages:
  total: 3
  current: 1
  definitions:
    1: { tasks: ["S1.1", "S1.2"], status: pending }
    2: { tasks: ["S1.3", "S1.4", "S1.5"], status: pending }
    3: { tasks: ["S1.6"], status: pending }

task_states:
  "S1.1": { status: pending, branch: "", worktree_path: "", attempt_counter: 0 }
  "S1.2": { status: pending, branch: "", worktree_path: "", attempt_counter: 0 }
```
