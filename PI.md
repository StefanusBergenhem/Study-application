# Study-application

A greenfield study application. Started with the wf toolkit for structured, skill-driven development.

---

## Workflow Integration

This project uses the wf toolkit (skills-based workflow for pi).

### Skills

- `/wf-skill-init` — install / upgrade the wf toolkit (idempotent: fresh / existing / patch).
- `/wf-skill-strategist` — author the product roadmap.
- `/wf-skill-sa` — maintain the spec layer (COMPONENTS.yaml + ADRs + master backlog).
- `/wf-skill-swa` — extract per-task contracts for the next sprint into `sprint.yaml`.
- `/wf-skill-orchestrate` — run the full build / review / retrospective pipeline.
- `/wf-skill-ship` — full validation + push + PR.
- `/wf-skill-status` — read-only inspector for pipeline state.

See `wf/docs/wf-architecture.html` for the full skill / agent / artifact map.

### State Directory

The `.workflow/` directory contains all workflow state:

- `.workflow/config.yaml` — project configuration (commands, paths, tuning).
- `.workflow/.transient/` — per-run handoff state (current_task, review_ready, feedback, pipeline_state, etc.). Gitignored.
- Persistent artifacts (`COMPONENTS.yaml`, `master_backlog.yaml`, `sprint.yaml`, `MEMORY.yaml`, `STATE.md`, `CONVENTIONS.md`, `adrs/`, `retrospective/`) — git-tracked unless the project routes them elsewhere via `paths.*`.

Do not edit `.workflow/.transient/*` manually unless you understand the pipeline state machine.

---

## Project Structure

<!-- Describe your project's directory layout here -->

```
Study-application/
├── .agent/          # Agent skills and configuration
├── .pi/             # Pi agent settings
├── .workflow/       # Workflow toolkit state
├── LICENSE          # Apache 2.0
└── PI.md            # This file
```

---

## Testing

### Commands

- **Unit tests:** (not configured)
- **Integration tests:** (not configured)
- **End-to-end tests:** (not configured)
- **Lint:** (not configured)
- **Type check:** (not configured)
- **Preflight (all checks):** (not configured)

### Testing Standards

- All new code must have tests written BEFORE implementation (TDD: red -> green -> refactor).
- Unit tests use no external dependencies (no DB, no network, no filesystem).
- Integration tests use real dependencies and are tagged appropriately.
- Every `if/else`, `switch`, and error path must have a dedicated test case.
- Happy-path-only coverage is insufficient.

---

## Conventions

### Code Style

<!-- Define your project's code style rules here -->

- Follow the conventions of the language chosen for this project.

### Commit Messages

<!-- Define your commit message format here -->

### Branch Naming

<!-- Define your branch naming convention here -->

---

## Architecture

See `COMPONENTS.yaml` (at `paths.components`) for the component registry — boundaries, EARS requirements, DbC exposes, governed_by_adrs traces.