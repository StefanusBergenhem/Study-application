#!/usr/bin/env bash
#
# check_ac_policy.sh — Mechanical enforcement of the per-type AC policy
# (wf/skills/wf-skill-spec-references/references/ears-syntax.md §Per-type policy).
#
# Owned by: wf-skill-spec-references (shared spec-layer machinery).
# Invoked by: SA Phase 5 pre-flight. Producer-owns; the arbitrator does not invoke this directly.
#
# Block-level checks (always mechanical):
#   - functional REQ has non-empty acceptance_criteria
#   - nfr REQ has nfr_elements with all five keys present (or DEFER-NUMERIC marker)
#   - invariant statement is non-empty
#
# Warn-level heuristics (string-similarity over 0.80):
#   - nfr REQ has AC bullet that paraphrases nfr_elements.threshold or condition
#   - invariant REQ has AC bullet that paraphrases the statement
#   - interface REQ has AC bullet that paraphrases a DbC postcondition
#     (best-effort; matches against the exposes block of the same component)
#
# Usage:
#   check_ac_policy.sh [--config <path>] [--json] [--no-fuzzy]
#
# Exit codes:
#   0 = no blocking findings
#   1 = blocking findings present
#   2 = script error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH=".workflow/config.yaml"
EMIT_JSON=0
NO_FUZZY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --json) EMIT_JSON=1; shift ;;
        --no-fuzzy) NO_FUZZY=1; shift ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required" >&2
    exit 2
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "error: config not found at $CONFIG_PATH" >&2
    exit 2
fi

exec python3 - "$CONFIG_PATH" "$EMIT_JSON" "$NO_FUZZY" <<'PYEOF'
import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "error: PyYAML is required.\n"
        "  install: pip install pyyaml\n"
    )
    sys.exit(2)

config_path = Path(sys.argv[1]).resolve()
emit_json = sys.argv[2] == "1"
fuzzy = sys.argv[3] != "1"
project_root = (
    config_path.parent.parent if config_path.name == "config.yaml" else Path.cwd()
).resolve()

config = yaml.safe_load(config_path.read_text()) or {}
paths = config.get("paths", {}) or {}
components_path = (project_root / paths.get("components", "COMPONENTS.yaml")).resolve()
if not components_path.exists():
    sys.stderr.write(f"error: components file not found at {components_path}\n")
    sys.exit(2)

doc = yaml.safe_load(components_path.read_text()) or {}
sys_reqs = doc.get("system_requirements", []) or []
components = doc.get("components", {}) or {}

NFR_KEYS = ("subject", "metric", "threshold", "condition", "source")
SIM_THRESHOLD = 0.80
DEFER_RE = re.compile(r"\[DEFER-NUMERIC")

# Fix-hint templates per finding kind. The producer (SA) consumes these in
# pre-flight to resolve the finding without round-tripping through the
# arbitrator. AC-policy findings are mechanical enough that static templates
# suffice — the message already includes the specific REQ id and field path.
FIX_HINTS_BY_KIND = {
    "functional_missing_ac":         "add an acceptance_criteria list with one or more measurable bullets; functional REQs require AC per the per-type policy",
    "functional_ac_unmeasurable":    "replace the empty or terse bullet with a concrete, measurable assertion (e.g. 'after POST /endpoint, response.field equals V')",
    "nfr_elements_not_dict":         "rewrite nfr_elements as a YAML mapping with the five NFR keys (subject, metric, threshold, condition, source)",
    "nfr_missing_element":           "populate the missing NFR element(s); use [DEFER-NUMERIC] in threshold if the value is not yet committed",
    "nfr_ac_defer_numeric_dup":      "remove the bullet — [DEFER-NUMERIC] belongs in nfr_elements.threshold, not in acceptance_criteria",
    "ac_paraphrases_nfr_elements":   "drop the bullet or replace with a non-redundant handle that adds something nfr_elements.threshold/condition does not",
    "invariant_statement_empty":     "populate the statement with the testable predicate; the statement IS the invariant",
    "ac_paraphrases_statement":      "drop the bullet or replace with a distinct sub-check that complements (not duplicates) the statement",
    "ac_paraphrases_dbc":            "drop the bullet or replace with a non-redundant handle; the DbC postcondition already encodes the assertion",
}

findings = []
next_id = [0]
def emit(kind, severity, field, message, fix_hint=None):
    next_id[0] += 1
    if fix_hint is None:
        fix_hint = FIX_HINTS_BY_KIND.get(kind, "")
    findings.append({
        "id": f"F-{next_id[0]:03d}",
        "category": "ac_policy",
        "kind": kind,
        "severity": severity,
        "artifact": str(components_path.relative_to(project_root)),
        "field": field,
        "message": message,
        "fix_hint": fix_hint,
    })

def normalise(text):
    if not isinstance(text, str):
        return ""
    return re.sub(r"\s+", " ", text.strip().lower())

def similar(a, b):
    return SequenceMatcher(None, normalise(a), normalise(b)).ratio()

# ---------- Walk every REQ ------------------------------------------------

def walk_req(req, base_field, exposes_postconds):
    """Apply per-type AC policy to one REQ."""
    if not isinstance(req, dict) or "id" not in req:
        return
    rid = req["id"]
    rtype = req.get("type", "")
    ac = req.get("acceptance_criteria") or []
    stmt = req.get("statement", "") or ""

    if rtype == "functional":
        if not ac:
            emit("functional_missing_ac", "block",
                 f"{base_field}.acceptance_criteria",
                 f"{rid} (functional) has no acceptance_criteria — AC is required for type=functional.")
        else:
            for i, bullet in enumerate(ac):
                if not isinstance(bullet, str) or len(bullet.strip()) < 10:
                    emit("functional_ac_unmeasurable", "block",
                         f"{base_field}.acceptance_criteria[{i}]",
                         f"{rid} (functional) acceptance_criteria[{i}] is empty or too terse to be measurable.")

    elif rtype == "nfr":
        elems = req.get("nfr_elements") or {}
        if not isinstance(elems, dict):
            emit("nfr_elements_not_dict", "block", f"{base_field}.nfr_elements",
                 f"{rid} (nfr) nfr_elements must be a mapping.")
        else:
            missing = [k for k in NFR_KEYS if not elems.get(k)]
            if missing:
                emit("nfr_missing_element", "block", f"{base_field}.nfr_elements",
                     f"{rid} (nfr) nfr_elements missing: {', '.join(missing)}.")
        # Fuzzy: if AC present, warn on bullets that paraphrase nfr_elements.
        if fuzzy and ac and isinstance(elems, dict):
            handles = [elems.get("threshold", ""), elems.get("condition", "")]
            for i, bullet in enumerate(ac):
                if not isinstance(bullet, str):
                    continue
                if DEFER_RE.search(bullet):
                    emit("nfr_ac_defer_numeric_dup", "warn",
                         f"{base_field}.acceptance_criteria[{i}]",
                         f"{rid} (nfr) acceptance_criteria[{i}] is just a [DEFER-NUMERIC] marker; drop — nfr_elements.threshold carries it.")
                    continue
                for handle in handles:
                    if handle and similar(bullet, handle) >= SIM_THRESHOLD:
                        emit("ac_paraphrases_nfr_elements", "warn",
                             f"{base_field}.acceptance_criteria[{i}]",
                             f"{rid} (nfr) acceptance_criteria[{i}] paraphrases nfr_elements.threshold/condition; drop or replace with a non-redundant handle.")
                        break

    elif rtype == "invariant":
        if not stmt.strip():
            emit("invariant_statement_empty", "block", f"{base_field}.statement",
                 f"{rid} (invariant) has empty statement; the statement is the testable predicate.")
        if fuzzy and ac:
            for i, bullet in enumerate(ac):
                if isinstance(bullet, str) and similar(bullet, stmt) >= SIM_THRESHOLD:
                    emit("ac_paraphrases_statement", "warn",
                         f"{base_field}.acceptance_criteria[{i}]",
                         f"{rid} (invariant) acceptance_criteria[{i}] restates the statement; drop or replace with a distinct sub-check.")

    elif rtype == "interface" and fuzzy and ac and exposes_postconds:
        for i, bullet in enumerate(ac):
            if not isinstance(bullet, str):
                continue
            for postcond in exposes_postconds:
                if similar(bullet, postcond) >= SIM_THRESHOLD:
                    emit("ac_paraphrases_dbc", "warn",
                         f"{base_field}.acceptance_criteria[{i}]",
                         f"{rid} (interface) acceptance_criteria[{i}] paraphrases a DbC postcondition; drop or replace.")
                    break

    # data, inherited-constraint, and any other types — no enforcement.

# Walk SYS-REQs
for sr in sys_reqs:
    if isinstance(sr, dict) and "id" in sr:
        walk_req(sr, f"system_requirements[{sr['id']}]", exposes_postconds=[])

# Walk component REQs (with their component's DbC postconditions in scope)
for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    # Collect every DbC postcondition string in this component's exposes
    postconds = []
    for ent in (c.get("exposes") or []):
        if not isinstance(ent, dict):
            continue
        post = ent.get("postconditions") or {}
        if isinstance(post, dict):
            for _, items in post.items():
                if isinstance(items, list):
                    postconds.extend(str(x) for x in items if isinstance(x, str))
    for req in (c.get("requirements") or []):
        walk_req(req, f"components.{cname}.requirements[{req.get('id','?')}]", postconds)

blocks = sum(1 for f in findings if f["severity"] == "block")
warns = sum(1 for f in findings if f["severity"] == "warn")

# Counts by type for telemetry
type_counts = {}
for sr in sys_reqs:
    if isinstance(sr, dict):
        type_counts[sr.get("type", "?")] = type_counts.get(sr.get("type", "?"), 0) + 1
for c in components.values():
    if isinstance(c, dict):
        for req in (c.get("requirements") or []):
            if isinstance(req, dict):
                type_counts[req.get("type", "?")] = type_counts.get(req.get("type", "?"), 0) + 1

result = {
    "summary": {
        "req_types": type_counts,
        "blocks": blocks,
        "warns": warns,
    },
    "findings": findings,
}

if emit_json:
    print(json.dumps(result, indent=2, sort_keys=False))
else:
    print(f"check_ac_policy — req_types={type_counts}")
    if not findings:
        print("OK — no findings.")
    else:
        for f in findings:
            sev = "BLOCK" if f["severity"] == "block" else "WARN "
            print(f"  [{sev}] {f['kind']:32s} {f['field']}")
            print(f"          {f['message']}")
            if f.get("fix_hint"):
                print(f"          fix_hint: {f['fix_hint']}")
    print(f"summary: blocks={blocks} warns={warns}")

sys.exit(1 if blocks else 0)
PYEOF
