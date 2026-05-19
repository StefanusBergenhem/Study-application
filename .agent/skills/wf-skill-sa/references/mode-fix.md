# Fix mode — full flow

Activated when `paths.arbitrator_feedback` exists at session start. The
previous arbitrator pass returned REJECTED. Job: address the specific findings
**only**, then re-dispatch the arbitrator. The normal Phase 1–4 flow does NOT
run in this mode.

---

## Flow

1. Read `paths.arbitrator_feedback`. Note iteration count and finding ids.
2. For each finding, identify which artifact and field. Plan a surgical fix.
3. Address **ONLY** the flagged issues. Preserve everything else.
4. **Do not re-author ADRs that were approved.** Do not re-write component REQs
   the arbitrator didn't flag. Scope is the findings list, nothing more.
5. After fixes, re-dispatch the arbitrator (`SKILL.md` §Phase 5).
6. On APPROVED, proceed to `SKILL.md` §Phase 6 (commit).
7. On REJECTED, repeat — up to the retry cap.

---

## Editorial discipline — no narrative comments in amended artifacts

When you amend a REQ, AC, ADR, or convention, do **not** leave inline
comments narrating the change. The spec file describes **current** state.
Historical narration belongs in:

- The commit message produced by this session.
- The resolved entry in `paths.design_issues` (when the amendment is
  design-issue-driven).
- An ADR (when the amendment meets the ADR threshold).

If the amended artifact is non-obvious without that context, leave a
**single-line pointer** — a finger pointing at the reasoning, never the
reasoning itself:

```yaml
# Acceptable pointers:
acceptance_criteria:
  - "AC-2: ..."             # see DI-VF-005
  - "AC-3: ..."              # rationale: ADR-019

# Not acceptable: multi-line prose explaining what changed and why.
```

The arbitrator's Category 2 surfaces multi-line inline comment blocks as a
warn. Use a pointer or move the prose to its proper home.

---

## Retry cap

3 attempts per session. If the 3rd consecutive verdict is REJECTED, halt and
escalate to the human — there is a systemic issue the fix loop is not
resolving. Do not commit.

---

## Meta-findings

For meta-findings (the arbitrator flagging that its own previous finding was
ambiguous): treat as a signal to fix more broadly than the literal finding
text suggested. Document what you interpreted in the commit message.
