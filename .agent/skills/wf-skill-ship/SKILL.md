---
name: wf-skill-ship
description: Validation gate. Verifies paths.pipeline_state is idle, runs commands.test_unit/integration/e2e plus coverage and db_validate, then pushes the sprint branch and opens a PR. Host-side; expects infrastructure access. Stops at the first failure — never auto-fixes.
---

# wf-skill-ship — Validation Gate

Run from the host side after the pipeline has produced a sprint branch. Validate, then push, then PR. Never on failure.

All paths and commands resolve through `config.yaml`.

## Prerequisites

- The pipeline must have completed (`paths.pipeline_state` shows `phase: idle`).
- The sprint branch exists locally.
- Infrastructure (DB, services) is running for integration / e2e tests.
- GitHub CLI (`gh`) is configured for push and PR creation.

## Steps

### 1. Verify pipeline completed

Read `paths.pipeline_state`. Check `current_phase` (or equivalent) is `idle`. If any other phase (`executing_stage`, `e2e_validation`, `retrospective`, etc.), HALT: "Pipeline is still running. Wait for completion before shipping."

### 2. Identify sprint branch

Read `sprint_branch` from `paths.pipeline_state`. Check it out:

```bash
git checkout <sprint_branch>
```

### 3. Run the full validation suite

Run each command in order. Stop at the first failure. Pipe all output to `/tmp/ship-*.log`.

#### 3a. Unit tests
```bash
<commands.test_unit> > /tmp/ship-test-unit.log 2>&1
```
Read the log. On failure: print summary and STOP.

#### 3b. Integration tests
```bash
<commands.test_integration> > /tmp/ship-test-integration.log 2>&1
```
On failure: STOP. If `commands.test_integration` is not configured or empty: skip with warning "No integration test command configured. Skipping."

#### 3c. End-to-end tests
```bash
<commands.test_e2e> > /tmp/ship-test-e2e.log 2>&1
```
On failure: STOP. If `commands.test_e2e` is not configured or empty: skip with warning.

#### 3d. Coverage
```bash
<commands.coverage> > /tmp/ship-coverage.log 2>&1
```
Read the log. Parse coverage for source files changed in this sprint (`git diff <base_branch> --name-only`). If any file is below `coverage.threshold` (default 90%), print the under-covered files with their percentages and STOP.

If `commands.coverage` is not configured: skip with warning.

#### 3e. Database validation
```bash
<commands.db_validate> > /tmp/ship-db-validate.log 2>&1
```
On failure: STOP. If `commands.db_validate` is not configured or empty: skip silently.

### 4. Report results

Print a summary table:

```
=== Ship Validation Results ===

  Check              Status    Details
  Unit tests         PASS      42 tests passed
  Integration tests  PASS      8 tests passed
  E2E tests          SKIP      Not configured
  Coverage           PASS      All files >= 90%
  DB validation      PASS      Schema up to date

All checks passed.
```

### 5. Push and open PR

If all checks pass:

```bash
git push -u origin <sprint_branch>
```

Then:

```bash
gh pr create \
  --base <base_branch> \
  --head <sprint_branch> \
  --title "Sprint <sprint_id>: <sprint summary from paths.sprint>" \
  --body "$(cat <<'EOF'
## Sprint Summary
<bullet list of completed tasks with their titles>

## Results
- Completed: <N> / <total> tasks
- Escalated: <list or "none">
- Design issues: <list or "none">

## Retrospective
See `<paths.retrospective>/<sprint-id>.md` for details.

🤖 Generated with [pi](https://github.com/earendil-works/pi)
EOF
)"
```

Print the PR URL.

### On failure

Print:

- Which check failed.
- The last 20 lines of the relevant log file.
- The full log file path for detailed inspection.

Do NOT attempt to fix anything. Do NOT push. The user investigates and re-runs the skill after fixing.

---

## Hard Constraints

- **Never push on failure.** Any single check failing means no push, no PR.
- **Never auto-fix.** Report and stop.
- **Run checks in order.** Unit → Integration → E2E → Coverage → DB. Stop at first failure.
- **Log everything.** All command output goes to `/tmp/ship-*.log`.
- **Host-only.** Expects infrastructure access. If a test fails because infrastructure is unavailable, report it clearly — don't treat it as a test failure.
- **Always create a PR on success.** The pipeline never publishes; this skill is the single entry point for pushing and PRs.
