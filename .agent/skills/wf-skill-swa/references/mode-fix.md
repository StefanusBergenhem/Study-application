# Fix mode — Resolve one contract_amendment DI

Triggered when the orchestrator dispatches `wf-swa` to resolve a design issue with `fix_kind: contract_amendment`. The job: amend a single task contract in `paths.sprint` surgically — no source-code changes, no spec-layer changes — and flip the DI status to `resolved` so the orchestrator can re-dispatch the original task.

The dispatch envelope provides the DI id to resolve and the path context. Read `wf-skill-spec-references/references/design-issues.md` before starting so the `fix_kind` taxonomy is fresh.

---

## Step 1 — Validate routing

1. Read `paths.design_issues` and locate the entry by `id`.
2. Verify `fix_kind == "contract_amendment"`. If anything else, HALT — the orchestrator routed incorrectly. Emit `WF-SWA HALT — routing_error: di=<id> fix_kind=<value>` and exit.
3. Verify `status` is `open` or `routing`. If `resolved` or `overridden`, HALT — no work to do.
4. Verify the DI's `task_id` exists in `paths.sprint`. If not, HALT with `WF-SWA HALT — task_not_found: di=<id> task=<task-id>`.

---

## Step 2 — Diagnose the contract defect

1. Read the DI's `summary` and `impact` to understand what defect the producer (build or review) found.
2. Read the task contract in `paths.sprint` (the entry whose `id` matches the DI's `task_id`).
3. Read the relevant source REQ/AC/DbC in `paths.components` — the task's `requirements_extract` and `parent_interface` quote them.
4. **Confirm the classification.** The DI claims the defect lives in the contract slice while the spec reads correctly. Verify:
   - The contract slice diverges from the source REQ/AC/DbC in a way that explains the producer's complaint.
   - The source REQ/AC/DbC in `paths.components` is correct on its own terms.
5. **If you disagree** (the spec itself is the defect), HALT with a meta-finding. Append to the DI entry:
   ```yaml
   reclassification_proposed: spec_amendment
   reclassification_reason: "<one-line: why the spec is actually the defect>"
   ```
   Print `WF-SWA HALT — reclassification: di=<id> proposed_fix_kind=spec_amendment`. The orchestrator routes from there. Do **not** silently amend the spec — that is SA's territory.

---

## Step 3 — Amend the task contract

Make the minimum amendment to `paths.sprint` that resolves the DI's specific complaint. Apply every rule in `SKILL.md` § Universal contract-authoring discipline as you write the amendment.

Common amendment shapes:

- **Defective AC text.** Rewrite the AC; ensure it still traces to the source REQ via the `(REQ-NNN)` handle and is testable (concrete, measurable, observable behavior).
- **Wrong `testing_mandate` target.** Correct the target path; ensure it's in `files_to_touch` (scope-consistency rule).
- **Missing `files_to_touch` entry.** Add the file. If adding it exceeds the sizing budget, this is no longer a pure contract amendment — escalate via the meta-finding shape in Step 2 step 5.
- **Malformed `parent_interface` slice.** Re-quote the DbC clause verbatim from `paths.components`.
- **Concrete-observable mismatch in AC** (the AC asserts behavior no merged code path produces). Either rewrite the AC to match the actual merged behavior, or — if the AC describes intended-but-unbuilt behavior — escalate via meta-finding for `spec_amendment` or human triage.

Do **not** exceed minimum-amendment scope:

- Do not refactor unrelated tasks.
- Do not change other ACs or testing items not implicated by the DI.
- Do not amend the spec layer (`paths.components`, `paths.adrs`, `paths.master_backlog`).
- Do not touch source code.

---

## Step 4 — Flip DI status

Update the DI entry in `paths.design_issues`:

```yaml
status: resolved
# Leave resolution_commit empty — the orchestrator backfills it after observing the commit.
```

---

## Step 5 — Commit and report

Follow `SKILL.md` § Commit hygiene. Stage exactly `paths.sprint` and `paths.design_issues`. Subject convention:

```
<project-prefix> SwA fix — <DI-id> resolved (<task-id> contract amended)

• <one-line description of the amendment>
• Reference: <DI-id> raised by <detected_by>
```

After successful commit, report:

```
WF-SWA FIX RESOLVED — di=<id> task=<task-id> commit=<short-sha>
```

The orchestrator parses this signal, backfills `resolution_commit` in the DI entry, and re-dispatches the original task at its current attempt count.

---

## Retry cap

If you cannot satisfy the DI within 3 consecutive amendment attempts (each refining the previous), HALT with:

```
WF-SWA HALT — fix_unconvergent: di=<id> attempts=3
```

The orchestrator escalates to the human. This matches the spirit of `review.max_attempts` for the build/review loop — a contract amendment that won't converge is itself a signal of a deeper design issue that needs human judgement.
