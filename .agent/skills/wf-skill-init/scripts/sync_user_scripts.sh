#!/usr/bin/env bash
#
# sync_user_scripts.sh — Copy user-invoked scripts (and their assets) from the
# wf-skill-init source into .workflow/scripts/.
#
# The scripts copied here are intended to be invoked directly by a human, so
# they live at a predictable path under .workflow/ rather than the symlinked
# .agent/skills/wf-skill-init/scripts/.
#
# Idempotent: re-running overwrites destination copies with the current wf
# source. Run on fresh install and on patch-mode upgrades.
#
# Currently managed user scripts:
#   - render_spec_html.sh   (+ assets/architecture.{css,js,html.tmpl})
#
# Usage:
#   sync_user_scripts.sh [--workflow-dir <path>]
#       --workflow-dir defaults to ./.workflow
#
# Exit codes:
#   0 = sync completed
#   2 = configuration / IO error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SCRIPTS_DIR="$SCRIPT_DIR"
SRC_ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"

WORKFLOW_DIR="./.workflow"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workflow-dir) WORKFLOW_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# sync_user_scripts\.sh/,/^set -euo pipefail/p' "$0" | sed '$d'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ── Inventory: which files travel into .workflow/scripts/ ────────────────
USER_SCRIPTS=(
    "render_spec_html.sh"
)
USER_ASSETS=(
    "architecture.html.tmpl"
    "architecture.css"
    "architecture.js"
)

DEST_SCRIPTS_DIR="$WORKFLOW_DIR/scripts"
DEST_ASSETS_DIR="$WORKFLOW_DIR/scripts/assets"

mkdir -p "$DEST_SCRIPTS_DIR" "$DEST_ASSETS_DIR"

copied=0
skipped=0

for f in "${USER_SCRIPTS[@]}"; do
    src="$SRC_SCRIPTS_DIR/$f"
    dst="$DEST_SCRIPTS_DIR/$f"
    if [[ ! -f "$src" ]]; then
        echo "error: source missing: $src" >&2
        exit 2
    fi
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        skipped=$((skipped + 1))
        continue
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    copied=$((copied + 1))
    echo "  copied: $dst"
done

for f in "${USER_ASSETS[@]}"; do
    src="$SRC_ASSETS_DIR/$f"
    dst="$DEST_ASSETS_DIR/$f"
    if [[ ! -f "$src" ]]; then
        echo "error: source missing: $src" >&2
        exit 2
    fi
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        skipped=$((skipped + 1))
        continue
    fi
    cp "$src" "$dst"
    copied=$((copied + 1))
    echo "  copied: $dst"
done

echo "sync_user_scripts: $copied copied, $skipped already up-to-date"
