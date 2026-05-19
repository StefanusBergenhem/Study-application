---
name: wf-skill-init
description: Idempotent install wizard for the wf toolkit. Auto-detects fresh/existing/patch mode and scaffolds .workflow/, config.yaml, and gitignore entries. Owns workflow-config.yaml.tmpl. Use on first install or after a toolkit upgrade.
---

# wf-skill-init — Install Wizard

Idempotent. Detect what state the project is in, pick the mode, walk the user through checkpoints, apply the change. Re-running this skill never destroys configuration.

## Inputs

| Source | Purpose |
|:-------|:--------|
| Project root | Detection signals (language, frameworks, existing wf install) |
| `assets/workflow-config.yaml.tmpl` | Canonical config schema — single source of truth for `paths.*`, `commands.*`, and tuning sections |
| `assets/project-pi.md.tmpl` | Starter PI.md / CLAUDE.md for projects without one |
| `assets/state.md.tmpl`, `assets/conventions.md.tmpl` | Starter persistent docs |
| `assets/architecture.html.tmpl`, `assets/architecture.css`, `assets/architecture.js` | Render-time assets for the spec-layer viewer copied into `.workflow/scripts/assets/` |
| `scripts/render_spec_html.sh`, `scripts/sync_user_scripts.sh` | User-facing scripts; `sync_user_scripts.sh` copies the renderer into `.workflow/scripts/` |
| Cross-skill templates | For empty starters of artifacts owned by other skills, read from the owning skill's `assets/` (e.g., `wf-skill-continuous-learning/assets/memory.yaml.tmpl`, `wf-skill-sa/assets/components.yaml.tmpl`) |

## Mode Detection

Run this triage before anything else:

```
.workflow/ does not exist?
  ├── source code present in the project (language manifests, source dirs)?  → existing mode
  └── otherwise                                                              → fresh mode
.workflow/ exists with .workflow/config.yaml?                                → patch mode
```

If `.workflow/` exists but `config.yaml` is missing or corrupt, report and ask — do not assume.

## Wizard Behaviour (all modes)

Operate as an **interactive setup wizard**. At checkpoint steps (marked `[CHECKPOINT]`):

1. **Show what was detected or generated** — present the relevant config section or finding.
2. **Explain why it matters** — one sentence on what breaks if this is wrong.
3. **Suggest values** — if empty fields can be inferred from project analysis, propose values with reasoning.
4. **Confirm** — "Does this look right?" before proceeding.

If the user says "skip" or "auto", apply defaults silently for the rest of this run.

To avoid back-and-forth, batch related sections:

- **Batch 1** — Project identity + paths
- **Batch 2** — Commands (test, lint, type-check, coverage, db)
- **Batch 3** — Tuning (coverage thresholds, task sizing, models, review)
- **Batch 4** — External skills (per-domain)
- **Batch 5** — CI alignment warnings

---

## Fresh Mode

For a clean project that has no `.workflow/` yet.

### 1. Detect language and framework

Scan the project root:

| Manifest | Language |
|:--|:--|
| `package.json` | Node.js (check for react, next, vue, angular) |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pyproject.toml` / `requirements.txt` / `setup.py` | Python |
| `pom.xml` / `build.gradle` | Java / Kotlin |
| `*.csproj` / `*.sln` | .NET |

Record detected language and framework for use in Step 2.

### 2. Create the .workflow/ tree

```
.workflow/
  config.yaml                # Owned by this skill
  .transient/                # Per-run handoff state (gitignored)
  archive/
    retrospective/           # Owned by wf-skill-continuous-learning
  retrospective/             # Owned by wf-skill-retrospective
  adrs/                      # Owned by wf-skill-sa
```

### 3. Generate `.workflow/config.yaml` `[CHECKPOINT]`

Read `assets/workflow-config.yaml.tmpl` — it is the **canonical source of truth**. Substitute template variables (`{{VAR}}`) with detected values:

| Variable | Detection source |
|:--|:--|
| `{{PROJECT_NAME}}` | Directory name or manifest (`package.json name`, `go.mod module`) |
| `{{LANGUAGE}}` | From Step 1 |
| `{{TEST_UNIT_CMD}}` | Detected runner (e.g., `go test ./...`, `npm test`) |
| `{{TEST_INTEGRATION_CMD}}` | `""` (user fills in) |
| `{{TEST_E2E_CMD}}` | `""` |
| `{{LINT_CMD}}` | Detected linter |
| `{{TYPE_CHECK_CMD}}` | Detected type checker |
| `{{PREFLIGHT_CMD}}` | Detected or `""` |
| `{{COVERAGE_CMD}}` | Detected or `""` |
| `{{DB_VALIDATE_CMD}}` | `""` |

Walk through the file with the user in the five batches above. The template defines **every** section (paths, commands, coverage, review, parallel, models, task_sizing, learning, external_skills) — do not add or omit any.

#### Smart Suggestions for empty command fields

Scan dependency manifests for these markers and propose values:

| Detected | Field | Suggested value |
|:--|:--|:--|
| `prisma` | `db_validate` | `npx prisma migrate status` |
| `typeorm` | `db_validate` | `npx typeorm migration:show` |
| `drizzle-orm` | `db_validate` | `npx drizzle-kit check` |
| `alembic` / `sqlalchemy` | `db_validate` | `alembic check` |
| `gorm` + migration files | `db_validate` | Prompt user |
| `pg` / `mysql2` / `better-sqlite3` | `test_integration` | Prompt: "DB driver detected — set integration test command" |
| `vitest` | `coverage` | `npx vitest run --coverage` |
| `jest` | `coverage` | `npx jest --coverage` |
| `cypress` | `test_e2e` | `npx cypress run` |
| `playwright` | `test_e2e` | `npx playwright test` |

Present all suggestions together: "Based on your dependencies, I suggest these values for empty fields. Apply? You can adjust any."

### 4. Initialize transient state

Write `.workflow/.transient/pipeline_state.yaml`:

```yaml
phase: idle
active_task: null
attempt_count: 0
last_action: "Project initialized"
last_updated: <timestamp>
```

### 5. Update `.gitignore`

Append `.workflow/.transient/` if not already present. Persistent artifacts under `.workflow/` (config, retrospective, archive, MEMORY, STATE, CONVENTIONS, sprint, COMPONENTS, master_backlog, roadmap, adrs) are intended to be git-tracked; only the `.transient/` subdirectory is local-only.

### 6. Scaffold persistent starter files

Create empty starters at the paths from `paths.*` in config:

| Artifact | Source template |
|:--|:--|
| `paths.components` (default `.workflow/COMPONENTS.yaml`) | `wf-skill-sa/assets/components.yaml.tmpl` |
| `paths.master_backlog` (default `.workflow/master_backlog.yaml`) | `wf-skill-sa/assets/master-backlog.yaml.tmpl` |
| `paths.memory` (default `.workflow/MEMORY.yaml`) | `wf-skill-continuous-learning/assets/memory.yaml.tmpl` |
| `paths.state` (default `.workflow/STATE.md`) | `assets/state.md.tmpl` |
| `paths.conventions` (default `.workflow/CONVENTIONS.md`) | `assets/conventions.md.tmpl` |
| `paths.adrs` (default `.workflow/adrs`) | (empty directory; ADRs come from `wf-skill-sa`) |

### 6b. Sync user-facing scripts into `.workflow/scripts/`

User-invoked scripts and their render-time assets live at a predictable path
under `.workflow/` rather than under the symlinked skill tree, so end-users
type `./.workflow/scripts/<name>.sh` without thinking about the install layout.

Run the helper bundled with this skill:

```bash
bash scripts/sync_user_scripts.sh
```

It populates:

| Destination | Source |
|:--|:--|
| `.workflow/scripts/render_spec_html.sh` | `scripts/render_spec_html.sh` |
| `.workflow/scripts/assets/architecture.html.tmpl` | `assets/architecture.html.tmpl` |
| `.workflow/scripts/assets/architecture.css` | `assets/architecture.css` |
| `.workflow/scripts/assets/architecture.js` | `assets/architecture.js` |

The output of `render_spec_html.sh` defaults to `paths.architecture_html`
(`.workflow/.transient/architecture.html` by default — gitignored). Override
in config to commit the rendered doc (e.g. `doc/architecture.html`).

### 7. Generate starter CLAUDE.md / PI.md (if none exists)

If no `CLAUDE.md` or `PI.md` exists at the project root, create one from `assets/project-pi.md.tmpl`. If `CLAUDE.md` or `PI.md` already exists, do **not** overwrite — report and suggest the user review.

### 8. Create `.agent/skills/` and `.agent/agents/`

Create `.agent/skills/` and `.agent/agents/` if missing. Project-local overrides land here; install.sh symlinks the wf toolkit's skills and agents into them.

### 9. Domains Detection `[CHECKPOINT]`

Pre-populate the top-level `domains:` section from language detection. Check `~/.agent/skills/` for installed skills and only reference ones that actually exist.

**Multi-language projects** (e.g., both `go.mod` and `package.json`): create one entry under `domains:` per language. Scan the project tree for language-specific directories (e.g., `cmd/`, `internal/`, `pkg/` for Go; `src/`, `frontend/`, `app/` for TypeScript). For each domain, suggest a `conventions:` path if a single conventions document is discoverable under its `match` tree (e.g., `<domain-root>/CONVENTIONS.md`); otherwise leave the slot absent so the project-wide `paths.conventions` applies.

**Single-language projects:** `domains:` may be left empty; `external_skills.defaults` and top-level `commands`/`paths.conventions` cover everything.

#### Auto-populate domain commands (multi-language only)

For each non-primary domain, add a `commands:` section with the keys that **differ** from top-level. Reference:

| Language | test_unit | lint | type_check | test_integration | coverage |
|:--|:--|:--|:--|:--|:--|
| Go | `go test ./...` | `golangci-lint run` | — | `go test -tags=integration ./...` | `go test -coverprofile=coverage.out ./...` |
| TypeScript | `npx vitest run` or `npm test` | `npx eslint .` | `tsc --noEmit` | — | `npx vitest run --coverage` |
| Python | `pytest` | `ruff check .` | `mypy .` | — | `pytest --cov` |
| Rust | `cargo test` | `cargo clippy` | — | — | — |

Skip domain `commands` entirely if the domain matches the primary language.

### 10. CI Alignment Check `[CHECKPOINT]`

Warn on common gaps:

- `commands.test_integration` empty + external dependencies detected (DB drivers, HTTP clients, queues, caches) → elevated warning: "Tasks with external dependencies will create integration test files the pipeline can't execute. Configure `commands.test_integration`."
- `commands.test_e2e` empty → "User-facing flows will produce e2e files that can't run."
- `commands.coverage` empty → "Pipeline can't enforce coverage thresholds."
- `commands.db_validate` empty + database detected → "Configure to catch stale migrations."

Re-offer Smart Suggestions for each gap that has one. Apply confirmed values.

### 11. Final report `[CHECKPOINT]`

Present a one-screen config summary, ask for last adjustments, then print:

```
Setup complete.

Next steps:
  /wf-skill-strategist     — Create the product roadmap
  /wf-skill-sa             — Define components, ADRs, master backlog
  /wf-skill-swa            — Detail the first sprint
  /wf-skill-orchestrate    — Execute the sprint
  /wf-skill-ship           — Validate and push when done
```

---

## Existing Mode

For projects with substantial existing source. Performs every fresh-mode step **plus**:

### E1 — Spawn parallel exploration sub-agents (up to 3)

Run concurrently:

- **Structure mapper** — directory tree, top-level modules/packages, import / dependency relationships → dependency graph.
- **Responsibility analyzer** — for each module, read entry points and main exports, summarise responsibility; flag overlap.
- **Size & complexity profiler** — file counts per module, exported-symbol counts, large files (>300 lines), high fan-in/fan-out modules.

### E2 — Draft starter `COMPONENTS.yaml`

Produce a skeleton at `paths.components`:

- One component per discovered module / package.
- `depends_on` derived from the import graph.
- `exposes` as plain symbol names (DbC blocks come later from the SA).
- `constraints` defaulted (max 20 files, max 15 exports) — flag if already exceeded.
- `requirements: []` — left empty; the SA authors EARS requirements in the first SA session.
- `governed_by_adrs: []` — left empty; populated as ADRs are authored.

**Existing mode does NOT author requirements or ADRs.** Spec-layer authoring is interactive SA work. This step sketches the skeleton from code analysis only.

### E3 — Component boundary review `[CHECKPOINT]`

Present components as a table:

| Component | Files | Exports | Depends On | Path | Status |
|:--|:--|:--|:--|:--|:--|

For each:

- **Constraint violations** — "Component `api` has 34 files (limit 20) and 22 exports (limit 15). Split into `api-routes` + `api-middleware`?"
- **Circular dependencies** — "Components `auth` and `users` depend on each other. Common fix: make `users` depend on `auth`, not the reverse."
- **Overlapping responsibilities** — "`utils` and `helpers` both hold string formatting. Merge?"

Apply user feedback before writing the final `COMPONENTS.yaml`.

### E4 — Architecture audit checklist

Write `architecture_audit.md` at the project root with:

- Component health table (counts vs limits).
- Separation of concerns issues with suggested splits.
- Dependency direction violations.
- Duplication concerns.
- Prioritised action items.

This checklist is the input for the first `/wf-skill-sa` session.

### E5 — Update config and report `[CHECKPOINT]`

- Update `.workflow/config.yaml` with component and audit paths if needed.
- Prioritise audit findings interactively: which go into the first sprint, which to deprioritise, which to add manually.
- Record priorities as `[P0]` / `[P1]` / `[SKIP]` annotations in `architecture_audit.md`.
- Print summary and next steps.

---

## Patch Mode

For projects already on wf that need upgrading after a toolkit update. **Non-destructive**:

- Never overwrites existing config values — only adds missing sections.
- Preserves user customisations (commands, paths, tuning).
- File renames create the new file first, remove the old only after confirming the new exists.
- Pipeline state is touched only if stuck on a deprecated phase.
- Reports all findings before applying.

### P1 — Scan existing structure

Read (skip absent files):

- `.workflow/config.yaml` — parse current `version`, check sections present, check `paths.*` entries.
- `.workflow/.transient/pipeline_state.yaml` (or legacy `.workflow/pipeline_state.yaml`) — read current `phase`.
- `docs/MEMORY.md` and `.workflow/MEMORY.yaml` — check formats.
- `.gitignore` — check entries.
- Directories: `.workflow/.transient/`, `.workflow/retrospective/`, `.workflow/archive/retrospective/`, `.workflow/adrs/`.

Then run the bundled consistency script — forward + reverse `paths.*` drift between the project's `config.yaml` and the installed skills/agents:

```bash
bash scripts/check_config_consistency.sh > /tmp/wf-init-consistency.log 2>&1 || true
```

The script never gates patch mode. Any `DEAD` (template field with zero consumers) or `UNKNOWN` (referenced field missing from the template) lines surface in the P3 report alongside the migration findings.

### P2 — Run migration checks

For each check: evaluate the detection condition, record `OK` or `NEEDS_MIGRATION`, note the action.

#### Check 1 — Config version

- **Detect:** `version` missing or below current template version.
- **Action:** Update `version` to match template.

#### Check 2 — Memory file format

- **Detect:** `paths.memory` points to `.md`, OR `docs/MEMORY.md` exists without `.yaml` counterpart.
- **Action:** If `.md` has content, convert to YAML using `wf-skill-continuous-learning/assets/memory.yaml.tmpl` schema (`version`, `max_entries`, `lessons: []`); map extracted content into entries. Write to the new `paths.memory`. Keep `.md` as backup.

#### Check 3 — Missing path entries

- **Detect:** any `paths.<key>` from `assets/workflow-config.yaml.tmpl` is missing from the user's config.
- **Action:** Add each missing key with the template default. Never overwrite existing values.

#### Check 4 — Legacy transient paths

- **Detect:** `paths.*` for transient artifacts point at `.workflow/<name>.yaml` instead of `.workflow/.transient/<name>.yaml`. Applies to: `pipeline_state`, `stage_manifest`, `current_task`, `review_ready`, `feedback`, `build_progress`, `build_blocked`, `design_issues`, `arbitrator_feedback`, `arbitrator_escalation`.
- **Action:** Move the file (if it exists) into `.workflow/.transient/`, update the config path. Add `.workflow/.transient/` to `.gitignore`.

#### Check 5 — ADR path shape (directory, not glob)

- **Detect:** legacy `architecture_docs` (glob list) or `architecture` (single string) key under `paths:`, OR `paths.adrs` is missing.
- **Action:** Replace with `adrs: ".workflow/adrs"` (or `"docs/adrs"` if the project explicitly routes spec layer to `docs/`). Migrate any pre-existing ADR files. Remove the legacy field.

#### Check 6 — Models section

- **Detect:** no `models:` section.
- **Action:** Append the `models:` block from `assets/workflow-config.yaml.tmpl`.

#### Check 7 — Learning section

- **Detect:** no `learning:` section.
- **Action:** Append from template.

#### Check 8 — Obsolete observability config

- **Detect:** `observability:` section present, OR `paths.metrics_dir` / `paths.archive_metrics` present, OR `learning.archive_metrics` key present. (Observability was removed from the toolkit.)
- **Action:** Remove the `observability:` section, the two `paths.*` entries, and the `learning.archive_metrics` line. If `.workflow/metrics/` or `.workflow/archive/metrics/` directories exist and are empty, remove them; if they contain files, leave them and report — the user may want to keep the historical data.

#### Check 9 — Missing directories

- **Detect:** any of these missing: `.workflow/.transient/`, `.workflow/retrospective/`, `.workflow/archive/retrospective/`, `.workflow/adrs/`.
- **Action:** Create them.

#### Check 10 — Gitignore gaps

- **Detect:** `.workflow/.transient/` not listed.
- **Action:** Append.

#### Check 11 — Stale pipeline phase

- **Detect:** `pipeline_state.yaml` has a deprecated phase (e.g., `awaiting_stage_approval`).
- **Action:** Set `phase: idle`, `last_action: "Migrated from deprecated <phase>"`.

#### Check 12 — Missing MEMORY.yaml

- **Detect:** neither `.md` nor `.yaml` exists at `paths.memory`.
- **Action:** Scaffold from `wf-skill-continuous-learning/assets/memory.yaml.tmpl`.

#### Check 13 — Deprecated per-module ARCHITECTURE.md

- **Detect:** any `**/ARCHITECTURE.md` exists (excluding `node_modules`, `.git`, vendored dirs).
- **Action:** Warn and list. Per-module ARCHITECTURE.md is superseded by `summary` fields in `COMPONENTS.yaml`. Do not auto-delete.

#### Check 14 — Missing or outdated external_skills + domains

- **Detect:** any of:
  1. No `external_skills:` section.
  2. Uses the old flat format (keys like `implementation` directly under `external_skills` instead of under `defaults`).
  3. `external_skills.domains` exists (the pre-v4 location for domain config; in v4+ `domains:` is a top-level section).
- **Action:**
  - Missing → append `external_skills.defaults` + an empty top-level `domains:` from template.
  - Old flat → migrate values into `external_skills.defaults` (wrap scalars as lists).
  - **v3 → v4 migration:** move the contents of `external_skills.domains.*` to top-level `domains:`. Preserve `match`, `skills`, and `commands` fields verbatim. Report the move.
  - For each domain without `commands` → infer domain language from `match` globs, compare against top-level commands, suggest a `commands` block for keys that differ. Skip domains matching the primary language.

#### Check 14a — Conventions: legacy list shape and missing domain conventions

- **Detect:** any of:
  1. `paths.conventions` is a list (legacy multi-lang workaround; v4 declares conventions per domain).
  2. `domains.<name>` exists with no `conventions:` field, AND the project has more than one conventions document on disk that matches the domain's `match` globs.
- **Action:**
  - List-shaped `paths.conventions` → keep the first entry as `paths.conventions` (project-wide default). For each remaining entry, find the domain whose `match` globs cover that file's directory tree and move the entry into `domains.<name>.conventions`. If no domain matches, report it for the user to assign.
  - Missing per-domain `conventions:` → if a single conventions file is discoverable under the domain's `match` tree (e.g., `<domain-root>/CONVENTIONS.md`), suggest it; otherwise leave the slot absent (project-wide default applies).

#### Check 15 — Missing task_sizing

- **Detect:** no `task_sizing:` section.
- **Action:** Append from template.

#### Check 16 — Missing or incomplete coverage

- **Detect:** no `coverage:` section, or missing `enforce_on_modified_files` / `integration_test_ratio`.
- **Action:** Append missing section or add missing fields from template.

#### Check 17 — Missing scaffolded files

- **Detect:** any of `paths.state`, `paths.conventions`, `paths.adrs` directory missing on disk.
- **Action:** Create from this skill's `assets/state.md.tmpl`, `assets/conventions.md.tmpl`; create the `adrs/` directory.

#### Check 18 — Dead config fields

- **Detect:** known-deprecated keys (`commands.compile_check`, `commands.context_map`, `parallel.merge_strategy`).
- **Action:** Warn — do not auto-remove (the user may have custom tooling).

#### Check 19 — Unknown config fields

- **Detect:** parse all dot-paths in the user config and in `assets/workflow-config.yaml.tmpl` (treat `{{VAR}}` as valid leaf). Compute user-paths minus template-paths. Exclude paths under `domains.` (user-defined domain names).
- **Action:** For each unknown field, suggest the closest template field by:
  1. Same section + substring overlap.
  2. Same leaf name in different section.
  3. Prefix / suffix match.
  4. Otherwise "No close match".

  Present interactively (rename / move / remove / keep). Do **not** auto-apply.

#### Check 20 — Missing source_globs / drift-detector config

- **Detect:** `source_globs:` absent, or `commands.scan_components` / `commands.scan_components_timeout` absent.
- **Action:** Append from template. `source_globs` defaults to `[]` (orphan + oversized checks skipped until set; path checks still run). `commands.scan_components` defaults to `""` (hook disabled). Do **not** auto-populate `source_globs` — the SA prompts the user for them.

#### Check 21 — Legacy TARGET_ARCHITECTURE.md

- **Detect:** a `target_architecture` key exists under `paths:` in config, OR a `TARGET_ARCHITECTURE.md` exists at the project root or at the configured path.
- **Action:** Warn: "TARGET_ARCHITECTURE.md has been retired. Its decisions migrate to per-decision files under `paths.adrs`; its architecture detail migrates into `paths.components` (as structured requirements + exposes). Run `/wf-skill-sa` to author the migration, then remove the file manually." Remove the `target_architecture` entry under `paths:` from config.

#### Check 22 — Legacy commands directory

- **Detect:** project-local `.agent/commands/wf-command-*.md` symlinks or files exist.
- **Action:** Slash commands are deprecated. Skills are invoked directly. Re-run `install.sh` (or the new equivalent in the upgraded toolkit) to clean stale command symlinks.

#### Check 23 — User-facing scripts in `.workflow/scripts/`

- **Detect:** either (a) `.workflow/scripts/render_spec_html.sh` is missing, or (b) it exists but differs from the wf-source version under this skill's `scripts/render_spec_html.sh` (likewise for the `assets/architecture.*` siblings under `.workflow/scripts/assets/`). Also detect missing `paths.architecture_html` in config.
- **Action:** Run `bash scripts/sync_user_scripts.sh` to refresh the copies (idempotent — re-overwrites stale files only). If `paths.architecture_html` is missing from config, append it with the template default (`.workflow/.transient/architecture.html`).

### P3 — Report and apply `[CHECKPOINT]`

Print the migration report (one line per check: number, name, status, action). Walk through each newly added config section in a checkpoint:

- Show the section content.
- Explain in one sentence what it controls.
- Ask: "Accept defaults, or adjust?"

After all sections walked, apply confirmed migrations.

### P4 — Verify and summarise `[CHECKPOINT]`

Re-scan to confirm everything is now current. Print final status. Optionally offer a full config walkthrough section-by-section to surface improvements.

```
Migration complete. Applied N changes.

Next steps:
  - Review .workflow/config.yaml — new sections added with defaults, customise as needed
  - Run install.sh to refresh skill / agent symlinks
  - /wf-skill-status to verify pipeline state
```

---

## Hard Constraints

- **Idempotent.** Re-running any mode must not destroy state.
- **Non-destructive in patch mode.** Never overwrite existing config values. Only add missing sections or fields.
- **Single source of truth for config.** All `paths.*` defaults come from `assets/workflow-config.yaml.tmpl`. No defaults embedded inline in this skill's body.
- **Cross-skill template reads are allowed.** When scaffolding empty starters for artifacts owned by other skills, read from their `assets/` (e.g., `wf-skill-sa/assets/components.yaml.tmpl`).
- **No commands left behind.** If a project still has `.agent/commands/wf-command-*` symlinks, surface the deprecation in patch mode and direct the user to re-run `install.sh`.
