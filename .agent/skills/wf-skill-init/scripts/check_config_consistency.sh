#!/usr/bin/env bash
# check_config_consistency.sh — Forward + reverse config ↔ skill consistency check.
#
# Owned by: wf-skill-init (it's the steward of workflow-config.yaml.tmpl).
# Invoked by: wf-skill-init during patch mode; can also be run standalone.
#
# Usage:
#   ./check_config_consistency.sh [wf_root]
#
# Default wf_root: two levels up from this script (i.e., the wf/ directory).
#
# What it checks:
#   1. FORWARD — every paths.<key> in workflow-config.yaml.tmpl is referenced
#      somewhere in skills/ or agents/. Any field with zero consumers is flagged.
#   2. REVERSE — every paths.<key> referenced in skills/ or agents/ exists in the
#      template. Any unknown reference is flagged.
#
# Exit status:
#   0 — clean (no drift).
#   1 — drift found (details printed).
#
# This is the mechanical version of the "Config ↔ skill consistency" section in
# wf/README.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_ROOT="${1:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
TEMPLATE="$WF_ROOT/skills/wf-skill-init/assets/workflow-config.yaml.tmpl"

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: config template not found at $TEMPLATE" >&2
    exit 2
fi

# Extract paths.<key> entries declared in the template.
declare -A declared
while IFS=: read -r key _; do
    key="${key// /}"
    [ -z "$key" ] && continue
    declared["$key"]=1
done < <(awk '
    /^paths:/ { in_paths = 1; next }
    /^[a-z_]+:/ && !/^paths:/ { in_paths = 0 }
    in_paths && /^  [a-z_]+:/ { sub(":.*$", ""); sub(/^  /, ""); print $0 ":" }
' "$TEMPLATE")

# Extract paths.<key> references from skills/ and agents/.
#
# Scripts under <skill>/scripts/ are first-class consumers of paths.*
# (README rule 6 — scripts live with the skill that uses them). Excluding
# the whole scripts/ tree would undercount legitimate consumers and surface
# spurious DEAD findings. Exclude only this script itself.
declare -A referenced
while IFS= read -r match; do
    key="${match#paths.}"
    referenced["$key"]=1
# PCRE with negative lookahead: deny `(` (Python method calls like
# `paths.get(...)`) AND deny `[a-z_]` (so the greedy match doesn't back
# off to a shorter substring just to satisfy the lookahead — e.g.,
# `paths.items(` must not produce a `paths.item` match).
done < <(grep -rhoP --exclude="check_config_consistency.sh" 'paths\.[a-z_]+(?![a-z_(])' "$WF_ROOT/skills" "$WF_ROOT/agents" 2>/dev/null | sort -u)

# Build the deprecation allowlist from wf-skill-init/SKILL.md migration
# checks. Patch-mode `Detect:` lines legitimately name removed paths.* fields
# so the wizard can find and offer to clear them; those mentions are
# deprecation prose, not real consumers. Subtract them from the reverse
# check so they don't surface as UNKNOWN.
declare -A deprecated
init_skill="$WF_ROOT/skills/wf-skill-init/SKILL.md"
if [ -f "$init_skill" ]; then
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        deprecated["$key"]=1
    done < <(awk '
        /^#### Check [0-9]+/ { in_check = 1; next }
        /^#### / && !/^#### Check [0-9]+/ { in_check = 0 }
        in_check && /Detect:.*paths\.[a-z_]+/ {
            line = $0
            while (match(line, /paths\.[a-z_]+/)) {
                print substr(line, RSTART + 6, RLENGTH - 6)
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$init_skill" | sort -u)
fi

errors=0

# Forward check — every declared key has at least one consumer.
echo "=== Forward check: every paths.* in the template is consumed ==="
for key in "${!declared[@]}"; do
    if [ -z "${referenced[$key]+x}" ]; then
        echo "  DEAD   paths.$key — declared in template, zero consumers"
        errors=$((errors + 1))
    fi
done
echo

# Reverse check — every referenced key exists in the template, with two
# allowed exceptions: deprecated keys (called out in patch-mode Detect
# prose) and the keys naturally produced by the deprecation-prose scan
# itself.
echo "=== Reverse check: every paths.* reference exists in the template ==="
for key in "${!referenced[@]}"; do
    if [ -n "${declared[$key]+x}" ]; then
        continue
    fi
    if [ -n "${deprecated[$key]+x}" ]; then
        # Deprecation prose, not a real consumer — skip.
        continue
    fi
    echo "  UNKNOWN paths.$key — referenced but not in template"
    errors=$((errors + 1))
done
echo

if [ "$errors" -gt 0 ]; then
    echo "FAIL: $errors consistency issue(s) found."
    exit 1
fi
echo "PASS: forward + reverse config consistency clean."
