---
id: ADR-003
status: accepted
date: "2026-05-19"
title: "Spaced repetition algorithm — SM-2 with FSRS migration path"
governs_components: [libraries, study]
supersedes: null
superseded_by: null
traces_to: [CAP-001]
---

# Spaced repetition algorithm — SM-2 with FSRS migration path

## Context

CAP-001 requires a spaced repetition study loop with four recall ratings
(again/hard/good/easy). The algorithm must compute review intervals that
optimize long-term retention. The user suggested SM-2 as a starting point
but left the final choice to the SA. The algorithm lives entirely within
the study component.

## Decision

Implement SM-2 (SuperMemo 2) as the initial SR algorithm, with the SRState
data model carrying an `algorithm_version` field to enable migration to FSRS
(Free Spaced Repetition Scheduler) without data loss.

## Alternatives

- **SM-2 (chosen)** — Simple algorithm (~50 lines): ease factor × interval, with
  adjustments per rating. Well-understood by the SRS community, abundant
  open-source implementations, trivial to verify by hand. Four ratings map
  directly. Accuracy is lower than FSRS for long-term retention prediction,
  especially at high repetition counts. Runs in O(1) per review — zero CPU
  concern on Railway Hobby.

- **FSRS** — State-of-the-art algorithm based on the three-component model
  (stability, difficulty, retrievability). Significantly more accurate at
  predicting recall probability and scheduling reviews. Requires a parameter
  optimization pass over the user's review history (non-trivial CPU cost on
  Railway Hobby) and a more complex state model. Harder to hand-verify scheduling
  decisions. Open-source implementations exist but are newer and less battle-tested.

- **Leitner system** — Physical-box metaphor: move cards between boxes on
  correct/incorrect. Dead simple to implement and explain. But does not scale
  to hundreds of cards; lacks data-driven interval computation; no support for
  nuanced ratings (binary correct/incorrect only). Not suitable for the product's
  core value proposition.

## Consequences

### Positive

- SM-2 is trivial to implement and test — the study component can ship quickly.
- Four ratings map naturally to SM-2's quality scale (0-5).
- `algorithm_version` field future-proofs the data model — FSRS migration is a
  version bump + new computation function, not a schema migration.
- Users familiar with Anki will recognize the 4-button interface.

### Negative

- SM-2's accuracy ceiling is lower than FSRS. Power users with large decks may
  see suboptimal scheduling at high repetition counts.
- No per-user parameter tuning — SM-2 uses fixed formulas, while FSRS adapts to
  individual memory curves.
- Migration to FSRS requires running parameter optimization on historical review
  data, which could be CPU-intensive on Railway Hobby.

## Reversibility

To reverse: implement FSRS as `algorithm_version: "fsrs-v1"`, write a migration
function that reads existing SM-2 review history and computes initial FSRS
parameters. The SRState schema already carries `algorithm_version` and
`review_history` — no schema change needed. Estimated cost: 1-2 weeks for
implementation + testing + migration.
