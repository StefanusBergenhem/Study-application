# Ongoing mode — Phase 3 + Phase 4c

Activated when `paths.roadmap` does not exist but `paths.master_backlog` and
`paths.components` do. Job: evaluate current system health, refine the spec
layer (fill gaps, add REQs for un-specified responsibilities, author ADRs for
decisions taken in-flight, retire stale REQs), and cut the next sprint.

Return to `SKILL.md` for Phase 4a, 4b, 5, 6.

---

## Phase 3 — Design (ongoing variant)

Review components touched by the next pending sprint. Focus on:

1. **Architecture drift.** Has the codebase evolved since the spec layer was
   written? Are any REQs now stale? Any acceptance criteria un-testable now?
2. **Spec-layer gaps surfaced by the upcoming work.**
   - Does the next sprint touch behavior that has no SYS-REQ but should
     (user-visible end-to-end flow, cross-cutting NFR, system invariant)?
     If yes, sketch the SYS-REQ now.
   - Are there existing SYS-REQs whose `allocated_to:` is incomplete relative
     to the components the sprint will touch?
   - Are there component REQs that allocate a SYS-REQ but lack
     `derives_from:`, or vice versa?
3. **New technical decisions.** Do any pending backlog items require decisions
   not made when the spec layer was written? Work them through using the
   structured reasoning format:

   > **Decision:** [what you're deciding]
   > **Alternatives considered:**
   > - A: [option] — [tradeoff]
   > - B: [option] — [tradeoff]
   > **Recommended:** [which one] because [1-2 sentences]
   > **Risk of this choice:** [1 sentence]

4. **New ADR candidates.** Are there decisions taken implicitly in-flight that
   should now be ADRs? Mark candidates `<!-- ADR-CANDIDATE: <decision> -->`.
5. **Backlog health.** Items to split, merge, re-order, or remove based on
   current spec state?

Present findings feature-by-feature (or in small clusters for simple items).

**WAIT** for the human to acknowledge before proceeding to Phase 4.

---

## Phase 4c — Update the master backlog (ongoing variant)

Update the existing backlog: **preserve completed sprints**, apply re-scoping
from Phase 3, add new items where needed.

Ongoing-specific rule: `capability_ref` is **optional** — use it when items
trace to roadmap capabilities, omit for architecture-driven or maintenance
work.

Common backlog rules and the sprint-cut visualization live in `SKILL.md`
§Phase 4c.
