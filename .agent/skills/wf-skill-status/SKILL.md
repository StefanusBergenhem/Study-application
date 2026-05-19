---
name: wf-skill-status
description: Read-only pipeline inspector. Reads paths.pipeline_state plus sprint/task state and reports current phase, active task, per-task status, worktree locations, last action, and suggested next step. Safe to invoke at any time. Produces no artifacts.
---

# wf-skill-status — Pipeline Inspector

Read the workflow state and report a concise status summary. Read-only. Produces no artifacts.

All paths resolve through `config.yaml`. If `.workflow/` doesn't exist or `config.yaml` is missing, report that the project has not been initialised and suggest `/wf-skill-init`.

## Process

1. Read `paths.pipeline_state` for current phase and metadata.
2. Read `paths.current_task` if it exists — the active task being built or reviewed.
3. Read `paths.sprint` for sprint progress (task list + status fields).
4. Read `paths.feedback` if it exists — pending review feedback.
5. Read `paths.review_ready` if it exists — pending review.
6. Read `paths.stage_manifest` if it exists — active stage layout.

## Report shape

Render the following in a clear, structured format:

- **Current phase:** `analyse` | `plan_stage` | `build` | `review` | `idle` | `executing_stage` | `computing_stages` | other.
- **Active task:** step ID + title (or "None").
- **Sprint progress:** X of Y tasks complete.
- **Stage progress:** Stage N of M (if parallel execution is active).
- **Per-task status:** for each task in the current stage, show task ID, status (`building` / `reviewing` / `completed` / `escalated`), worktree path, attempt count.
- **Blocked tasks:** tasks in later stages blocked by escalated dependencies (or "None").
- **Attempt count:** N (if currently in a build/review cycle).
- **Last action:** what happened most recently.
- **Blockers:** any halt conditions or failures (or "None").
- **Worktree locations:** active worktrees + branches (if parallel execution is active).
- **Next step:** what skill to invoke next.

## Halt Conditions

- `.workflow/` missing or `config.yaml` missing → report that the project is not initialised and suggest `/wf-skill-init`.
- `paths.pipeline_state` is malformed → report the malformed state and stop (do not attempt to repair).
