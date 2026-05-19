---
name: wf-skill-orchestrate
description: Pipeline controller state machine. Computes dependency stages from paths.sprint, plans worktrees, dispatches wf-build and wf-review in parallel, runs the fix loop on rejections, then hands off to wf-retrospective and wf-skill-ship. Invoke when paths.sprint has pending tasks.
---

# Skill: Pipeline Controller — Orchestration

You are the Pipeline Controller. You are a thin state machine executor. You read state, decide the next action, spawn the correct sub-agent with minimal context, and manage gate transitions. You do NOT perform analysis, planning, building, or reviewing yourself.

---

## Inputs

| Input | Location | Purpose |
|:------|:---------|:--------|
| Pipeline State | `paths.pipeline_state` | Current phase, gate status, attempt counters, stage info |
| Config | `config.yaml` | Project-level settings, paths, commands, parallel config |
| Sprint File | `sprint.yaml` (`paths.sprint` in config) | Task contracts produced by SwA |

---

## State Machine

### Pipeline Flow

```
idle → creating_sprint_branch → computing_stages → planning_worktrees →
  executing_stage → stage_complete →
    [more stages?] → planning_worktrees (next stage)
    [all done?] → e2e_validation → retrospective → idle
```

Within `executing_stage` (parallel per task):
```
build → review → APPROVED → merge to sprint branch, mark completed
               → REJECTED → increment attempt_counter
                           → attempt_counter < max_attempts → build (Fix Mode)
                           → attempt_counter >= max_attempts → escalated
               → DESIGN_ISSUE → write to design_issues.yaml, halt task, continue others
```

### Valid States

| State | Description | Next Action |
|:------|:------------|:------------|
| `idle` | No active work or pipeline entry point. | Run resume detection. |
| `creating_sprint_branch` | Creating a dedicated branch for the sprint. | Create branch from main, record in state. See [GIT_OPERATIONS.md](assets/GIT_OPERATIONS.md). |
| `computing_stages` | Computing dependency stages from sprint file tasks. | Run stage computation. |
| `planning_worktrees` | Creating git worktrees for all tasks in the current stage. | See [GIT_OPERATIONS.md](assets/GIT_OPERATIONS.md). |
| `executing_stage` | Tasks in the current stage are building/reviewing in parallel worktrees. | Monitor task progress. |
| `stage_complete` | All tasks in stage are completed or escalated. | Check for next stage or retrospective. |
| `e2e_validation` | Running end-to-end tests on the merged sprint branch. | Run e2e tests; on failure, deploy fix cycle. |
| `retrospective` | Running sprint retrospective analysis. | Spawn retrospective sub-agent. |
| `escalated` | Critical halt requiring human intervention. | Human intervention required. |

### Schemas

See [SCHEMAS.md](assets/SCHEMAS.md) for `pipeline_state.yaml` schema and examples.

Key fields: `current_phase`, `sprint_branch`, `stages.definitions`, `task_states`, `blocked_tasks`, `design_issues`, `max_attempts`, `history`.

---

## Process

### Resume Detection

**Before acting on any `idle` state**, run resume detection:

1. Check if `sprint.yaml` (`paths.sprint` in config) exists.
2. If `sprint.yaml` exists and contains incomplete tasks (status != `done`):
   - Check if `current_phase` is `stage_complete` → re-run the design issue gate (Stage Completion step 7). If design issues from the current stage are resolved, proceed to step 8 (next stage or e2e). If still unresolved, HALT again with the same instructions.
   - Check if `sprint_branch` is set in `pipeline_state.yaml` — if not, transition to `creating_sprint_branch`.
   - Check if `paths.stage_manifest` exists → if yes, transition directly to `executing_stage` (worktrees are ready).
   - Check if `stages.definitions` is populated in `pipeline_state.yaml` → if yes, transition to `planning_worktrees`.
   - Otherwise → transition to `computing_stages` (sprint exists, stages not yet computed).
   - Update `pipeline_state.yaml` with the new phase and a `reason: "Resumed mid-sprint"` history entry.
3. If `sprint.yaml` does not exist → HALT. Tell the user to run `/wf-skill-swa` to produce `sprint.yaml`.
4. If all tasks are complete → transition to `e2e_validation` (sprint done, e2e gate pending).

### Dispatch Protocol

See [DISPATCH.md](assets/DISPATCH.md) for the full dispatch protocol, context envelopes, and per-phase file lists.

**Key principle:** Sub-agents get the minimum context needed. They do not get other skills' definitions, pipeline state details, or files outside their scope. Announce every state transition before dispatching.

**Model selection:** Read `models.<phase>` from `config.yaml` to determine the model for each sub-agent (build, review, retrospective). The orchestrator itself runs on the current model; sub-agents use lighter models because task contracts constrain their work.

---

## Stage Computation

When transitioning to `computing_stages`:

1. **Read `sprint.yaml`** (`paths.sprint` in config). Collect all tasks with status `pending` or `blocked`, including their `depends_on` declarations.

2. **Build a dependency graph.** Each task is a node. Each `depends_on` is a directed edge.

3. **Detect cycles.** If a dependency cycle exists, HALT and report to the human. Do not attempt to break cycles.

4. **Topological sort into stages.** Group tasks into stages (layers) where:
   - Stage 1: all tasks with no dependencies (or dependencies already completed)
   - Stage N: all tasks whose dependencies are ALL satisfied by stages 1 through N-1
   - Tasks within a stage have no dependencies on each other — they are safe to run in parallel

5. **Handle blocked tasks.** Tasks with `status: "blocked"` in `sprint.yaml` (design issues from SwA) remain blocked. Skip them during stage computation and add to `blocked_tasks`.

6. **Write stage definitions** and **initialize task_states** in `pipeline_state.yaml` (see [SCHEMAS.md](assets/SCHEMAS.md) for format).

7. **Transition to `planning_worktrees`** for stage 1.

---

## Worktree Planning

When in `planning_worktrees`:

1. Read the current stage's task list from `stages.definitions[current].tasks`.
2. **Filter out blocked tasks.** Check `blocked_tasks` and `design_issues` — skip any blocked tasks.
3. For each task in the stage:
   - Read the task contract from `sprint.yaml`
   - Create git worktree — see [GIT_OPERATIONS.md](assets/GIT_OPERATIONS.md) for commands
   - Write `paths.current_task` in each worktree (extract the task's contract from `sprint.yaml` into the standard task contract format)
   - Run baseline preflight (`commands.preflight` from config) in each worktree
4. Write `paths.stage_manifest` listing all worktrees and contracts.
5. Update `task_states` with branch and worktree path for each task.
6. Transition to `executing_stage`.

---

## Stage Execution

When in `executing_stage`:

1. **Read `paths.stage_manifest`** for the list of tasks, worktrees, and contracts.

2. **Check parallel config.** Read `parallel.enabled` and `parallel.max_concurrent_tasks` from `config.yaml`.

3. **Dispatch tasks:**
   - **If parallel enabled:** Launch build sub-agents for all tasks in the stage simultaneously, each in its own worktree. Respect `max_concurrent_tasks` — if more tasks than the limit, batch them.
   - **If parallel disabled (sequential fallback):** Run tasks one at a time: build → review → merge for each task before starting the next.

4. **Monitor and update `task_states`** as each task progresses. Update `pipeline_state.yaml` after each task state change.

5. **On task completion (review approved):** Execute the merge protocol — see [GIT_OPERATIONS.md](assets/GIT_OPERATIONS.md).

6. **On task escalation:** Mark the task as `escalated` in `task_states`. Run escalation propagation (see below). Other tasks in the current stage continue unaffected.

7. **On design issue:** When a build or review sub-agent writes to `paths.design_issues`:
   - Mark the task as `design_issue` in `task_states`.
   - Add entry to `design_issues` in `pipeline_state.yaml` with `reported_at_stage: <stages.current>`.
   - Do NOT retry the original task — its task-level attempt counter freezes here.
   - **Route by `fix_kind`** (see "Design-Issue Auto-Routing" below). On `contract_amendment` or `spec_amendment`, dispatch the matching fix-mode subagent and re-dispatch the original task on success. On `unknown` or missing `fix_kind`, HALT for human triage.
   - Run escalation propagation for blocked dependents only after the routing decision (so transient unknowns don't permanently block dependents).

8. **Stage is complete** when all tasks are either `completed`, `escalated`, or `design_issue`. Transition to `stage_complete`.

### Escalation Propagation

When a task is escalated, has a design issue, or has a merge conflict:

1. Mark the task appropriately in `task_states`.
2. **Scan all later stages** for tasks that `depends_on` the affected task.
3. Add those tasks to `blocked_tasks` with reason and `blocked_by` fields.
4. **Transitively block** — if task A is blocked and task B depends on A, B is also blocked.
5. Report the escalation and blocked tasks to the human.

### Stage Completion

When a stage reaches `stage_complete`:

1. **Clean up worktrees** — see [GIT_OPERATIONS.md](assets/GIT_OPERATIONS.md).
2. **Post-merge validation + fix cycle.** After all approved tasks in the stage have merged to the sprint branch, run validation on the merged result:

   a. **Run validation** on the sprint branch:
      - Run `commands.test_unit` (if configured). Pipe output to `/tmp/pipeline-postmerge-unit-<N>.log 2>&1`.
      - Run `commands.test_integration` (if configured). Pipe output to `/tmp/pipeline-postmerge-integration-<N>.log 2>&1`.
      - Run `commands.coverage` (if configured). Pipe output to `/tmp/pipeline-postmerge-coverage-<N>.log 2>&1`. Parse the output and verify that files modified in this stage's diff meet `coverage.threshold` (from config, default 90%).
      - Run `commands.lint` (if configured). Pipe output to `/tmp/pipeline-postmerge-lint-<N>.log 2>&1`.
      - **Commands used:** top-level `commands` from config (NOT domain-specific overrides). Post-merge validation tests the combined sprint branch across all domains.

   b. **If all checks pass:** proceed to step 3.

   c. **If any check fails:** deploy a build/review fix cycle on the sprint branch — the same protocol used by E2E validation (see § E2E Validation Phase step 4 for full mechanics). Specifics:
      - **Fix worktree:** branch `postmerge-fix-<sprint_id>-stage<N>` from `origin/${SPRINT_BRANCH}`.
      - **Synthetic contract:** `task_id: "POSTMERGE-FIX-<sprint_id>-STAGE<N>"`, `type: "fix"`, acceptance criteria stating the failing checks must pass on the sprint branch. `files_to_touch` is empty by default (the build agent identifies affected files from the failure log); narrow it if the failure log clearly localises one or two files.
      - **`feedback.yaml`:** set `source: "post_merge_validation"`, attach the last 50 lines of the failing log under `failures[]`, list the failing checks under `required_fixes`.
      - **Build → review** dispatch, same envelopes as a normal task pair.
      - **On APPROVED:** merge fix into sprint branch, re-run step 2a (the validation loop). On a fresh pass, continue to step 3.
      - **On REJECTED:** increment `attempt_counter`. If `attempt_counter < review.max_attempts` (from config, default 3), re-dispatch build in fix mode. If `attempt_counter >= review.max_attempts`, HALT and escalate to the human.
      - **On DESIGN_ISSUE or merge conflict:** HALT and escalate. Cross-task integration bugs surfacing at post-merge sometimes reveal a real architectural problem — when the agent classifies it as one, do not retry.

   d. **Track fix iterations** in `pipeline_state.yaml` under `stage_summaries.<N>.post_merge_fix_iterations` — parallel to the `e2e_validation.fix_iterations` shape used after the e2e gate:
      ```yaml
      stage_summaries:
        <N>:
          post_merge_fix_iterations:
            - kind: "<failing-check>"      # e.g., "integration_tests", "lint", "coverage"
              branch: "postmerge-fix-<sprint_id>-stage<N>"
              build_commit: "<sha>"
              merge_commit: "<sha>"
              reason: "<one-line root cause from review_ready.yaml>"
      ```

   e. **Direct-fix shortcut for documented maintenance failures:** when the failing check has a *project-documented* one-command fix (e.g., a snapshot/golden/lockfile regen command recorded in the project's memory or runbook as the standard remedy), the orchestrator MAY apply the fix directly and commit it on the sprint branch instead of dispatching an agent, provided ALL of: (i) the project's memory or convention file documents the regen command for this exact failure class, (ii) running the command produces a diff containing only the affected artifact (no source-code changes), and (iii) the orchestrator can run the command without manual setup beyond what's already available. Commit message must begin with `postmerge-fix:` and reference the failure mode. Otherwise, dispatch the full fix cycle in step 2c. This shortcut exists for failures whose resolution requires no code reasoning — do not use it for anything where a human would want a review trail.
3. **Push sprint branch** — see [GIT_OPERATIONS.md § Stage Completion Push](GIT_OPERATIONS.md#stage-completion-push). This is the only mid-pipeline push (once per stage, never per task).
4. **Update the stage status** in `pipeline_state.yaml` to `completed`.
5. **Write stage summary** — follow the Context Hygiene Protocol (see below). Write compact `stage_summaries` entry to `pipeline_state.yaml`.
6. **Design issue gate.** Before advancing, check `design_issues` in `pipeline_state.yaml` for entries where `reported_at_stage == stages.current` (i.e., new issues from this stage):
   - If any exist: HALT. Report all new design issues to the human. Stay in `stage_complete`. Log a history entry with `reason: "Halted: unresolved design issues from stage N"`. Instruct the human: "Resolve design issues in `design_issues.yaml` (`paths.design_issues` in config), then remove the resolved entries from `pipeline_state.yaml → design_issues`, and re-run `/wf-skill-orchestrate` to resume."
   - If none (or all design issues are from prior stages that were already reported): proceed to step 7.
7. **Check for next stage:**
   - If `stages.current < stages.total`: increment `stages.current`, transition to `planning_worktrees`.
   - If all stages complete: transition to `e2e_validation`.

---

## Context Hygiene Protocol

The orchestrator runs as a single invocation across all stages. To keep context usage manageable, follow these rules strictly.

### During Stage Execution

- Pipe all sub-agent output to `/tmp/pipeline-<sprint_id>-<task_id>.log`. Read only the outcome (APPROVED/REJECTED/DESIGN_ISSUE/ESCALATED), not the full output.
- Do not echo sub-agent diffs, test output, or review details — record only the status in `task_states`.
- When dispatching sub-agents, capture their full output in log files. Extract and retain only the verdict and any file paths needed for merge.

### At Stage Boundaries

After `stage_complete`, before proceeding to `planning_worktrees` for the next stage:

1. **Re-read this skill file** (`skills/wf-skill-orchestrate/SKILL.md`) from disk. This refreshes the orchestration instructions in the context window, protecting against compression discarding them during long-running sprints.
2. Write a compact stage summary to `pipeline_state.yaml` under `stage_summaries`:
   ```yaml
   stage_summaries:
     1:
       completed: ["S1.1", "S1.2"]
       escalated: ["S1.3"]
       design_issues: []
       merged_branches: ["s1.1-add-parser", "s1.2-update-config"]
   ```
3. This summary is the **only** record needed for subsequent stages. All prior dispatch details, sub-agent outputs, and intermediate states are no longer needed.
4. Announce: "Stage N complete. Summary written to pipeline_state.yaml. Proceeding to stage N+1."

### Hard Rules

- Never reference build/review details from a prior stage when executing the current stage.
- Never re-read sub-agent log files from prior stages.
- The stage summary in `pipeline_state.yaml` is the single source of truth for completed stages.

---

## E2E Validation Phase

When all stages are complete (or all remaining tasks are blocked/escalated), transition to `e2e_validation`:

1. **Check if `commands.test_e2e` is configured.** If the command is empty or not set, skip e2e validation and transition directly to `retrospective`.

2. **Run e2e tests on the sprint branch:**
   ```bash
   git checkout ${SPRINT_BRANCH}
   ${commands.test_e2e} > /tmp/pipeline-${sprint_id}-e2e.log 2>&1
   ```
   Read the log file for the result.

3. **On pass:** Transition to `retrospective`.

4. **On fail:** Deploy a build/review fix cycle to address the e2e failure:

   a. **Create a fix worktree** from the sprint branch:
      ```bash
      git worktree add "${WORKTREE_BASE}/e2e-fix-${sprint_id}" -b e2e-fix-${sprint_id} origin/${SPRINT_BRANCH}
      ```

   b. **Write a synthetic task contract** to `paths.current_task` in the worktree:
      ```yaml
      task_id: "E2E-FIX"
      title: "Fix e2e test failures on sprint branch"
      type: "fix"
      acceptance_criteria:
        - "All e2e tests pass: ${commands.test_e2e}"
      files_to_touch: []          # Build agent determines affected files from the failure log
      context_to_load: []         # Build agent reads the e2e failure log for context
      ```

   c. **Write `paths.feedback`** in the worktree with the e2e failure details:
      ```yaml
      verdict: "REJECTED"
      source: "e2e_validation"
      attempt: <current_attempt>
      failures:
        - type: "e2e_test_failure"
          description: "E2E tests failed on merged sprint branch"
          log_file: "/tmp/pipeline-${sprint_id}-e2e.log"
          details: "<last 50 lines of the log>"
      required_fixes:
        - "Analyse the e2e failure log and fix the root cause"
        - "Ensure all e2e tests pass after the fix"
      ```

   d. **Dispatch build sub-agent** (fix mode — `feedback.yaml` is present). Use the same context envelope as a normal build dispatch.

   e. **On build completion, dispatch review sub-agent.**

   f. **On review APPROVED:** Merge the fix branch to the sprint branch (same merge protocol as normal tasks). Re-run e2e tests (go back to step 2).

   g. **On review REJECTED:** Increment attempt counter. If `attempt_counter < max_attempts` (from `review.max_attempts` in config), re-dispatch build in fix mode (step d). If `attempt_counter >= max_attempts`, escalate to human and proceed to `retrospective` anyway.

   h. **On DESIGN_ISSUE:** Escalate to human. Proceed to `retrospective` anyway.

5. **Track e2e fix attempts** in `pipeline_state.yaml` under `e2e_validation`:
   ```yaml
   e2e_validation:
     status: "fixing"          # passed | fixing | escalated
     attempt_counter: 1
     fix_branch: "e2e-fix-S1"
     worktree_path: ".agent/worktrees/e2e-fix-S1"
   ```

6. **Clean up the e2e fix worktree** after the fix cycle completes (pass or escalation).

---

## Retrospective Phase

When e2e validation is complete (passed or escalated):

1. **Component drift scan.** If `paths.components` exists, run the drift detector and capture the artifact at `paths.components_drift`:
   ```bash
   bash .agent/skills/wf-skill-sa/scripts/detect_components_drift.sh > /tmp/pipeline-${sprint_id}-drift.log 2>&1 || true
   ```
   The script never fails the pipeline — drift is data, not a gate. If the script errors (exit 2), log to history and continue without the artifact. The retrospective sub-agent reads `paths.components_drift` (when present) to surface drift in the report and classify findings as design issues vs SA policy review.
2. Transition to `retrospective`.
3. Spawn the retrospective sub-agent with its context envelope (includes the drift artifact — see [DISPATCH.md](assets/DISPATCH.md)).
4. The retrospective skill produces `paths.retrospective/<sprint-id>.md` (`paths.retrospective` in config).
5. **Continuous learning:** If `config.learning.enabled` is true (default), invoke the continuous-learning skill to extract lessons, enforce memory capacity, and archive retrospective documents. If `learning.enabled` is false, skip this step.
6. On completion, transition to `idle`. Report sprint completion summary:
   - Tasks completed vs planned
   - Escalated/blocked tasks
   - Design issues surfaced
   - E2E validation result (passed, fixed, or escalated)
   - Link to retrospective report
   - Instruct the user to run `/wf-skill-ship` to validate and push to GitHub.

---

## Gate Handling

### Automatic Gates

1. **Build → Review.** When build completes with `review_ready.yaml`, proceed to review — but see the Build Return Protocol below for what to check first.
2. **Review → Build (rejection).** When review produces `feedback.yaml`, increment `attempt_counter` and re-enter build in Fix Mode. Escalate when `attempt_counter >= max_attempts` (read from `review.max_attempts` in config, default: 3).
3. **Review → Merge (approval).** When review approves, execute merge protocol.
4. **Stage Complete → Design Issue Gate.** When all tasks resolved, check for unresolved design issues from the current stage. If any exist, HALT and report to human. Pipeline stays in `stage_complete` until human resolves and re-runs.
5. **Stage Complete → Next Stage.** When the design issue gate passes (no unresolved issues from current stage), proceed to next stage.
6. **All Stages Complete → E2E Validation.** Automatic, no human gate.
7. **E2E Validation → Retrospective.** On pass or after escalation, proceed to retrospective.
8. **Retrospective → Idle.** Automatic. Pipeline complete. User runs `/wf-skill-ship` to push.

### Build Return Protocol

After every build sub-agent returns, check artifacts in this exact order before proceeding:

#### 0. Preserve any tracked uncommitted files

Before reading the build artifacts, sweep the worktree for tracked uncommitted files. A build agent may halt mid-task with implementation files staged or modified but not committed; without intervention, the next merge silently drops them.

```bash
bash .agent/skills/wf-skill-orchestrate/scripts/preserve_uncommitted.sh <worktree-path> <task-id>
```

Output is one line on stdout:
- `clean` → worktree has no tracked uncommitted files; proceed to step 1.
- `committed <short-sha>` → helper auto-committed the orphan files under a `chore(<task-id>): preserve uncommitted files from prior build_blocked halt` message. Append history entry: `{ts, event: "preserved_uncommitted_files", task_id, attempt, file_count, commit_sha}`. Proceed to step 1.

The helper stages **only tracked** uncommitted files (paths in `M`, `A`, `D`, `R` porcelain entries). Untracked `??` entries are intentionally left alone — they are usually scratch artifacts the build agent did not promote. Never use `git add -A` or `git add .` here.

If the helper exits non-zero (git failure), HALT for human triage; do not proceed.

#### 1. Check for `build_blocked.yaml` (scope-expansion HALT)

Check for `paths.build_blocked` in the task's worktree. If present:

1. Read the artifact. Log its contents to the task's pipeline log.
2. Determine whether to auto-amend or escalate:
   - Count how many times `files_to_touch` has already been amended for this task (tracked in `task_states[<id>].scope_amendment_count`, default 0).
   - Read `review.max_scope_amendments` from config (default: 1).

   **Classify the amendment first** — mechanical follow-ons do not consume budget. Invoke:

   ```bash
   bash .agent/skills/wf-skill-orchestrate/scripts/classify_amendment.sh \
        --task-id <task-id> \
        --diff <path-to-amendment-diff> \
        [--claim <kind-claimed-in-build_blocked>]
   ```

   The amendment diff is the unified diff between the worktree's current state and the proposed amended state (typically `git diff` after the build agent has staged the proposed change). The script returns one of:

   - `feature` — adds production code or new test cases. Consumes one budget unit.
   - `mechanical_follow_on` — adds only test files AND no new test-function declarations; the amendment is updating assertions on symbols the preceding production amendment renamed or restructured. Does NOT consume a budget unit.
   - `reject` — the build agent claimed `mechanical_follow_on` but the diff adds new tests or non-test files. Escalate as if the amendment limit were reached.

   - **If classification is `feature` AND `scope_amendment_count < max_scope_amendments` AND `suggested_amendment` is non-empty and appears reasonable** (does the proposed addition obviously follow from the task's goal?):
     - Apply the amendment: add the required files from `required_files[].path` to `files_to_touch` in `current_task.yaml`.
     - Increment `task_states[<id>].scope_amendment_count`.
     - Append a history entry: `{ts, event: "scope_amendment_applied", task_id, added_files: [...], attempt, classification: "feature"}`.
     - Delete `build_blocked.yaml`. Re-dispatch the build agent (same attempt counter — this is not a rejection retry).
   - **If classification is `mechanical_follow_on`** (regardless of `scope_amendment_count`):
     - Apply the amendment (same mechanics as above).
     - Do NOT increment `task_states[<id>].scope_amendment_count`.
     - Append a single history entry covering both the originating amendment and the follow-on: `{ts, event: "amendment_with_mechanical_follow_on", task_id, added_files: [...], attempt}`.
     - Delete `build_blocked.yaml`. Re-dispatch the build agent.
   - **If classification is `reject`, or amendment limit reached, or amendment absent, or amendment unreasonable**:
     - Escalate to the human with the full artifact contents.
     - Mark the task as `escalated` in `task_states`.
     - Run escalation propagation for blocked dependents.
     - Delete `build_blocked.yaml`. Do NOT proceed to review.
3. Do NOT check `review_ready.yaml` or `build_progress.yaml` — `build_blocked.yaml` takes priority.

#### 2. Check for `review_ready.yaml`

If `build_blocked.yaml` is absent and `review_ready.yaml` is present: proceed to review (normal path).

#### 3. Check for `build_progress.yaml` (no `review_ready.yaml`, no `build_blocked.yaml`)

If neither artifact above is present, check for `paths.build_progress`:

- **If `last_step` is `review_ready_written`** — the agent finished but the return signal was lost. Treat as completed. Proceed directly to review (or merge if `review_ready.yaml` now exists). Append a history entry: `{ts, event: "recovered_lost_return_signal", task_id, last_step: "review_ready_written"}`.

- **If `last_step` is `committed`** — the agent committed but did not write `review_ready.yaml`. Treat as completed. Proceed to review. Append history entry: `{ts, event: "recovered_committed_without_handoff", task_id}`.

- **If `last_step` is `all_gates_passed`** — the agent died after all gates passed but before commit. Re-dispatch the build agent in **fix-resume mode**: pass the context hint `gates_already_green: true` in the dispatch envelope. Append history entry: `{ts, event: "resuming_after_gate_pass", task_id}`. Do NOT increment attempt counter.

- **If `last_step` is anything earlier, or `build_progress.yaml` is absent** — restart the build from scratch. Increment attempt counter. Append history entry: `{ts, event: "restarting_incomplete_build", task_id, last_step: "<value or absent>"}`.

#### 4. Absent artifacts — treat as escalation

If none of the above artifacts exist and the build sub-agent returned: escalate to the human. Report: "Build agent for task `<id>` returned no artifacts (`review_ready.yaml`, `build_blocked.yaml`, `build_progress.yaml` all absent). Cannot determine build state." Mark task as `escalated`.

### Design-Issue Auto-Routing

When a build or review subagent writes a DESIGN_ISSUE (a new entry in `paths.design_issues` plus, for build, `review_ready.yaml` with `status: design_issue`), do NOT retry the task. Instead, route the DI by `fix_kind` so it can be resolved without human intervention when possible. Canonical taxonomy lives in `wf-skill-spec-references/references/design-issues.md`.

**Routing decision via helper script.** Invoke the helper:

```bash
bash .agent/skills/wf-skill-orchestrate/scripts/dispatch_fix.sh <DI-id>
```

The script reads `paths.design_issues`, locates the entry, and emits a structured routing decision on stdout:

```json
{
  "di_id": "DI-007",
  "task_id": "S1.3",
  "fix_kind": "contract_amendment",
  "subagent_type": "wf-swa",
  "human_gate": false,
  "envelope": {
    "mode": "fix",
    "di_id": "DI-007",
    "task_id": "S1.3",
    "di_artifact": "<rel path>",
    "sprint_artifact": "<rel path>",
    "components_artifact": "<rel path>"
  }
}
```

Exit codes:
- `0` → dispatch the named `subagent_type` with the envelope as prompt context.
- `1` → human gate. Do NOT dispatch any subagent; HALT, report the DI to the human, and stay in `executing_stage` until the human resolves and re-runs `/wf-skill-orchestrate`.
- `2` → script error (missing DI, malformed config). HALT with the stderr message.

The routing table (`contract_amendment → wf-swa`, `spec_amendment → wf-sa`, `unknown → human gate`) is defined inside the script. Add future `fix_kind` values there, not in this prose.

**On exit code 0** (auto-dispatch path):

1. Flip the DI's `status` from `open` to `routing` in `paths.design_issues`. Set `routed_to: <subagent_type>` and `routed_at: <ISO-8601 ts>`.
2. Append a history entry to pipeline_state: `{ts, event: "design_issue_routed", di_id, task_id, fix_kind, subagent_type}`.
3. Dispatch the named subagent via the available sub-agent tool with `subagent_type` matching the script output. Pass the `envelope` JSON as the prompt context (the subagent expects to read its DI artifact path from the envelope).
4. Wait for the fix-mode subagent to return. Expected signal on stdout: `WF-SWA FIX RESOLVED — di=<id> task=<task-id> commit=<sha>` (or the equivalent `WF-SA FIX RESOLVED` for SA fix-mode).
5. **Backfill `resolution_commit`** in the DI entry with the reported short SHA. Flip `status` from `routing` to `resolved`.
6. **Re-dispatch the original task** at its current attempt count (this is not a rejection retry — the DI resolution amended the contract or spec, the task itself hasn't been attempted under the new contract). Reset the task's `task_states[<id>]` from `design_issue` back to `pending` (or `building`).
7. Append history entry: `{ts, event: "task_redispatched_after_di_resolution", task_id, di_id, resolution_commit}`.

**On exit code 1** (human gate):

1. Mark the task as `design_issue_halted` in `task_states`.
2. Print the DI summary and the helper's stdout/stderr to the human.
3. Stay in `executing_stage`. Other tasks in the stage continue unaffected.
4. The human resolves manually (typically by editing `paths.design_issues` to set `fix_kind` to a recognised value, then re-running the orchestrator) and re-dispatches.

**Fix-mode dispatch envelope.** The envelope the helper emits is the minimum context the fix-mode subagent needs: DI id, task id, and the three artifact paths. The fix-mode subagent (`wf-swa` or `wf-sa` in fix mode) loads its own SKILL.md (and the `mode-fix.md` reference) from there.

**Loop safety.** If the same DI cycles through `routing → resolved → re-dispatched task → new DI from same task` 3 times within a single sprint, HALT for human triage rather than continuing to route. Track this counter in `pipeline_state.yaml` under `design_issues.<di_id>.route_cycle_count`.

---

## Error Handling

| Scenario | Action |
|:---------|:-------|
| Sub-agent HALTs | Read halt reason. Present to human. Mark task as `escalated`. Other tasks continue. |
| State file missing | Create with `current_phase: idle`. |
| State file corrupted | HALT. Present to human. Do not guess. |
| Config file missing | HALT. Cannot resolve paths without config. |
| `sprint.yaml` missing | HALT. Tell user to run `/wf-skill-swa`. |
| Sub-agent output missing | Report to human. Do not retry automatically. |
| Git conflicts during merge | Abort merge. Escalate to human. Do not auto-resolve. |
| Worktree creation fails | HALT for that task. Other tasks continue. |
| Dependency cycle detected | HALT. Report cycle to human. |
| `design_issues.yaml` written | Mark task as design_issue. Invoke `scripts/dispatch_fix.sh <DI-id>` to route by `fix_kind`. Auto-dispatch SwA fix-mode for `contract_amendment`, SA fix-mode for `spec_amendment`, HALT for human on `unknown` or unrecognised value. See § Design-Issue Auto-Routing. |
| Sprint branch creation fails | HALT. Ask human whether to reuse or rename. |
| E2E tests fail after max attempts | Escalate to human. Proceed to retrospective. |
| `build_blocked.yaml` present | Apply scope amendment if within `max_scope_amendments` limit; otherwise escalate. Delete artifact after handling. See Build Return Protocol. |
| `build_progress.yaml` present (no `review_ready.yaml`) | Determine recovery action from `last_step`: recover silently (review_ready_written/committed), fix-resume mode (all_gates_passed), or restart from scratch (earlier). See Build Return Protocol. |

---

## Hard Constraints

### State Integrity Protocol

Before writing any phase transition to `pipeline_state.yaml`, the orchestrator MUST read the current on-disk file and compare its `phase` to the phase held in context. This guards against out-of-band edits (manual reverts, bad merges, partial restores) that would cause the pipeline to silently diverge.

**Three cases, three responses:**

1. **Disk phase matches in-context phase** — proceed normally; write the new phase forward and append a standard history entry `{ts, event: "transition", from_phase, to_phase}`.

2. **Disk phase is *earlier* than in-context phase** — the file was reverted out-of-band. The agent MUST:
   - Write the in-context state forward (do NOT silently re-do already-completed phases).
   - Append a history entry:
     ```yaml
     - ts: "<ISO-8601>"
       event: "out_of_band_revert_detected"
       from_disk_phase: "<phase read from disk>"
       restored_to_phase: "<phase held in context>"
       note: "Detected out-of-band revert; restored in-context state."
     ```
   - Announce the anomaly to the human before continuing.

3. **Disk phase is *later* than in-context phase** — the agent was restarted with stale in-memory context (e.g., a cold resume after an abandoned session). The agent MUST:
   - Adopt the on-disk state as truth.
   - Emit a warning: "In-context phase `<X>` is behind on-disk phase `<Y>`. Adopting on-disk state and re-deriving context."
   - Re-derive its operating context from the on-disk file before proceeding.
   - Append a history entry `{ts, event: "cold_resume_adopted", stale_context_phase: "<X>", adopted_phase: "<Y>"}`.

**`history` field rules:**
- `history` is an append-only list of state-transition events in `pipeline_state.yaml`. See [SCHEMAS.md](assets/SCHEMAS.md) for the entry shape.
- Every phase transition appends an entry — minimum fields: `{ts, event, from_phase, to_phase}`. Additional fields (`note`, `dispatched_agents`, `reason`, etc.) are allowed.
- Never edit or delete prior history entries under any circumstance.

---

- **Thin controller.** Never perform analysis, planning, building, or reviewing. Only manage state transitions and context assembly.
- **Minimal context.** Each sub-agent gets ONLY its SKILL.md + required state files + context_to_load.
- **State is persistent.** All state lives in `pipeline_state.yaml`. The orchestrator is stateless between dispatches.
- **Automatic gates are mandatory and cannot be overridden.** Error-path escalations (merge conflicts, design issues, max-retry) require human intervention.
- **Max 3 build-review loops per task.** Escalate on the 4th attempt.
- **Design issues halt tasks AND the pipeline at stage boundaries.** Never retry a task with a design issue. At stage completion, if any design issues were raised in that stage, the pipeline halts for human resolution before advancing to the next stage. Requires architect intervention.
- **Append-only history.** Never delete or modify history entries in `pipeline_state.yaml`.
- **Context hygiene is mandatory.** Sub-agent output goes to /tmp log files, not inline. At stage boundaries, write a compact stage summary and do not reference prior stage details.
- **No auto-conflict resolution.** Merge conflicts always escalate to the human.
- **Escalation does not block the stage.** Other tasks continue. Only dependents in later stages are blocked.
- **Worktree cleanup is mandatory.** Never leave orphaned worktrees.
- **Retrospective is mandatory.** Every completed sprint gets a retrospective.
- **Sprint branch is mandatory.** All work happens on a sprint branch, never directly on main.
- **E2E validation is mandatory** when `commands.test_e2e` is configured. Skipped (with log message) when not configured.
- **Pipeline does not push or create PRs.** Publishing is handled by `/wf-skill-ship` after the pipeline completes.
