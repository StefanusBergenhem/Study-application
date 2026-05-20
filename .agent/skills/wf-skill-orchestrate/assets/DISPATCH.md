# Dispatch Protocol & Context Envelopes

**Note:** This protocol uses Pi's `Agent` tool for sub-agent dispatch. The orchestrator dispatches sub-agents with `subagent_type` set to the agent name (`wf-build`, `wf-review`, `wf-retrospective`), the context envelope as the prompt, and the model selected from `config.yaml` → `models.<phase>`. Sub-agents run in isolated contexts and return verdicts on completion.

## Dispatch Protocol

For every state transition that requires a sub-agent:

1. **Read state.** Load `paths.pipeline_state`. Verify the current phase.
2. **Verify gate.** Confirm all automatic gate conditions are met for this transition.
3. **Assemble context envelope.** Each sub-agent receives ONLY the files listed below for its phase. Sub-agents do not get other skills' definitions, pipeline state details, or files outside their scope.
   - **Worktree path:** For per-task phases (build, review, e2e fix), include the worktree path in the sub-agent's prompt. Instruct the sub-agent: "Your working directory is `<worktree_path>`. All `.workflow/` references (reading and writing) resolve to `<worktree_path>/.workflow/.transient/`. Write all output artifacts there." This ensures sub-agents write feedback.yaml, review_ready.yaml, and design_issues.yaml directly to disk in the correct location.
4. **Select model.** Read `models.<phase>` from `config.yaml` (e.g., `models.build`, `models.review`).
5. **Announce transition.** State: "Dispatching [agent] for task [task_id] with model [model] — transitioning from [old_phase] to [new_phase]."
6. **Spawn sub-agent.** Dispatch via the `Agent` tool with `subagent_type` set to the agent name for the phase (`wf-build`, `wf-review`, or `wf-retrospective`), the assembled context envelope as the prompt, and the selected model.
7. **Wait.** Let the sub-agent complete its work.
8. **Read verdict.** Extract ONLY the verdict (APPROVED / REJECTED / DESIGN_ISSUE / ESCALATED) from the sub-agent's text return. Do NOT parse or retain detailed feedback, review analysis, or test output from the text — that content belongs in the on-disk artifacts. Check output artifacts exist on disk at `<worktree_path>/.workflow/.transient/` (review_ready.yaml, feedback.yaml, design_issues.yaml) to confirm they were written. Do not read their contents into the orchestrator's context; the next sub-agent will read them directly from disk.
9. **Update state.** Write the new phase to `pipeline_state.yaml`. Append to the history log.
10. **Gate check.** Verify automatic gate conditions are satisfied before proceeding.

## Context Envelopes

Per-phase agents are dispatched via the available sub-agent tool with the `subagent_type` field set to the agent name. The agent's system prompt (its `.agent/agents/wf-*.md` file) is loaded by the sub-agent tool at dispatch time — the orchestrator does NOT pass the agent file as part of the prompt envelope. The envelope below is the per-task context the orchestrator passes as the prompt content.

### Build Phase (per-task, in worktree)
Subagent: `wf-build`
Model: `config.yaml → models.build` (default: `deepseek/deepseek-v4-flash`)

**Required envelope field:** `worktree_root` — the absolute filesystem path to the worktree root for this task. MUST be included in every build dispatch. The build agent reads this before any file mutation to enforce path discipline (see `agents/wf-build.md` § Worktree Path Discipline).

Prompt envelope (paths the agent must read on dispatch):
- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.feedback>` (if exists — Fix Mode)
- Files listed in `context_to_load` from the task contract
- Memory file at `paths.memory`
- `COMPONENTS.yaml` (for design issue detection)
- External skills config from `config.external_skills` (if configured)
- Cross-cutting skill: `.agent/skills/wf-skill-testing-anti-patterns/SKILL.md` (referenced from the agent's body — agent loads it during the Red phase)

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `review_ready.yaml` — build completion claim
- `design_issues.yaml` — appended to `paths.design_issues` if design issue detected

### Review Phase (per-task, in worktree)
Subagent: `wf-review`
Model: `config.yaml → models.review` (default: `deepseek/deepseek-v4-flash`)

**Required envelope field:** `worktree_root` — the absolute filesystem path to the worktree root for this task. MUST be included in every review dispatch. The review agent reads this before any file mutation to enforce path discipline (see `agents/wf-review.md` § Worktree Path Discipline). All `paths.<x>` references from `config.yaml` (including `paths.sprint`, `paths.memory`, `paths.state`, `paths.design_issues`) resolve to `<worktree_root>/<config_path>` — never to a path outside the worktree. State and memory updates that are intended to land on the sprint branch must be written inside the worktree so the merge carries them.

Prompt envelope:
- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.review_ready>`
- Git diff (via `git diff origin/<sprint_branch>` within the worktree)
- Memory file at `paths.memory`
- Conventions file(s) at `paths.conventions`
- `COMPONENTS.yaml` (for architecture compliance)
- External skills config from `config.external_skills` (if configured)
- Cross-cutting skill: `.agent/skills/wf-skill-testing-anti-patterns/SKILL.md` (referenced from the agent's body — agent loads it during P1 Test Quality)

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `feedback.yaml` — rejection details (only on REJECTED verdict)
- `design_issues.yaml` — appended to `paths.design_issues` if design issue detected

### E2E Fix Cycle (per-attempt, in worktree)
Subagent for build: `wf-build`
Subagent for review: `wf-review`
Model: `config.yaml → models.build` (default: `deepseek/deepseek-v4-flash`) for build, `config.yaml → models.review` (default: `deepseek/deepseek-v4-flash`) for review

Build dispatch prompt envelope (same as normal build, with synthetic task contract):
- `config.yaml`
- `<worktree_path>/<paths.current_task>` (synthetic E2E-FIX contract)
- `<worktree_path>/<paths.feedback>` (e2e failure details)
- Memory file at `paths.memory`
- `COMPONENTS.yaml`

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `review_ready.yaml` — build completion claim

Review dispatch prompt envelope (same as normal review):
- `config.yaml`
- `<worktree_path>/<paths.current_task>`
- `<worktree_path>/<paths.review_ready>`
- Git diff (via `git diff origin/<sprint_branch>` within the worktree)
- Memory file at `paths.memory`
- `COMPONENTS.yaml`

Output artifacts (written by sub-agent to `<worktree_path>/.workflow/.transient/`):
- `feedback.yaml` — rejection details (only on REJECTED verdict)

### Retrospective Phase
Subagent: `wf-retrospective`
Model: `config.yaml → models.retrospective` (default: `deepseek/deepseek-v4-flash`)

Prompt envelope:
- `config.yaml`
- `paths.pipeline_state`
- `sprint.yaml`
- `design_issues.yaml` (if exists)
- `paths.components_drift` (if exists — component drift report from pre-retrospective scan)
- Memory file at `paths.memory` (for deduplication during lesson extraction)
- Cross-cutting skill: `.agent/skills/wf-skill-continuous-learning/SKILL.md` (referenced from the agent's body — agent loads it after writing the report)
