# wf → Pi Migration State

## Status: COMPLETE ✅ — all items resolved

The entire wf skills/ and agents/ have been copied to `.agent/` and adapted for Pi. All migration tasks are complete.

---

## ✅ Completed

### File copy & structure
- Copied all 16 skills to `.agent/skills/` (with assets, references, scripts)
- Copied all 6 agents to `.agent/agents/`
- All files present and accessible in the new location

### Path updates (`.claude/` → `.agent/`)
- `wf-skill-init/SKILL.md` — all paths updated
- `wf-skill-init/assets/workflow-config.yaml.tmpl` — `worktree_base` updated
- `wf-skill-init/scripts/sync_user_scripts.sh` — path updated
- `wf-skill-orchestrate/SKILL.md` — all paths updated
- `wf-skill-orchestrate/assets/GIT_OPERATIONS.md` — default path updated
- `wf-skill-orchestrate/assets/DISPATCH.md` — all paths updated
- `wf-skill-sa/SKILL.md` — script paths updated
- `wf-skill-sa/scripts/detect_components_drift.sh` — `.agent` added to skip dirs

### Agent frontmatter adaptation (Claude → Pi format)
All 6 agent files rewritten:
- Removed `tools:`, `model:` frontmatter fields (Pi doesn't use these)
- Updated "Skills to load" sections to use `read` tool instead of `Skill` tool
- Added tool usage guidance compatible with Pi's tool set
- SA agent (`wf-sa.md`) documents the sub-agent dispatch gap and inline fallback

### Tool references in skill bodies
- `wf-skill-build/SKILL.md`: "Read, Grep, cat" → "read, bash (with grep/rg/find), cat"
- `wf-skill-build/SKILL.md`: "must be loaded" → "must be read"
- `wf-skill-review/SKILL.md`: "must be loaded" → "must be read"
- `wf-skill-retrospective/SKILL.md`: "load ... and execute" → "load using the read tool"

### Claude Code references
- `wf-skill-ship/SKILL.md`: "Generated with Claude Code" → "Generated with pi"

### Template file rename
- `assets/project-claude.md.tmpl` → `assets/project-pi.md.tmpl`
- Content updated to reference "pi" instead of "Claude Code"
- Init skill updated to reference the renamed template

---

## 🔴 Remaining: Sub-agent dispatch tool

The orchestrator (`wf-skill-orchestrate`) and Solution Architect (`wf-skill-sa`) skills rely on a sub-agent dispatch mechanism that Claude Code provides via its `Agent` tool. This is used for:

1. **Orchestrator** (wf-skill-orchestrate): Dispatching `wf-build` and `wf-review` sub-agents to worktrees during stage execution, and `wf-retrospective` at sprint end.

2. **Orchestrator** (design-issue auto-routing): Dispatching `wf-swa` (fix mode) for `contract_amendment` or `wf-sa` (fix mode) for `spec_amendment` design issues.

3. **Solution Architect** (Phase 5): Dispatching `wf-arbitrator-review` to verdict the spec layer before commit.

### Affected files (already updated with fallback instructions)

| File | What it references |
|------|-------------------|
| `.agent/agents/wf-sa.md` | Documents the gap and provides inline fallback procedure |
| `.agent/skills/wf-skill-sa/SKILL.md` | Updated to say "sub-agent tool; inline as fallback" |
| `.agent/skills/wf-skill-orchestrate/SKILL.md` | References dispatching sub-agents conceptually |
| `.agent/skills/wf-skill-orchestrate/assets/DISPATCH.md` | Full dispatch protocol with inline fallback documented |

### ✅ Resolved — Pi's Agent tool is now available

All four items completed:

1. **Created** `.agent/WF_AGENT_TOOL_AVAILABLE` marker
2. **Updated** `.agent/skills/wf-skill-orchestrate/assets/DISPATCH.md` — replaced all inline-fallback notes with Agent-tool dispatch instructions
3. **Updated** `.agent/agents/wf-sa.md` — replaced inline arbitrator simulation with `Agent` tool dispatch
4. **Updated** `.agent/skills/wf-skill-sa/SKILL.md` (Phase 5 step 3) — simplified arbitrator dispatch to direct Agent tool call

---

## Files structure

```
.agent/
  agents/
    wf-build.md               # Developer agent
    wf-review.md              # QA gatekeeper agent
    wf-swa.md                 # Software Architect (sprint contracts)
    wf-sa.md                  # Solution Architect (spec layer)
    wf-retrospective.md       # Sprint retrospective agent
    wf-arbitrator-review.md   # Spec-layer verdict agent
  skills/
    wf-skill-build/           # TDD build workflow
    wf-skill-review/          # QA checklist-based review
    wf-skill-init/            # Idempotent project installer
    wf-skill-orchestrate/     # Pipeline state machine
    wf-skill-swa/             # Sprint detailing
    wf-skill-sa/              # Spec layer (COMPONENTS.yaml, ADRs)
    wf-skill-ship/            # Validation, push, PR
    wf-skill-status/          # Read-only pipeline inspector
    wf-skill-retrospective/   # Sprint analysis
    wf-skill-continuous-learning/  # Lesson extraction & archival
    wf-skill-strategist/      # Product roadmap authoring
    wf-skill-verification/    # Cross-cutting completion checklist
    wf-skill-testing-anti-patterns/  # Test quality rules
    wf-skill-spec-references/  # Canonical spec language (EARS, DbC, ADR, conventions, DIs)
    wf-skill-arbitrator-review/  # Spec-layer adjudicator
```
