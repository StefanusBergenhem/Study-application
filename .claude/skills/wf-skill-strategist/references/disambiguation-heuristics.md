# Disambiguation Heuristics

Bucket every user-input item into exactly one of five categories: **real need / veiled design / goal / unrealistic / out-of-scope**. Hold the bucket call internally while taking input; surface it during readback (Phase 4) so the user can affirm or reframe.

## Bucket 1 — Real need

A real need is an underlying problem or capability statement that does NOT pre-commit to an implementation approach.

**Tests:**

- Could three different technologies plausibly satisfy this?
- Is the user describing a problem they have, not a solution they want?
- Strip technology nouns from the statement — does the remaining sentence still make sense as a thing they need?

Examples (real needs):

- "Users need to find their past orders quickly."
- "Field engineers can't access the system without internet."
- "We need an audit trail of who changed what and when."

Each admits multiple implementations. Each becomes a candidate CAP-NNN.

## Bucket 2 — Veiled design

A stated preference that's really a HOW pretending to be a WHAT. User names a specific technology, library, framework, pattern, or implementation detail.

**Tests:**

- Is there a brand name, library name, or specific technical pattern in the statement?
- Is the verb "use" or "have" followed by a technology noun? ("We need to use Redis" = veiled design.)
- Could you write a competing implementation that's better but couldn't be described this way? Then this is design, not need.

Examples (veiled design and their translations):

| Stated | Underlying need |
|---|---|
| "Use Redis" | Fast lookups under load X / pub-sub at fan-out N / cache invalidation pattern Y |
| "Make it a web app" | Cross-platform access without per-user install |
| "Use OAuth" | Third-party identity integration; no in-house auth |
| "Add an API" | Programmatic access for use case X |
| "Microservices architecture" | Independent team velocity / per-component deployment / specific scale shape |
| "Server-side rendering" | First-paint performance / SEO / specific accessibility requirement |

**Handling:** translate, then ask the user to confirm the translation during readback. If they insist on the specific technology AND the insistence is backed by a binding external mandate, treat as an **external constraint** (see below) — captured in `external_constraints`, not in `capabilities`.

### When veiled design is a legitimate external constraint

Sometimes the user really does have a binding mandate from outside the design process that they happen to express as a technology choice:

- "Use OAuth" — because the company's identity provider only supports OAuth.
- "Java only" — because the deployment platform mandates it.
- "PostgreSQL" — because the DBA team only supports it.
- "Must run on-prem" — because of regulatory data-residency.

These are **external constraints**: non-negotiable inputs from outside the design process, with no genuine alternatives. They live in `external_constraints` with a one-line `reason` and a `source`.

**Ownership boundary:** the strategist captures user-stated external constraints; it does NOT make architectural commitments. SA reads `external_constraints` and converts each entry into a `type: inherited-constraint` REQ in `COMPONENTS.yaml`, with `traces_to: [EXT-NNN]` pointing back to the strategist's entry. SA owns ADRs, conventions, and the actual architectural shape — the strategist just relays the user's mandates upstream.

## Bucket 3 — Goal

A high-level "what" without enough detail to act on. Vague verbs ("improve", "enable", "streamline") without measurable success criteria.

**Tests:**

- Could you fail to deliver this while still having shipped something?
- Is the verb a generic improvement verb (improve, enhance, optimize, streamline)?
- Is success defined? If not, this is a goal that needs decomposition.

Examples:

- "Improve user engagement."
- "Make the dashboard better."
- "Streamline the onboarding flow."

**Handling:** decompose into testable sub-capabilities, each of which becomes a CAP-NNN candidate. Brainstorming (see `brainstorm-patterns.md`) is the right tool — offer 2–4 concrete sub-capabilities via `AskUserQuestion` and let the user pick. If decomposition isn't possible in this session, mark as an `open_questions` entry rather than authoring a vague capability.

## Bucket 4 — Unrealistic as stated

Items that, as stated, aren't achievable. Three common failure modes:

### 4a — Impossible thresholds

"100% accurate", "zero downtime", "no latency", "infinite scale", "free".

**Handling:** propose a realistic threshold + acceptable failure mode in readback. Get the user's agreement on the reframe.

### 4b — Impossible timelines

"Done in 2 weeks" for what's plainly 6 months of work.

**Handling:** name an estimate range. Offer to ship a smaller useful slice in the user's timeline if possible. Get agreement on scoping.

### 4c — Mutually contradictory asks

"Cheap to operate" + "five-9s availability" + "globally distributed" — pick at most two; one will give. Or: "fast to ship" + "high quality".

**Handling:** surface the contradiction explicitly in readback. Make the user pick or explicitly accept the trade-off. Don't silently optimise one over the other.

### Important: don't dismiss

Unrealistic asks usually point at a real underlying need ("free" probably means "the budget is X"; "100% accurate" probably means "errors X and Y are unacceptable"). Reframe to capture the real need; don't drop the input.

## Bucket 5 — Out of scope

Things the user explicitly does NOT want. Or things you propose that they explicitly reject.

**Handling:** keep in the `out_of_scope` section of the artifact. Surfacing what's explicitly out is as valuable as listing what's in. Scope creep is the default failure mode without this section.

## Edge case: user asks for "AI" or "ML"

This is almost always veiled design or unrealistic, but it's worth a separate note because it appears often.

**Translation prompts:**

- "Use AI to do X" → "What's the underlying decision X automates? What's the cost of getting it wrong?"
- "AI-powered recommendations" → "What inputs are available? What's the success metric? How is feedback collected?"

If the underlying need is genuinely something only ML can solve well (e.g. "translate language Y to language Z"), the ML capability becomes a CAP-NNN in capability-voice ("user can translate text between language Y and Z"). The fact that it's ML is an architectural decision for SA, not a strategist commitment — do not put "use ML" in `external_constraints` unless there's a genuine external mandate (e.g. compliance requires explainable ML).

## Internal working notation

Hold the bucket call in your head during intake — do not write a transient file. The conversation transcript and the readback step are the record. During readback (Phase 4), surface each item via `AskUserQuestion` with the bucket as `header`:

| Bucket | `header` (≤12 chars) |
|---|---|
| Real need | `Real need` |
| Veiled design | `Design read` |
| External constraint | `Ext constraint` |
| Unrealistic as-stated | `Unrealistic` |
| Out of scope | `Out of scope` |
| Open question | `Open Q` |

The user affirms or reframes. Affirmed entries become artifact content per Phase 5.
