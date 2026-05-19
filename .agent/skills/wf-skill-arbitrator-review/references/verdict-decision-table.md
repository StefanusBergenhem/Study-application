# Verdict Decision Table

Decision rules for the final verdict after all 6 check categories run.

## Decision table

| Condition                                          | Verdict                                            |
|----------------------------------------------------|----------------------------------------------------|
| Any Category-1 (DESIGN_ISSUE) finding              | **ESCALATE** — stop here, ignore other findings    |
| Any `block` finding in Categories 2–6              | **REJECTED**                                       |
| ≥3 `warn` findings across Categories 2–6           | **REJECTED** (aggregation)                         |
| 1–2 `warn` findings, no blocks                     | **APPROVED** (with warns printed)                  |
| 0 findings                                         | **APPROVED** (clean)                               |

## When to escalate (DESIGN_ISSUE)

Escalation is for problems that **cannot** be fixed by SA re-running. The
problem lives upstream of SA's mandate.

- A REQ traces to a roadmap capability or external constraint that doesn't
  exist → roadmap layer.
- A backlog item requires a decision that no REQ or ADR addresses, and the
  choice rightly lives at product level → roadmap / Strategist.
- Two roadmap capabilities imply incompatible architectural choices that SA
  has no basis to pick between → roadmap / Strategist.
- The project mandate is unclear at a level SA cannot resolve → human.

**Routing field `target_layer`:**

| target_layer | When                                                            |
|--------------|-----------------------------------------------------------------|
| `roadmap`    | Roadmap is silent on a load-bearing question, or capabilities conflict. |
| `strategist` | Stakeholder-level disagreement needs Strategist resolution.     |
| `human`      | Genuine design-level question with no clear upstream target — needs direct human judgement. |

If `target_layer = roadmap`, the human re-runs `/wf-skill-strategist`. If
`target_layer = human`, the human resolves directly and re-runs `/wf-skill-sa`.

## When NOT to escalate

The arbitrator does **not** have a "human input loop" for borderline calls.
That role is filled by REJECTED with a `warn`-severity finding — the SA reads
the warning and decides whether to address it. This preserves verdict
actionability and avoids paralysing the pipeline.

Examples that are NOT escalations:

- "The composition feels off." → REJECTED with a `warn` finding pointing at
  the specific component.
- "ADR alternatives are thin." → REJECTED with a `warn` finding.
- "[DEFER-NUMERIC]" on an NFR threshold — the deferral itself is fine, but the
  arbitrator can flag that downstream consumers may need the number sooner than
  expected → `warn`.

## Aggregation example

Three reviews of the same artifact set across SA fix iterations:

**Iteration 1** (greenfield):
- 5 block findings → REJECTED.

**Iteration 2** (after SA fix):
- 1 block (one item from iter-1 wasn't fixed correctly), 2 warns → REJECTED.
- Arbitrator notices the block is on the same field as F-003 from iter-1;
  raise `meta-finding` flagging "previous finding may have been unclear".

**Iteration 3** (after SA fix):
- 0 blocks, 1 warn → APPROVED (with warn printed).

**Iteration 4 (if iter-3 had been REJECTED):** 3-retry cap fires. Escalate to
human regardless of finding count: `ARBITRATOR ESCALATE, target_layer=human,
reason="3-retry cap exceeded — systemic issue"`.

## Per-iteration check budget

Don't re-do checks the previous iteration approved. In fix mode:

1. Read previous `arbitrator_feedback.yaml`.
2. For each finding, verify it has been addressed in the current artifact state.
3. Run only **categories that had findings** in the previous iteration.
   Categories that were clean don't need re-checking unless the fix may have
   introduced regressions in them (a fix that adds an exposes block affects
   Category 2 DbC checks; a fix that adds a new component affects Category 4
   cross-artifact checks).

This keeps fix-mode reviews cheaper than greenfield reviews.

## Stop-and-emit timing

After verdict is decided:

1. Write the output file (`arbitrator_feedback.yaml` or
   `arbitrator_escalation.yaml`, or nothing for APPROVED).
2. Print the one-line summary.
3. **Stop.** The verdict is final for this iteration.

If you discover a finding mid-write that should have been a Category-1
DESIGN_ISSUE, discard the partial feedback file and emit
`arbitrator_escalation.yaml` instead. Escalation preempts rejection.
