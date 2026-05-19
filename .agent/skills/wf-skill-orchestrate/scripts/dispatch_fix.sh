#!/usr/bin/env bash
#
# dispatch_fix.sh — Routing helper for orchestrator DESIGN_ISSUE handling.
#
# Owned by: wf-skill-orchestrate.
# Invoked by: orchestrator on DESIGN_ISSUE verdict from build or review.
#
# Reads a DI entry from paths.design_issues, extracts fix_kind, and emits a
# structured routing decision on stdout (which agent to dispatch, with which
# context envelope). Future fix_kind values are added in the ROUTING table
# below — one place, not scattered across the orchestrator SKILL prose.
#
# Usage:
#   dispatch_fix.sh <di-id> [--config <path>]
#
# Output (stdout, JSON):
#   {
#     "di_id": "DI-007",
#     "task_id": "S1.3",
#     "fix_kind": "contract_amendment",
#     "subagent_type": "wf-swa",
#     "human_gate": false,
#     "envelope": {
#       "mode": "fix",
#       "di_id": "DI-007",
#       "task_id": "S1.3",
#       "di_artifact": "<rel path>",
#       "sprint_artifact": "<rel path>",
#       "components_artifact": "<rel path>"
#     }
#   }
#
# Exit codes:
#   0 = routing decision emitted (dispatch the named subagent_type)
#   1 = HALT decision (human gate; orchestrator surfaces to human)
#   2 = script error (missing DI, malformed config, etc.)
#
# Dependencies: python3 with PyYAML.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH=".workflow/config.yaml"

di_id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) echo "unknown arg: $1" >&2; exit 2 ;;
        *)  di_id="$1"; shift ;;
    esac
done

if [[ -z "$di_id" ]]; then
    echo "error: DI id is required (positional arg)" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required" >&2
    exit 2
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "error: config not found at $CONFIG_PATH" >&2
    exit 2
fi

exec python3 - "$CONFIG_PATH" "$di_id" <<'PYEOF'
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "error: PyYAML is required.\n"
        "  install: pip install pyyaml  (or: apt install python3-yaml)\n"
    )
    sys.exit(2)

config_path = Path(sys.argv[1]).resolve()
di_id = sys.argv[2]
project_root = (
    config_path.parent.parent if config_path.name == "config.yaml" else Path.cwd()
).resolve()

try:
    config = yaml.safe_load(config_path.read_text()) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {config_path}: {exc}\n")
    sys.exit(2)

paths = config.get("paths", {}) or {}
di_path = (project_root / paths.get("design_issues", "design_issues.yaml")).resolve()
sprint_path = (project_root / paths.get("sprint", "sprint.yaml")).resolve()
components_path = (project_root / paths.get("components", "COMPONENTS.yaml")).resolve()

if not di_path.exists():
    sys.stderr.write(f"error: design issues file not found at {di_path}\n")
    sys.exit(2)

try:
    doc = yaml.safe_load(di_path.read_text()) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {di_path}: {exc}\n")
    sys.exit(2)

issues = doc.get("issues", []) or []
entry = next((i for i in issues if isinstance(i, dict) and i.get("id") == di_id), None)
if entry is None:
    sys.stderr.write(f"error: DI {di_id} not found in {di_path}\n")
    sys.exit(2)

status = entry.get("status", "open")
if status in ("resolved", "overridden"):
    sys.stderr.write(
        f"error: DI {di_id} status is '{status}'; no routing decision needed\n"
    )
    sys.exit(2)

fix_kind = entry.get("fix_kind", "")
task_id = entry.get("task_id", "")

# Routing table. Add new fix_kind values here.
# subagent_type=None → human gate (orchestrator HALTs, does not dispatch).
ROUTING = {
    "contract_amendment": {"subagent_type": "wf-swa", "human_gate": False},
    "spec_amendment":     {"subagent_type": "wf-sa",  "human_gate": False},
    "unknown":            {"subagent_type": None,     "human_gate": True},
}

route = ROUTING.get(fix_kind)
unrecognised = route is None
if unrecognised:
    sys.stderr.write(
        f"warning: DI {di_id} has unrecognised fix_kind '{fix_kind}'. "
        f"Treating as 'unknown' (human gate). "
        f"Recognised values: {sorted(k for k in ROUTING if k)}.\n"
    )
    route = ROUTING["unknown"]
    fix_kind = fix_kind or "unknown"

def relpath(p):
    try:
        return str(p.relative_to(project_root))
    except ValueError:
        return str(p)

envelope = {
    "mode": "fix",
    "di_id": di_id,
    "task_id": task_id,
    "di_artifact": relpath(di_path),
    "sprint_artifact": relpath(sprint_path),
    "components_artifact": relpath(components_path),
}

result = {
    "di_id": di_id,
    "task_id": task_id,
    "fix_kind": fix_kind,
    "subagent_type": route["subagent_type"],
    "human_gate": route["human_gate"],
    "envelope": envelope,
}

print(json.dumps(result, indent=2, sort_keys=False))

sys.exit(1 if route["human_gate"] else 0)
PYEOF
