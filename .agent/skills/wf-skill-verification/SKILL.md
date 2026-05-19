---
name: wf-skill-verification
description: Cross-cutting evidence-based completion checking. Ensures every claim of done is backed by fresh, verifiable evidence — not assumptions or cached results.
---

# Verification — Evidence-Based Completion Checking

## Purpose

Ensure that every claim of "done" is backed by fresh, verifiable evidence. This skill prevents the agent from declaring victory based on assumptions, cached results, or wishful thinking.

**This skill is the single source of truth for completion checks.** Both the build skill (self-check before handoff) and the review skill (independent verification) reference this checklist. Do not duplicate these checks elsewhere — point here instead.

## Core Principle

**Claims without evidence are lies.**

It does not matter if you "know" the code is correct. It does not matter if it "should" work. If you have not run the command and seen the output in this session, you do not know. Produce the evidence or do not claim completion.

## When This Skill Activates

- Before marking any task, step, or phase as complete.
- Before submitting work for review.
- Before reporting success to the user.
- After applying any fix (to confirm the fix worked).

## The Verification Checklist

Every completion claim must pass ALL applicable checks. Skip none.

### 1. Fresh Test Run

- [ ] Tests were executed in this session, not referenced from a previous run.
- [ ] Test output is captured and shown — not summarized, not paraphrased.
- [ ] All tests pass. If any test is skipped, there is a documented reason.
- [ ] No test caching was used (`--no-cache`, `--forceExit`, or equivalent for the framework).
- [ ] The test command matches what CI would run — not a subset, not a filtered version.

**Evidence format:**
```
TEST RUN:
  Command: <exact command>
  Output: <full output or relevant excerpt showing pass/fail counts>
  Result: ALL PASS / X FAILURES (list them)
```

### 2. Preflight Pass

- [ ] Linting passes with zero warnings (not just zero errors).
- [ ] Type checking passes (if applicable).
- [ ] Build completes successfully (if applicable).
- [ ] Formatting is applied (not just checked — actually applied).

**Evidence format:**
```
PREFLIGHT:
  Lint: <command> -> <result>
  Types: <command> -> <result>
  Build: <command> -> <result>
  Format: <command> -> <result>
```

### 3. Scope Compliance (via Scope Guard)

- [ ] `git diff --name-only` output matches `files_to_touch` from the contract.
- [ ] No files outside scope were modified.
- [ ] No unintended new files were created.
- [ ] No files were deleted that shouldn't have been.

**Evidence format:**
```
SCOPE CHECK:
  files_to_touch: [list from contract]
  git diff --name-only: [actual output]
  Match: YES / NO (explain discrepancy)
```

### 4. No Suppression Directives

- [ ] No `// @ts-ignore`, `// @ts-expect-error` (without a linked issue), `# type: ignore`, `// eslint-disable`, `# noqa`, `# noinspection`, `@SuppressWarnings`, or equivalent was added.
- [ ] If a suppression directive already existed and was NOT part of the task, it was not removed (scope guard applies).
- [ ] If a suppression directive is genuinely necessary, it includes a comment explaining why and linking to an issue/ticket.

**Check command:**
```bash
git diff | grep -E "(ts-ignore|ts-expect-error|eslint-disable|noqa|noinspection|SuppressWarnings|type:\s*ignore)"
```

### 5. No Debug Output

- [ ] No `console.log`, `print()`, `debugger`, `binding.pry`, `dd()`, or equivalent debug statements were added.
- [ ] No commented-out code was left behind.
- [ ] No temporary test values (hardcoded IDs, localhost URLs, "test123") remain.

**Check command:**
```bash
git diff | grep -E "^\+" | grep -E "(console\.log|debugger|binding\.pry|dd\(|print\(|System\.out\.print|var_dump)"
```

### 6. No TODO Comments

- [ ] No new `TODO`, `FIXME`, `HACK`, `XXX`, or `TEMP` comments were introduced.
- [ ] If a TODO is genuinely needed (known limitation that is out of scope), it includes a ticket/issue reference.

**Check command:**
```bash
git diff | grep -E "^\+" | grep -E "(TODO|FIXME|HACK|XXX|TEMP)"
```

### 7. Red-Phase Evidence (for TDD tasks)

When the task follows TDD, the "red phase" evidence must show actual test failures:

- [ ] Tests were run BEFORE implementation code was written.
- [ ] The test output shows real failures (not compilation errors, not import errors — actual assertion failures or missing-method errors that prove the test is checking the right thing).
- [ ] The failure messages correspond to the behavior being implemented.

**Evidence format:**
```
RED PHASE:
  Command: <test command>
  Failures:
    - <test name>: <failure message>
    - <test name>: <failure message>
  Interpretation: These failures confirm the tests are checking <behavior> which does not yet exist.
```

### 8. Diff Review

- [ ] Review your own `git diff` as if you were a code reviewer.
- [ ] Every changed line has a reason. No accidental whitespace changes, no unrelated formatting.
- [ ] The diff tells a coherent story — a reviewer should be able to understand the change from the diff alone.

## Evidence Presentation Format

When presenting completion evidence, use this structure:

```
## Verification Evidence

### Tests
<evidence>

### Preflight
<evidence>

### Scope
<evidence>

### Clean Code Checks
- Suppression directives: NONE ADDED
- Debug output: NONE ADDED
- TODOs: NONE ADDED

### Diff Summary
- Files changed: <count>
- Lines added: <count>
- Lines removed: <count>
- All changes within scope: YES/NO
```

## What Disqualifies a Completion Claim

Any of the following instantly disqualifies a "done" claim:

| Disqualifier | Example |
|-------------|---------|
| Stale evidence | "Tests passed earlier" without fresh output |
| Partial evidence | Showing 3 of 10 tests passing |
| Summarized evidence | "All tests pass" without showing the output |
| Assumed evidence | "This should work because..." |
| Suppressed failures | Adding `skip` to failing tests |
| Scope violations | Files changed that aren't in `files_to_touch` |
| Lingering debug code | `console.log` left in production code |
| Untested error paths | Every error/exception path in the implementation written for this task must have a corresponding test. If the implementation has N distinct error returns/throws, there must be at least N error-path tests. "Only happy-path tests exist" is a disqualifier. |

## Relationship to Other Skills

- **Testing Anti-Patterns** ensures the tests themselves are valid evidence.
