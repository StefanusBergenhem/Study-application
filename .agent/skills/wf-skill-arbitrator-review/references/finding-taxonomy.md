# Finding Taxonomy

Structure and severity rules for `arbitrator_feedback.yaml` findings.

## Finding fields

```yaml
- id: F-001                              # unique within this review
  category: <one of the 6 check categories>
  artifact: <relative path>              # which file the finding lives in
  field: <YAML path or H2 heading>       # e.g. "components.auth.requirements[0].acceptance_criteria"
  severity: block | warn
  message: <one-sentence finding>
  fix_hint: <optional one-sentence hint>
```

## Severity rules

### `block` — single finding triggers REJECTED

- Any missing required field (e.g. component with no `requirements`, ADR with
  no `Reversibility`).
- Spec Ambiguity Test failure (SwA would have to guess).
- ADR fails three-condition threshold (load-bearing missing, single-option,
  non-contingent).
- Orphan REQ (no `traces_to`).
- Smuggled design in a requirement.
- Compound requirement.
- Missing complementary pair when required.
- Generic rationale in ADR Context (no cited driver).
- Missing Reversibility answer.
- Ghost ADR reference (component's `governed_by_adrs` names a non-existent file).
- Asymmetric ADR ↔ component trace (one side names the other; other side doesn't).
- Circular `depends_on` in the component graph.

### `warn` — accumulates

- Glossary term used inconsistently (1× — drift, but consistent elsewhere).
- Mermaid diagram present but suboptimal.
- ADR threshold borderline (load-bearing yes, but options thin).
- NFR allocation correct but split-of-obligation could be clearer.
- Acceptance criteria measurable but verbosely worded.
- AC bullet paraphrases its handle (nfr_elements / invariant statement / DbC clause).
- Stale `traces_to` reference (roadmap capability or external constraint
  renamed; the trace looks broken but the intent is recoverable).

**Aggregation rule:** 3+ warns in one review = upgraded to REJECTED. Below 3
warns, verdict is APPROVED with `warns: <N>` printed for visibility.

## Common anti-pattern catalogue

### Requirements (Category 2) — both tiers

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Compound REQ (`A and B`)                   | block    | "REQ-NNN combines two obligations; split."                                                |
| Subjective threshold                       | block    | "REQ-NNN uses 'fast'/'scalable' without a measurable threshold."                          |
| Smuggled design                            | block    | "REQ-NNN names a specific library/algorithm; move to ARCH (exposes block) or ADR."        |
| Missing trace                              | block    | "REQ-NNN has empty traces_to; every REQ must link to a roadmap capability, external constraint, parent REQ, or ADR." |
| Missing complementary pair                 | block    | "REQ-NNN is event-driven; corresponding unwanted-behavior REQ not present."               |
| Per-statement rationale                    | block    | "REQ-NNN carries a rationale paragraph; move to an ADR."                                  |
| NFR missing element                        | block    | "NFR-NNN missing <subject\|metric\|threshold\|condition\|source>."                        |
| Functional REQ missing AC                  | block    | "REQ-NNN (functional) has no acceptance_criteria — AC is required for type=functional."   |
| Functional AC unmeasurable                 | block    | "REQ-NNN (functional) acceptance_criteria item <i> not measurable as written."            |
| AC paraphrases nfr_elements                | warn     | "REQ-NNN (nfr) AC item <i> paraphrases nfr_elements.threshold/condition; drop or replace with a non-redundant handle." |
| AC paraphrases statement (invariant)       | warn     | "REQ-NNN (invariant) AC item <i> restates the statement; drop or replace with a distinct sub-check." |
| AC paraphrases DbC clause                  | warn     | "REQ-NNN (interface) AC item <i> restates a DbC clause from exposes[<name>]; drop or replace." |
| Invariant statement not testable           | block    | "REQ-NNN (invariant) statement is not testable as written; sharpen the statement or add AC." |
| Component has zero REQs                    | block    | "Component <name> has no requirements; either declare status:support or author REQs."     |
| No depends_on field                        | warn     | "Component <name> missing depends_on; use `depends_on: []` explicitly."                   |
| Smuggled convention                        | warn     | "REQ-NNN describes code organization, not behavior — move to top-level `conventions:` block as CONV-NNN." |

### System requirements (Category 2 — tier-specific)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| SYS-REQ unallocated                        | block    | "SYS-REQ-NNN has empty allocated_to; allocate to ≥1 component or demote to component REQ." |
| SYS-REQ wrong tier (single-component)      | warn     | "SYS-REQ-NNN allocated to one component and describes no cross-component obligation; demote to that component's requirements." |
| SYS-REQ type invalid                       | block    | "SYS-REQ-NNN type must be one of functional, nfr, invariant; got '<value>'."              |
| SYS-REQ NFR missing element                | block    | "SYS-REQ-NNN (nfr) missing nfr_elements.<subject\|metric\|threshold\|condition\|source>." |
| Tier inflation                             | warn     | "system_requirements count (<N>) exceeds component count (<M>); review for Tier 2 demotion candidates." |

### Exposes / DbC (Category 2)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Interface block missing DbC field          | block    | "Interface <name> missing <field>."                                                       |
| Hidden clauses                             | block    | "Interface <name> declared demanding but contract implies defensive checks."              |
| Vague precondition                         | warn     | "Interface <name>.preconditions[i] vague — 'valid input' needs format/range."             |
| Untyped error                              | block    | "Interface <name>.typed_errors[i] missing name or when condition."                        |
| Style not chosen                           | block    | "Interface <name> missing `style` — pick demanding or tolerant."                          |

### ADRs (Category 3)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Threshold violation                        | block    | "ADR-NNN does not meet three-condition threshold: <which>."                               |
| Generic rationale                          | block    | "ADR-NNN Context cites no specific driver; lists generic benefits only."                  |
| One alternative                            | block    | "ADR-NNN Alternatives list has fewer than 2 genuine options."                             |
| Missing Reversibility                      | block    | "ADR-NNN Reversibility section missing or empty."                                         |
| Consequence one-sided                      | block    | "ADR-NNN Consequences shows only positive (or only negative); list both signs."           |
| Empty governs_components                   | block    | "ADR-NNN governs_components is empty; an accepted ADR must shape at least one component." |
| Invalid status                             | block    | "ADR-NNN status '<value>' not in {proposed, accepted, superseded, deprecated}."           |
| Asymmetric supersession                    | block    | "ADR-NNN supersedes ADR-XXX but ADR-XXX.superseded_by is not set (or names a different ADR)." |
| Threshold borderline (load-bearing, weak options) | warn | "ADR-NNN passes load-bearing but alternatives feel thin; review whether it earns the slot." |
| Convention-as-ADR                          | warn     | "ADR-NNN ratifies a one-line code rule with thin alternatives; migrate to top-level `conventions:` block as CONV-NNN (keep the ADR thin if reversal genuinely ripples)." |
| Forward-declaration ADR (accepted, no REQ trace) | warn | "ADR-NNN (status: accepted) has no REQ in its governs_components tracing back to it; either add a REQ.traces_to entry or demote to status: proposed until the code that ratifies it lands." |

### Conventions (Category 2 — top-level `conventions:` block)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Id malformed                               | block    | "CONV entry id '<value>' does not match CONV-\\d+."                                       |
| Duplicate id                               | block    | "CONV-NNN id appears more than once in conventions block."                                |
| Missing required field                     | block    | "CONV-NNN missing <rule\|rationale\|enforced_by\|applies_to>."                            |
| Invalid enforced_by                        | block    | "CONV-NNN enforced_by '<value>' not in {lint, ci-script, review, nothing}."               |
| Ghost ADR trace                            | block    | "CONV-NNN traces_to lists ADR-NNN which does not exist under paths.adrs."                 |
| Compound rule                              | warn     | "CONV-NNN combines two rules joined by 'and'; split into separate entries."               |
| Generic rationale                          | warn     | "CONV-NNN rationale gives no driver — cite past bug, maintenance pain, or architectural posture." |
| REQ paraphrase                             | warn     | "CONV-NNN.rule closely paraphrases REQ-NNN.statement; pick the right slot for one of them and delete the duplicate." |
| enforced_by: nothing                       | warn     | "CONV-NNN has enforced_by: nothing — acceptable transitionally, but give it a real handle on next iteration." |

### Cross-artifact (Category 4)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Orphan REQ                                 | block    | "REQ-NNN has empty traces_to; no upstream trace."                                         |
| Ghost ADR reference                        | block    | "Component <name>.governed_by_adrs lists ADR-NNN which does not exist under paths.adrs."  |
| Ghost component in ADR                     | block    | "ADR-NNN governs_components lists <name> which is not declared in COMPONENTS.yaml."       |
| Asymmetric ADR trace                       | block    | "ADR-NNN claims to govern <comp>, but <comp>.governed_by_adrs does not include ADR-NNN." |
| ADR cites missing REQ                      | block    | "ADR-NNN Context cites REQ-XXX which does not exist in any component's requirements."     |
| Stale roadmap trace                        | warn     | "REQ-NNN traces_to=[CAP-007] but capability CAP-007 not found in roadmap.yaml (rename? removed?)." |
| Glossary drift                             | warn     | "Term '<word>' used differently in REQ-NNN vs ADR-MMM (first as X, second as Y)."         |
| Backlog item without REQ                   | warn     | "Master backlog item <id> modifies component <comp> which has no REQs — SwA would author against nothing." |
| Ghost component in SYS-REQ                 | block    | "SYS-REQ-NNN allocated_to lists <name> which is not declared in COMPONENTS.yaml."         |
| Ghost SYS-REQ in derives_from              | block    | "REQ-NNN derives_from lists SYS-REQ-XXX which does not exist in system_requirements."     |
| SYS-REQ in traces_to                       | block    | "REQ-NNN traces_to lists SYS-REQ-XXX; move it to derives_from (allocation is the formal link)." |
| Asymmetric allocation (SYS-REQ → comp)     | block    | "SYS-REQ-NNN allocated_to includes <comp>, but no REQ in <comp> has derives_from including SYS-REQ-NNN." |
| Asymmetric allocation (comp → SYS-REQ)     | block    | "REQ-NNN derives_from SYS-REQ-XXX, but SYS-REQ-XXX.allocated_to does not include <comp>." |

### Meta (Category 6)

| Pattern                                    | Severity | Finding template                                                                          |
|--------------------------------------------|----------|-------------------------------------------------------------------------------------------|
| Spec Ambiguity                             | block    | "SwA would need to guess <X> when authoring impl contracts for <component>."              |
| Open follow-ups section                    | block    | "`## Open follow-ups` section present in <file>; use `[DEFER-ADR: ...]` markers inline."  |

## Fix-hint discipline

`fix_hint` is optional but useful. Discipline:

- Point at the field/section to change, not the rewrite. ("Move rationale to a
  new ADR" not "Rewrite as: <full text>".)
- Be specific. "Add 4th alternative" beats "consider more options".
- Don't lecture. Two sentences max.

## Finding ID convention

`F-NNN` where N is monotonic within one review. If the review is iteration 2 of
fix mode, use `F-201`, `F-202` — first digit identifies iteration (helps SA see
"the same finding came back").

## Meta-findings

If, while reviewing, the arbitrator notices that the **previous** review's
findings were unclear or contradictory (i.e. SA's fix failed because the finding
text was ambiguous), raise a `meta-finding`:

```yaml
- id: M-001
  type: meta
  message: "Previous F-XXX was ambiguous about which field to change."
  affected_finding: F-XXX
```

Meta-findings do NOT count toward block/warn aggregation. They're advisory and
signal that the arbitrator's own previous output may need refinement.
