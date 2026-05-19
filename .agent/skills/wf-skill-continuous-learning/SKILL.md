---
name: wf-skill-continuous-learning
description: Cross-cutting protocol that extracts refined lessons from retrospective outputs into a structured memory file, enforces capacity limits, and archives processed documents. Routes wf-toolkit feedback (`process_rules`) to `paths.wf_candidates` when set. Invoked as the final step of the retrospective phase.
---

# Skill: Continuous Learning — Lesson Extraction & Archival

You are the Learning Extractor. You run at the end of every retrospective. You read the retrospective report and design issues, extract actionable lessons into a compact structured memory file, and archive the retrospective so it doesn't consume context in future pipeline runs.

---

## Inputs

| Input | Location | Purpose |
|:------|:---------|:--------|
| Retrospective Report | `paths.retrospective/<sprint-id>.md` (`paths.retrospective` in config) | Source of improvement suggestions and failure patterns |
| Design Issues | `design_issues.yaml` (`paths.design_issues` in config, optional) | Open vs resolved design issues |
| Memory File | `docs/MEMORY.yaml` (`paths.memory` in config) | Current lessons to deduplicate against |
| Pipeline State | `paths.pipeline_state` | Sprint ID and task states |
| Config | `.workflow/config.yaml` | Learning settings, paths, archive preferences |

---

## Process

### Step 1 — Load Inputs

1. Read `paths.pipeline_state` — extract `sprint_id`.
2. Read the retrospective report at `paths.retrospective/<sprint-id>.md` (`paths.retrospective` in config).
3. Read `docs/MEMORY.yaml` (`paths.memory` in config). If it does not exist, initialise from the template (empty `lessons: []` list with `version: 1`).
4. If `design_issues.yaml` (`paths.design_issues` in config) exists, load it to identify resolved vs open issues.
5. Read `config.yaml` learning settings. **If `learning.enabled` is false, skip all operations and report "Learning disabled in config." then exit.** Otherwise read `learning.max_memory_entries`, `learning.archive_retrospectives`, etc. Use defaults if individual settings are not configured.

### Step 2 — Extract Lessons

Parse the retrospective report to identify actionable lessons. Focus on:

#### From "What Failed" section:
- For each failed task, extract the **root cause** and **category**
- If the root cause is a contract problem (missing context file, wrong scope), create a `contract_patterns` lesson
- If the root cause is component-specific, create a `component_rules` lesson
- If the same rejection type appears across multiple tasks, create a `rejection_patterns` lesson

#### From "Suggested Improvements" section:
- Each specific suggestion becomes a candidate lesson
- Map to the appropriate category:
  - Workflow suggestions → `process_rules` (see § Routing process_rules below)
  - Architecture suggestions → `architecture_signals`
  - Task sizing suggestions → `contract_patterns`
  - Contract quality suggestions → `contract_patterns` or `component_rules`

#### Lesson format:
For each extracted lesson, produce:

```yaml
- id: "L-<next_number>"
  category: "<category>"
  rule: "<one-sentence actionable rule>"
  evidence:
    - sprint: "<sprint_id>"
      tasks: ["<task_ids>"]
      detail: "<brief evidence>"
  confidence: "<high|medium>"
  created: "<today's date>"
  last_reinforced: "<today's date>"
```

**Confidence scoring:**
- `high` — Pattern observed across 2+ tasks in this sprint, OR reinforces an existing lesson
- `medium` — Single observation, first occurrence

**Quality bar for lessons:**
- The `rule` field must be a concrete, actionable instruction — not an observation
- Bad: "Component auth had low pass rate"
- Good: "Include auth/types.ts in context_to_load for all tasks touching auth/"
- Bad: "Tests were rejected for quality issues"
- Good: "Testing mandates for API endpoints must include error response shape assertions"

#### Routing `process_rules` (wf-toolkit feedback)

`process_rules` lessons describe improvements to the **wf toolkit itself** — pipeline mechanics, skill instructions, agent boundaries — not project rules. They have no automated consumer; they're for the wf maintainer to act on.

Route based on `paths.wf_candidates`:

- **If `paths.wf_candidates` is set** (the project co-develops the wf toolkit in-tree, e.g., a wf-on-dems setup): append each `process_rules` lesson as a markdown block to that file. Use the schema in `assets/wf_candidate.md.tmpl`. Do NOT add it to MEMORY.yaml. Do NOT apply capacity capping (Step 4) or YAML dedup (Step 3) to these entries — they're long-form markdown for human review.
- **If `paths.wf_candidates` is empty or absent** (normal project — wf is a separate dependency): keep the `process_rules` lesson in MEMORY.yaml using the standard structured-lesson format. Subject to Step 3 dedup and Step 4 capacity capping like other categories.

When routing to `paths.wf_candidates`, **strip project-specific details** from the lesson text. The wf toolkit is project-agnostic; entries describing a dems schema, a dems path, or a dems framework choice do not belong there — keep those in MEMORY.yaml's `process_rules` regardless of routing. If the lesson can be generalised, generalise it; if it cannot, keep it in MEMORY.yaml.

### Step 3 — Deduplicate Against Existing Memory

For each new lesson, check existing entries in the memory file:

1. **Exact match** — same category and semantically identical rule → skip (no duplicate)
2. **Reinforcement** — same category and similar rule (same component, same pattern) →
   - Bump confidence to `high` if currently `medium`
   - Append the new sprint to the `evidence` list
   - Update `last_reinforced` to today's date
   - Do NOT create a new entry
3. **New lesson** — no matching entry → add as new entry with next available `L-<number>` ID

### Step 4 — Enforce Memory Capacity

Read `max_entries` from the memory file (or `learning.max_memory_entries` from config, default 30).

If the total lesson count (existing + new) exceeds `max_entries`:

1. **Rank all entries** by priority score:
   - confidence: `high` = 2, `medium` = 1
   - evidence count: +1 per evidence entry
   - recency: +1 if `last_reinforced` within last 3 sprints
   - Total score = confidence_score + evidence_count + recency_bonus

2. **Archive lowest-ranked entries** to `.workflow/archive/lessons-archived.yaml`:
   - Append the pruned entries to the archive file (create if it doesn't exist)
   - Include an `archived_at` timestamp and `reason: "capacity_limit"`
   - Remove them from the active memory file

3. **Trim to `max_entries`** — keep the highest-scored entries.

### Step 5 — Archive Source Documents

Based on config settings (all default to `true`):

#### If `learning.archive_retrospectives` is true:
- Create `paths.archive_retrospective` directory if it doesn't exist
- Move `paths.retrospective/<sprint-id>.md` to `paths.archive_retrospective/<sprint-id>.md`

#### If `learning.cleanup_design_issues` is true:
- Read `design_issues.yaml` (`paths.design_issues` in config)
- Remove entries with `status: resolved`
- Keep entries with `status: open` or `status: overridden`
- If all entries were resolved, delete the file
- If some remain, write the filtered list back

### Step 6 — Write Outputs

1. **Write the updated `docs/MEMORY.yaml`** (`paths.memory` in config) with all lessons (existing + new, minus archived).
2. **Announce summary:** "Learning complete: extracted N new lessons, reinforced M existing, archived K source documents. Memory file has T/max_entries entries."

---

## Memory File Schema

The memory file uses structured YAML for programmatic consumption by build, review, and SWA skills:

```yaml
# Managed by wf-skill-continuous-learning after each sprint.
# Consumed by build, review, and SWA skills as context.

version: 1
max_entries: 30

lessons:
  - id: "L-001"
    category: "contract_patterns"
    rule: "Whenever a domain's source files use a naming or pattern rule, surface it explicitly in domains.<name>.conventions — the build skill reads the resolved conventions set in Step 1a, but only what's written down counts"
    evidence:
      - sprint: "S1"
        tasks: ["S1.3", "S1.5"]
        detail: "Both rejected for convention_violation; the rule lived in source files only, not in any conventions document"
    confidence: "high"
    created: "2026-03-15"
    last_reinforced: "2026-03-20"
```

### Categories

| Category | What it captures | Consumed by |
|:---------|:-----------------|:------------|
| `contract_patterns` | Task contract quality rules (context_to_load, files_to_touch, scope) | SwA |
| `component_rules` | Component-specific rules (always load file X for component Y) | SwA, Build |
| `rejection_patterns` | Recurring rejection types and proven fixes | Review, Build |
| `architecture_signals` | Design-level patterns for architectural planning | SA, SwA |
| `process_rules` | wf-toolkit / pipeline / workflow improvements surfaced by the retrospective | **Human review** — no agent consumes these. They accumulate in MEMORY.yaml as candidate wf-framework changes for the maintainer to act on between sprints. |

---

## Output

| Artifact | Location | Description |
|:---------|:---------|:------------|
| Updated Memory File | `docs/MEMORY.yaml` (`paths.memory` in config) | Compact structured lessons |
| Archived Retrospective | `paths.archive_retrospective/<sprint-id>.md` | Moved from active directory |
| Cleaned Design Issues | `design_issues.yaml` (`paths.design_issues` in config) | Resolved issues removed |
| Archived Lessons | `.workflow/archive/lessons-archived.yaml` | Pruned low-priority lessons |
| wf Candidate Entries | `paths.wf_candidates` (when set) | Appended markdown blocks routing `process_rules` lessons to a co-developed wf toolkit |

---

## Hard Constraints

- **Actionable rules only.** Every lesson must be a concrete instruction, not an observation. If you cannot phrase it as "do X" or "always include Y", it is not a lesson.
- **No duplicates.** Always check existing memory before adding. Reinforce, don't duplicate.
- **Capacity is enforced.** Never exceed `max_entries`. Archive before adding if at capacity.
- **Evidence required.** Every lesson must cite specific task IDs and sprint IDs. No lessons from general impressions.
- **Archive, don't delete.** Source documents move to archive directories — they are never destroyed.
- **Config-driven.** All archival behaviours are controlled by config flags. Respect disabled settings.

---

## Halt Conditions

Stop and report if:
- The retrospective report does not exist at `paths.retrospective/<sprint-id>.md` (`paths.retrospective` in config)
- `pipeline_state.yaml` does not exist or has no `sprint_id`
- The memory file exists but is malformed (not valid YAML, missing `version` or `lessons` keys)
