# Brainstorm Patterns

When the user's input has obvious gaps, a vague verb is dangling, or you can offer concrete alternatives they may not have considered, propose 2–4 candidate capabilities via `AskUserQuestion` and let the user pick, override, or write their own.

## The boundary

Brainstorming surfaces ideas as **user-capability statements** (candidate CAP-NNN entries), never as components, scopes, technology choices, or architectural decisions.

| Surface as a CAP-NNN candidate | Out of scope for brainstorming |
|---|---|
| "User can search across order history." | "You'll need Elasticsearch for full-text search." |
| "Admins can view who changed what, when." | "You'll want an audit-log microservice." |
| "Operator gets paged on a failed payment retry." | "Use PagerDuty for paging." |

Architectural decomposition is not the strategist's job. The job is to help the user articulate every capability they want; what those decompose into is decided downstream by SA.

## When to brainstorm

Trigger whenever any of these surface during conversation:

### 1. Vague improvement verb

User says "improve X", "streamline X", "make X better" without specifics.
→ Brainstorm 2–4 concrete capabilities that "improve X" might mean.

### 2. Missing coverage of an obvious category

User describes the happy path but not error handling. Or the read flow but not the write flow. Or features but not observability. Or visible UI but not admin ops.
→ Brainstorm 1–3 likely-missing capabilities in the underspecified category.

### 3. Single-noun product mention

User says "build a dashboard" with no detail about what's on it.
→ Brainstorm 2–3 specific capabilities the dashboard might have.

### 4. Common adjacency

A product class usually implies certain capabilities — auth, observability, admin, audit, backup, error reporting. If the user named the product class and did not mention these, they may have assumed them implicitly.
→ Brainstorm 2–3 likely-implicit capabilities.

### 5. User asks "what should I add?"

Explicit invitation. Surface 2–4 candidates based on what's already in the artifact, what similar products typically have, or gaps you noticed during intake.

## How to brainstorm

Use `AskUserQuestion` with 2–4 options. Each option is a concrete proposed capability in user-voice. The tool's auto-added 'Other' lets the user override or write their own.

Question shape:

```
question: "<one-line frame for why you're asking>"
header:   "Brainstorm"
multiSelect: true
options:
  - label: "<≤5 words>"
    description: "<one-line user-voice statement of what this means>"
  - ...
```

Worked example:

```
question: "For 'improve dashboard', here are some candidates — which apply?"
header:   "Brainstorm"
multiSelect: true
options:
  - label: "Surface unresolved first"
    description: "Dashboard puts unresolved errors at the top, most recent first."
  - label: "30-day revenue trend"
    description: "Chart showing last 30 days of revenue with day-over-day delta."
  - label: "Top 5 errors today"
    description: "List of the 5 most frequent error types in the past 24h."
  - label: "User retention panel"
    description: "Active-user count + week-over-week retention curve."
```

`multiSelect: true` is usually right — users typically want several. Use single-select only when options are mutually exclusive (e.g. one of N versions of the same feature).

## How many to brainstorm at once

- **2–4 options per `AskUserQuestion` call** (the tool's cap).
- **At most 1–2 brainstorm rounds in a row.** If you want a third round, the user's input is too vague to brainstorm against — ask directly: "What problem are we trying to solve here? Help me anchor."

## What NOT to brainstorm

- **Architecture, components, technology.** Not the strategist's lane.
- **Implementation details or acceptance thresholds.** Those land in formal requirements downstream, not in capabilities here.
- **Wholesale new products.** Stay inside the user's stated scope. Building a dashboard does not mean proposing a mobile app.
- **Aesthetic / UI-detail preferences.** "Blue button vs green button" is too low-level for strategy.

## Anti-patterns

- **Filling silence.** Do not brainstorm because the user paused. Brainstorm because there's a gap.
- **Overwhelming.** Two consecutive `AskUserQuestion` calls full of options is cognitive overload. Surface, wait for the user to integrate, then maybe ask again.
- **Padding the artifact.** Do not propose capabilities just to make `capabilities:` longer. The smallest worthwhile slice should stay small.
- **Asserting brainstormed items as facts.** "You'll want X" is presumptuous. Phrase as "Have you considered X?" or offer via `AskUserQuestion` options.
- **Brainstorming in component-voice.** "You'll need an admin panel" pre-empts architecture. Reshape as: "Admins can do A, B, C — relevant?"
