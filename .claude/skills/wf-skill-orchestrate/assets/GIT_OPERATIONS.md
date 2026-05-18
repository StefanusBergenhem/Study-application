# Git Operations Reference

All git command sequences used by the orchestrator. The sprint branch is the base for all operations — never work directly on main.

---

## Sprint Branch Creation

When transitioning to `creating_sprint_branch`:

1. **Read `sprint.yaml`** to get the `sprint_id`.

2. **Derive branch name:** `sprint/<sprint_id>` (e.g., `sprint/S1`).

3. **Create and push the branch:**
   ```bash
   git fetch origin
   git checkout -b sprint/<sprint_id> origin/main
   git push -u origin sprint/<sprint_id>
   ```

4. **Record in `pipeline_state.yaml`:**
   ```yaml
   sprint_branch: "sprint/<sprint_id>"
   ```

5. **Transition to `computing_stages`.**

---

## Worktree Creation

For each task in a stage, create a worktree branching from the sprint branch:

```bash
git fetch origin
WORKTREE_BASE=$(grep -A1 'worktree_base' .workflow/config.yaml | tail -1 | tr -d ' "' || echo ".claude/worktrees")
PIPELINE_STATE_PATH=$(grep -E '^\s*pipeline_state:' .workflow/config.yaml | awk '{print $2}' | tr -d '"' || echo ".workflow/.transient/pipeline_state.yaml")
SPRINT_BRANCH=$(grep sprint_branch "$PIPELINE_STATE_PATH" | awk '{print $2}' | tr -d '"')
git worktree add "${WORKTREE_BASE}/<branch-name>" -b <branch-name> origin/${SPRINT_BRANCH}
```

Branch naming: `<task_id>-<short-description>`, all lowercase, hyphens only.

After creating the worktree:
- Write `paths.current_task` (extract the task's contract from `paths.sprint`)
- Run baseline preflight (`commands.preflight` from config)

---

## Merge Protocol

When a task's review is approved:

1. **Merge to sprint branch** (not main):
   ```bash
   SPRINT_BRANCH=<sprint_branch from pipeline_state.yaml>
   git checkout ${SPRINT_BRANCH}
   git merge <branch> --no-ff
   ```

2. **On conflict:** Abort (`git merge --abort`), mark task as `merge_conflict`, escalate to human. Do NOT auto-resolve or force merge.

3. **On success:**
   ```bash
   git worktree remove <worktree_path>
   ```
   Update `task_states` to `completed`.

> **Note:** Individual task branches are never pushed to GitHub. The sprint branch is pushed once per stage after all merges and post-merge validation — see [Stage Completion Push](#stage-completion-push) below.

---

## Stage Completion Push

After all tasks in a stage are merged and **post-merge validation passes** (unit tests + integration tests + coverage + lint on the sprint branch), push the sprint branch:

```bash
SPRINT_BRANCH=<sprint_branch from pipeline_state.yaml>
git push origin ${SPRINT_BRANCH}
```

This is the only mid-pipeline push. It happens once per stage, not per task.

---

## Worktree Cleanup

Worktrees must be cleaned up in these scenarios:

1. **Stage completion (normal):** Remove all worktrees for completed tasks after merge.
2. **Stage completion (escalated/design_issue tasks):** Remove worktrees during stage cleanup.
   ```bash
   git worktree remove <worktree_path> --force
   ```
3. **Error recovery:** Check for orphaned worktrees:
   ```bash
   git worktree list
   ```
   Remove any under `parallel.worktree_base` that don't correspond to active tasks in `task_states`.

