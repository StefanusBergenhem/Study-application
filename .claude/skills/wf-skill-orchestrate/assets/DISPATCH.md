# Dispatch Protocol & Context Envelopes (OpenCode)

## Dispatch Protocol

For every state transition that requires a sub-agent:

1. **Read state.** Load `paths.pipeline_state`. Verify the current phase.
2. **Verify gate.** Confirm all automatic gate conditions are met for this transition.
3. **Assemble context envelope.** Each sub-agent receives ONLY the files listed below for its phase. Sub-agents do not get other skills' definitions, pipeline state details, or files outside their scope.
   - **Worktree path:** For per-task phases (build, review, e2e fix), include the worktree path in the sub-agent's prompt. Instruct the sub-agent: "Your working directory is `<worktree_path>`. All `.workflow/` references (reading and writing) resolve to `<worktree_path>/.workflow/.transient/`. Write all output artifacts there." This ensures sub-agents write feedback.yaml, review_ready.yaml, and design_issues.yaml directly to disk in the correct location.
4. **Announce transition.** State: "Dispatching [agent] for task [task_id] — transitioning from [old_phase] to [new_phase]."
5. **Spawn sub-agent.** Dispatch via the `task` tool with `subagent_type: general`. The `prompt` parameter must be the full prompt: **[agent prelude (embedded below)] + [context envelope (listed below)]** joined by a blank line. OpenCode does not auto-load agent files — the agent role and skill-loading instructions are embedded directly in the prompt.
6. **Wait.** Let the sub-agent complete its work.
7. **Read verdict.** Extract ONLY the verdict (APPROVED / REJECTED / DESIGN_ISSUE / ESCALATED) from the sub-agent's text return. Do NOT parse or retain detailed feedback, review analysis, or test output from the text — that content belongs in the on-disk artifacts. Check output artifacts exist on disk at `<worktree_path>/.workflow/.transient/` (review_ready.yaml, feedback.yaml, design_issues.yaml) to confirm they were written. Do not read their contents into the orchestrator's context; the next sub-agent will read them directly from disk.
8. **Update state.** Write the new phase to `pipeline_state.yaml`. Append to the history log.
9. **Gate check.** Verify automatic gate conditions are satisfied before proceeding.

## Context Envelopes

Per-phase agents are dispatched via the `task` tool with `subagent_type: general`. Unlike Claude Code, OpenCode does NOT auto-load agent `.md` files on dispatch. Instead, the orchestator embeds the agent's role, skill-loading instructions, and tool allowlist directly into the prompt **before** the context envelope (separated by `---`).

### Build Phase (per-task, in worktree)

**Agent prelude (embed at the top of the prompt):**

```
You are the Lead Developer. Your name is wf-build.

You execute the contract at `paths.current_task` (default `.workflow/.transient/current_task.yaml`) with precision. You do not plan. You do not expand scope.

## Skills to load

Load these skills before doing any work:

1. `wf-skill-build` — procedural source of truth. TDD workflow, fix mode, fix-resume mode, halt conditions, scope-expansion protocol, design-issue detection, artifact write contracts. **This is the load-bearing skill.**
2. `wf-skill-verification` — canonical completion checklist (Step 6 of `wf-skill-build`).
3. `wf-skill-testing-anti-patterns` — test quality rules (Red phase).

Your available tools: Read, Edit, Write, Bash, Grep, Glob, Skill
```

**Required envelope field:** `worktree_root` — the absolute filesystem path to the worktree root for this task. MUST be included in every build dispatch. The build agent reads this before any file mutation to enforce path discipline (see `wf-skill-build` § Worktree Path Discipline).

Prompt envelope (paths the agent must read on dispatch):
- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.feedback>` (if exists — Fix Mode)
- Files listed in `context_to_load` from the task contract
- Memory file at `paths.memory`
- `COMPONENTS.yaml` (for design issue detection)
- External skills config from `config.external_skills` (if configured)
- Cross-cutting skill: `skills/wf-skill-testing-anti-patterns/SKILL.md` (referenced from the agent's body — agent loads it during the Red phase)

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `review_ready.yaml` — build completion claim
- `design_issues.yaml` — appended to `paths.design_issues` if design issue detected

### Review Phase (per-task, in worktree)

**Agent prelude (embed at the top of the prompt):**

```
You are the QA Reviewer. Your name is wf-review.

You validate the Developer's work against the Architect's contract. You do not write code. You do not fix issues. You send them back with precise, actionable instructions.

## Skills to load

Load these skills before doing any work:

1. `wf-skill-review` — procedural source of truth. P0/P1/P2/P3 checklist, design-issue detection, post-APPROVED sequence, forbidden actions. **This is the load-bearing skill.**
2. `wf-skill-verification` — canonical completion checklist (referenced by §-notation in P0/P1 checks).
3. `wf-skill-testing-anti-patterns` — Quick Reference for P1.2 test-quality check.

External skills (`external_skills.defaults` + matching domains from `config.yaml`) load on top via the resolution rule in `wf-skill-review` Step 1b. They augment the checklist; they do **not** replace P0-P3 checks.

Your available tools: Read, Edit, Write, Bash, Grep, Glob, Skill
```

**Required envelope field:** `worktree_root` — the absolute filesystem path to the worktree root for this task. MUST be included in every review dispatch. The review agent reads this before any file mutation to enforce path discipline (see `wf-skill-review` § Worktree Path Discipline). All `paths.<x>` references from `config.yaml` (including `paths.sprint`, `paths.memory`, `paths.state`, `paths.design_issues`) resolve to `<worktree_root>/<config_path>` — never to a path outside the worktree. State and memory updates that are intended to land on the sprint branch must be written inside the worktree so the merge carries them.

Prompt envelope:
- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.review_ready>`
- Git diff (via `git diff origin/<sprint_branch>` within the worktree)
- Memory file at `paths.memory`
- Conventions file(s) at `paths.conventions`
- `COMPONENTS.yaml` (for architecture compliance)
- External skills config from `config.external_skills` (if configured)
- Cross-cutting skill: `skills/wf-skill-testing-anti-patterns/SKILL.md` (referenced from the agent's body — agent loads it during P1 Test Quality)

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `feedback.yaml` — rejection details (only on REJECTED verdict)
- `design_issues.yaml` — appended to `paths.design_issues` if design issue detected

### E2E Fix Cycle (per-attempt, in worktree)
Subagent for build: `wf-build`
Subagent for review: `wf-review`

Build dispatch: use the **Build Phase** agent prelude (above) + context envelope:

- `config.yaml`
- `<worktree_path>/<paths.current_task>` (synthetic E2E-FIX contract)
- `<worktree_path>/<paths.feedback>` (e2e failure details)
- Memory file at `paths.memory`
- `COMPONENTS.yaml`

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `review_ready.yaml` — build completion claim

Review dispatch: use the **Review Phase** agent prelude (above) + context envelope:

- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.review_ready>`
- Git diff (via `git diff origin/<sprint_branch>` within the worktree)
- Memory file at `paths.memory`
- `COMPONENTS.yaml`

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `feedback.yaml` — rejection details (only on REJECTED verdict)

### Retrospective Phase

**Agent prelude (embed at the top of the prompt):**

```
You are the Retrospective Analyst. Your name is wf-retrospective.

You run at the end of every sprint pipeline execution. You analyse what happened, produce a structured report, and refine the memory file.

## Skills to load

Load these before doing any work:

1. `wf-skill-retrospective` — procedural source of truth. Data gathering, pattern analysis, improvement suggestions, write contract for the retrospective report. **This is the load-bearing skill.**
2. `wf-skill-continuous-learning` — lesson extraction protocol invoked as Step 5 of the retrospective skill. Refines `paths.memory`, archives the processed retrospective, cleans resolved design issues.

Your available tools: Read, Edit, Write, Bash, Grep, Glob, Skill
```

Prompt envelope:
- `config.yaml`
- `paths.pipeline_state`
- `sprint.yaml`
- `design_issues.yaml` (if exists)
- `paths.components_drift` (if exists — component drift report from pre-retrospective scan)
- Memory file at `paths.memory` (for deduplication during lesson extraction)
- Cross-cutting skill: `skills/wf-skill-continuous-learning/SKILL.md` (referenced from the agent's body — agent loads it after writing the report)
