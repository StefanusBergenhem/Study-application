#!/usr/bin/env bash
#
# check_spec_links.sh — Mechanical validation of every cross-artifact link in
# the spec layer (COMPONENTS.yaml + ADRs + optional roadmap).
#
# Owned by: wf-skill-spec-references (shared spec-layer machinery).
# Invoked by: SA Phase 5 pre-flight. Producer-owns; the arbitrator does not
# invoke this directly — it relies on the producer to have reached a clean
# script state before dispatch.
#
# Checks (project-agnostic, see wf/docs/wf-architecture.html §Link fields inventory):
#   1. traces_to entries resolve (roadmap capability/external constraint, ADR id, or peer REQ id).
#   2. No SYS-REQ ids in traces_to (must use derives_from).
#   3. derives_from SYS-REQ ids exist.
#   4. allocated_to <-> derives_from symmetry (both directions).
#   5. allocated_to components exist.
#   6. governs_components <-> governed_by_adrs symmetry (both directions).
#   7. governs_components components exist.
#   8. governed_by_adrs ADRs exist on disk.
#   9. supersedes <-> superseded_by symmetry.
#  10. depends_on references resolve; no cycles.
#  11. conventions block: id uniqueness, required fields, enforced_by enum,
#      traces_to ADR resolution.
#  12. accepted ADRs are ratified: at least one REQ (SYS-REQ or component REQ)
#      in the ADR's governs_components traces back via traces_to.
#
# Usage:
#   check_spec_links.sh [--config <path>] [--json]
#
# Exit codes:
#   0 = no blocking findings (warnings may be present)
#   1 = blocking findings present
#   2 = script error (missing config, malformed input, no PyYAML)
#
# Dependencies: python3 with PyYAML.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH=".workflow/config.yaml"
EMIT_JSON=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --json)   EMIT_JSON=1; shift ;;
        -h|--help)
            sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
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

exec python3 - "$CONFIG_PATH" "$EMIT_JSON" <<'PYEOF'
import json
import os
import re
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
emit_json = sys.argv[2] == "1"
project_root = (
    config_path.parent.parent if config_path.name == "config.yaml" else Path.cwd()
).resolve()

try:
    config = yaml.safe_load(config_path.read_text()) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {config_path}: {exc}\n")
    sys.exit(2)

paths = config.get("paths", {}) or {}
components_path = (project_root / paths.get("components", "COMPONENTS.yaml")).resolve()
adrs_dir = (project_root / paths.get("adrs", "docs/adrs")).resolve()
roadmap_path_str = paths.get("roadmap", "")
roadmap_path = (project_root / roadmap_path_str).resolve() if roadmap_path_str else None

if not components_path.exists():
    sys.stderr.write(f"error: components file not found at {components_path}\n")
    sys.exit(2)

try:
    components_doc = yaml.safe_load(components_path.read_text()) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {components_path}: {exc}\n")
    sys.exit(2)

sys_reqs = components_doc.get("system_requirements", []) or []
components = components_doc.get("components", {}) or {}
conventions = components_doc.get("conventions", []) or []

# ---------- Index everything ------------------------------------------------

sys_req_ids = {r["id"] for r in sys_reqs if isinstance(r, dict) and "id" in r}
component_names = set(components.keys())

# component_req_id -> (component_name, req_dict)
component_req_index = {}
for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    for req in c.get("requirements", []) or []:
        if isinstance(req, dict) and "id" in req:
            component_req_index[req["id"]] = (cname, req)

# Load ADRs from disk
adr_index = {}  # adr_id -> {file, frontmatter}
if adrs_dir.exists():
    for adr_file in sorted(adrs_dir.glob("ADR-*.md")):
        text = adr_file.read_text()
        m = re.match(r"---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
        if not m:
            continue
        try:
            front = yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError:
            continue
        if isinstance(front, dict) and "id" in front:
            adr_index[front["id"]] = {"file": adr_file, "frontmatter": front}

# Roadmap entity ids — capabilities (CAP-NNN), external constraints (EXT-NNN),
# and optionally other namespaces the strategist authored (OOS-, OPQ-, DEF-).
roadmap_ids = set()
if roadmap_path and roadmap_path.exists():
    try:
        roadmap_doc = yaml.safe_load(roadmap_path.read_text()) or {}
    except yaml.YAMLError:
        roadmap_doc = {}

    def collect_ids(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "id" and isinstance(v, str):
                    roadmap_ids.add(v)
                else:
                    collect_ids(v)
        elif isinstance(obj, list):
            for item in obj:
                collect_ids(item)
    collect_ids(roadmap_doc)

# ---------- Finding emitter -------------------------------------------------

# Fix-hint templates per finding kind. Each entry is a short, structured
# action the producer (SA) can consume in pre-flight to resolve the finding
# without round-tripping through the arbitrator. Asymmetric / route-choice
# kinds use the "(a) ... / (b) ..." form; trivial schema kinds use a single
# corrective action. Call sites MAY pass an explicit fix_hint= argument to
# emit() with parametrised values; the asymmetric kinds do this so the
# routes name the specific REQ / SYS-REQ / component involved.
FIX_HINTS_BY_KIND = {
    "trace_non_string":              "ensure all traces_to entries are strings",
    "sys_req_in_traces_to":          "move the SYS-REQ id from traces_to to derives_from (SYS-REQ allocation is the formal link, not a trace)",
    "ghost_sys_req_in_traces_to":    "(a) author the missing SYS-REQ in system_requirements / (b) drop the trace",
    "ghost_req_ref":                 "(a) author the missing REQ in the target component / (b) drop the trace",
    "ghost_adr_ref":                 "(a) author the missing ADR file under paths.adrs / (b) drop the trace",
    "stale_roadmap_trace":           "(a) add the entity to the roadmap / (b) update or drop the trace",
    "unrecognised_trace":            "review the token format — must match SYS-REQ-NNN, REQ-<COMP>-NNN, ADR-NNN, CAP-NNN, or EXT-NNN",
    "derive_non_string":             "ensure all derives_from entries are strings",
    "derive_wrong_id":               "move the non-SYS-REQ id from derives_from to traces_to (derives_from is SYS-REQ only)",
    "ghost_sys_req_in_derives_from": "(a) author the missing SYS-REQ / (b) drop derives_from from this REQ",
    "sys_req_unallocated":           "(a) allocate to ≥1 component / (b) demote to a component REQ inside the relevant component",
    "ghost_component_in_alloc":      "(a) declare the component in components: / (b) drop it from allocated_to",
    "asymmetric_alloc_no_back_link": "(a) author a REQ in the allocated component with derives_from: [<sys-req>] / (b) drop the component from allocated_to",
    "asymmetric_alloc_no_alloc_entry": "(a) add the component to <sys-req>.allocated_to / (b) remove derives_from: [<sys-req>] from the component REQ",
    "adr_ref_non_string":            "ensure all governed_by_adrs entries are strings",
    "ghost_adr_in_component":        "(a) author the missing ADR file / (b) drop it from governed_by_adrs",
    "adr_empty_governs":             "(a) populate governs_components with the component(s) this ADR shapes / (b) demote to status: proposed",
    "governs_non_string":            "ensure all governs_components entries are strings",
    "ghost_component_in_adr":        "(a) declare the component in components: / (b) drop it from governs_components",
    "asymmetric_adr_no_back_link":   "(a) add the ADR to the component's governed_by_adrs / (b) drop the component from the ADR's governs_components",
    "asymmetric_adr_no_govern_entry":"(a) add the component to the ADR's governs_components / (b) drop the ADR from the component's governed_by_adrs",
    "ghost_supersedes":              "(a) author the missing ADR / (b) clear the supersedes field",
    "ghost_superseded_by":           "(a) author the missing ADR / (b) clear the superseded_by field",
    "asymmetric_supersession":       "align both sides: set the missing back-link (supersedes / superseded_by) to match its partner, or correct the existing mismatch",
    "adr_accepted_unratified":       "(a) add traces_to: [<adr>] on one REQ or CONV in the governed components / (b) demote the ADR to status: proposed",
    "conv_not_mapping":              "rewrite the conventions entry as a YAML mapping",
    "conv_id_malformed":             "use a CONV-NNN id (zero-padded, monotonically increasing)",
    "conv_id_duplicate":             "renumber one of the duplicate CONV entries",
    "conv_missing_field":            "populate the missing required field",
    "conv_enforced_by_invalid":      "use one of: lint | ci-script | review | nothing",
    "conv_enforced_by_nothing":      "give the convention a real handle (lint / ci-script / review) on next iteration; transitionally acceptable",
    "conv_traces_not_list":          "rewrite traces_to as a YAML list",
    "conv_trace_non_string":         "ensure all traces_to entries are strings",
    "conv_trace_not_adr":            "conventions only trace to ADRs — replace or remove the non-ADR token",
    "conv_ghost_adr":                "(a) author the missing ADR / (b) drop it from the convention's traces_to",
    "conventions_not_list":          "rewrite the conventions block as a YAML list",
    "missing_depends_on":            "add an explicit `depends_on: []` field to the component",
    "depends_on_not_list":           "rewrite depends_on as a YAML list (use `depends_on: []` if empty)",
    "depends_on_non_string":         "ensure all depends_on entries are strings",
    "ghost_depends_on":              "(a) declare the missing component / (b) drop it from depends_on",
    "depends_on_cycle":              "break the cycle: remove one edge, invert one dependency, or introduce a mediating interface",
}

findings = []
next_id = [0]
def emit(kind, severity, field, message, fix_hint=None):
    next_id[0] += 1
    if fix_hint is None:
        fix_hint = FIX_HINTS_BY_KIND.get(kind, "")
    findings.append({
        "id": f"F-{next_id[0]:03d}",
        "category": "spec_links",
        "kind": kind,
        "severity": severity,
        "artifact": str(components_path.relative_to(project_root)),
        "field": field,
        "message": message,
        "fix_hint": fix_hint,
    })

# ---------- Check 1 & 2 & 3 — traces_to + derives_from at REQ level --------

ID_PATTERNS = {
    "sys_req":      re.compile(r"^SYS-REQ-\d+"),
    "comp_req":     re.compile(r"^REQ-[A-Z0-9]+-\d+"),
    "adr":          re.compile(r"^ADR-\d+"),
    # Roadmap entity ids — capability (CAP-NNN), external constraint (EXT-NNN),
    # or the strategist's auxiliary namespaces (OOS / OPQ / DEF). REQs typically
    # trace to CAP or EXT; the others are matched so a misdirected trace
    # surfaces with a precise message instead of "unrecognised pattern".
    "roadmap_like": re.compile(r"^(CAP|EXT|OOS|OPQ|DEF)-\d+"),
}

def classify_trace(token):
    for kind, pat in ID_PATTERNS.items():
        if pat.match(token):
            return kind
    return "unknown"

def check_traces_to(field_path, traces, source_kind):
    """source_kind: 'sys_req' or 'comp_req'.

    SYS-REQ ids are forbidden in traces_to on component REQs (must use
    derives_from). SYS-REQ-to-SYS-REQ traces_to entries are allowed — they
    express peer lineage (e.g., an NFR SYS-REQ that derives from functional
    SYS-REQs).
    """
    if not traces:
        return
    for token in traces:
        if not isinstance(token, str):
            emit("trace_non_string", "block", field_path,
                 f"traces_to entry is not a string: {token!r}")
            continue
        kind = classify_trace(token)
        if kind == "sys_req":
            if source_kind == "comp_req":
                emit("sys_req_in_traces_to", "block", field_path,
                     f"{token} appears in component REQ traces_to; move to derives_from "
                     f"(SYS-REQ allocation is the formal link, not a trace).")
            elif token not in sys_req_ids:
                emit("ghost_sys_req_in_traces_to", "block", field_path,
                     f"traces_to references {token} which does not exist in system_requirements.")
        elif kind == "comp_req":
            if token not in component_req_index:
                emit("ghost_req_ref", "block", field_path,
                     f"traces_to references {token} which does not exist in any component.")
        elif kind == "adr":
            if token not in adr_index:
                emit("ghost_adr_ref", "block", field_path,
                     f"traces_to references {token} which has no file under paths.adrs.")
        elif kind == "roadmap_like":
            if roadmap_path and roadmap_path.exists() and token not in roadmap_ids:
                emit("stale_roadmap_trace", "warn", field_path,
                     f"traces_to references {token} which is not declared in {roadmap_path_str}.")
        else:
            emit("unrecognised_trace", "warn", field_path,
                 f"traces_to entry {token!r} does not match SYS-REQ / REQ / ADR / CAP / EXT pattern.")

def check_derives_from(field_path, derives):
    if not derives:
        return
    for token in derives:
        if not isinstance(token, str):
            emit("derive_non_string", "block", field_path,
                 f"derives_from entry is not a string: {token!r}")
            continue
        if not ID_PATTERNS["sys_req"].match(token):
            emit("derive_wrong_id", "block", field_path,
                 f"derives_from entry {token} is not a SYS-REQ id (derives_from is only for SYS-REQ).")
        elif token not in sys_req_ids:
            emit("ghost_sys_req_in_derives_from", "block", field_path,
                 f"derives_from references {token} which does not exist in system_requirements.")

for sr in sys_reqs:
    if not isinstance(sr, dict) or "id" not in sr:
        continue
    sid = sr["id"]
    check_traces_to(
        f"system_requirements[{sid}].traces_to",
        sr.get("traces_to", []) or [],
        "sys_req",
    )

for rid, (cname, req) in component_req_index.items():
    base = f"components.{cname}.requirements[{rid}]"
    check_traces_to(f"{base}.traces_to", req.get("traces_to", []) or [], "comp_req")
    check_derives_from(f"{base}.derives_from", req.get("derives_from", []) or [])

# ---------- Check 4 & 5 — allocated_to <-> derives_from symmetry -----------

# Build derives-from map: sys_req_id -> {component_names that back-link}
derives_back = {sid: set() for sid in sys_req_ids}
for rid, (cname, req) in component_req_index.items():
    for sid in (req.get("derives_from", []) or []):
        if isinstance(sid, str) and sid in sys_req_ids:
            derives_back[sid].add(cname)

for sr in sys_reqs:
    if not isinstance(sr, dict) or "id" not in sr:
        continue
    sid = sr["id"]
    allocated = list(sr.get("allocated_to", []) or [])
    field = f"system_requirements[{sid}].allocated_to"
    if not allocated:
        emit("sys_req_unallocated", "block", field,
             f"{sid} has empty allocated_to; allocate to ≥1 component or demote to component REQ.")
        continue
    for comp in allocated:
        if comp not in component_names:
            emit("ghost_component_in_alloc", "block", field,
                 f"{sid}.allocated_to lists '{comp}' which is not declared in components:.")
            continue
        if comp not in derives_back[sid]:
            emit("asymmetric_alloc_no_back_link", "block", field,
                 f"{sid} allocated to '{comp}' but no REQ in '{comp}' has derives_from: [{sid}].",
                 fix_hint=f"(a) author a REQ in component '{comp}' with derives_from: [{sid}] / (b) drop '{comp}' from {sid}.allocated_to")

# Reverse: components that back-link to a SYS-REQ NOT in its allocated_to
for sid, comps_with_back_link in derives_back.items():
    sr = next((r for r in sys_reqs if isinstance(r, dict) and r.get("id") == sid), None)
    if sr is None:
        continue
    allocated_set = set(sr.get("allocated_to", []) or [])
    for comp in comps_with_back_link - allocated_set:
        emit("asymmetric_alloc_no_alloc_entry", "block",
             f"components.{comp}.requirements[*].derives_from",
             f"Component '{comp}' has REQ with derives_from: [{sid}] but {sid}.allocated_to does not include '{comp}'.",
             fix_hint=f"(a) add '{comp}' to {sid}.allocated_to / (b) remove derives_from: [{sid}] from the REQ in '{comp}'")

# ---------- Check 6, 7, 8 — ADR <-> component symmetry -------------------

# component name -> set of ADR ids it claims in governed_by_adrs
comp_governs = {}
for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    adrs = c.get("governed_by_adrs", []) or []
    comp_governs[cname] = set(adrs)
    field = f"components.{cname}.governed_by_adrs"
    for aid in adrs:
        if not isinstance(aid, str):
            emit("adr_ref_non_string", "block", field,
                 f"governed_by_adrs entry is not a string: {aid!r}")
            continue
        if aid not in adr_index:
            emit("ghost_adr_in_component", "block", field,
                 f"'{cname}'.governed_by_adrs lists {aid} which has no file under paths.adrs.")

# ADR -> claimed components
for aid, info in adr_index.items():
    front = info["frontmatter"]
    governs = front.get("governs_components", []) or []
    field = f"adrs/{aid}.governs_components"
    if not governs:
        # Only flag accepted ADRs without governs (proposed/superseded/deprecated may be empty mid-flight).
        if front.get("status", "accepted") == "accepted":
            emit("adr_empty_governs", "block", field,
                 f"{aid} (status=accepted) has empty governs_components; an accepted ADR must shape ≥1 component.")
        continue
    for comp in governs:
        if not isinstance(comp, str):
            emit("governs_non_string", "block", field, f"governs_components entry is not a string: {comp!r}")
            continue
        if comp not in component_names:
            emit("ghost_component_in_adr", "block", field,
                 f"{aid}.governs_components lists '{comp}' which is not declared in components:.")
            continue
        if aid not in comp_governs.get(comp, set()):
            emit("asymmetric_adr_no_back_link", "block", field,
                 f"{aid} claims to govern '{comp}' but '{comp}'.governed_by_adrs does not include {aid}.",
                 fix_hint=f"(a) add {aid} to '{comp}'.governed_by_adrs / (b) drop '{comp}' from {aid}.governs_components")

# Reverse: components claim ADRs that don't list them
for cname, claimed_adrs in comp_governs.items():
    for aid in claimed_adrs:
        if aid not in adr_index:
            continue  # already flagged
        front = adr_index[aid]["frontmatter"]
        governs = set(front.get("governs_components", []) or [])
        if cname not in governs:
            emit("asymmetric_adr_no_govern_entry", "block",
                 f"adrs/{aid}.governs_components",
                 f"Component '{cname}' lists {aid} in governed_by_adrs but {aid}.governs_components does not include '{cname}'.",
                 fix_hint=f"(a) add '{cname}' to {aid}.governs_components / (b) drop {aid} from '{cname}'.governed_by_adrs")

# ---------- Check 9 — supersedes <-> superseded_by ------------------------

for aid, info in adr_index.items():
    front = info["frontmatter"]
    sup = front.get("supersedes")
    if sup:
        field = f"adrs/{aid}.supersedes"
        if sup not in adr_index:
            emit("ghost_supersedes", "block", field,
                 f"{aid}.supersedes references {sup} which has no file under paths.adrs.")
        else:
            other_front = adr_index[sup]["frontmatter"]
            if other_front.get("superseded_by") != aid:
                emit("asymmetric_supersession", "block", field,
                     f"{aid}.supersedes {sup} but {sup}.superseded_by is "
                     f"{other_front.get('superseded_by')!r}, expected {aid!r}.",
                     fix_hint=f"set {sup}.superseded_by to {aid} (the newer ADR's supersedes is the source of truth)")
    sb = front.get("superseded_by")
    if sb:
        field = f"adrs/{aid}.superseded_by"
        if sb not in adr_index:
            emit("ghost_superseded_by", "block", field,
                 f"{aid}.superseded_by references {sb} which has no file under paths.adrs.")
        else:
            other_front = adr_index[sb]["frontmatter"]
            if other_front.get("supersedes") != aid:
                emit("asymmetric_supersession", "block", field,
                     f"{aid}.superseded_by {sb} but {sb}.supersedes is "
                     f"{other_front.get('supersedes')!r}, expected {aid!r}.",
                     fix_hint=f"set {sb}.supersedes to {aid} (or clear {aid}.superseded_by if the supersession claim was wrong)")

# ---------- Check 12 — accepted ADR ratification --------------------------
#
# For every ADR with status: accepted, at least one ratifying trace must
# point at it. A ratifying trace is any traces_to entry on a SYS-REQ, a
# component REQ, or a conventions entry. Without one the ADR is a forward
# declaration — a plan, not a ratified decision.
#
# The conventions block IS counted here: a CONV that traces to an ADR is
# real consumption of the decision (the rule the ADR ratifies is in active
# use), so it satisfies ratification.

referenced_adrs = set()
for sr in sys_reqs:
    if isinstance(sr, dict):
        for token in (sr.get("traces_to", []) or []):
            if isinstance(token, str) and ID_PATTERNS["adr"].match(token):
                referenced_adrs.add(token)
for rid, (cname, req) in component_req_index.items():
    for token in (req.get("traces_to", []) or []):
        if isinstance(token, str) and ID_PATTERNS["adr"].match(token):
            referenced_adrs.add(token)
if isinstance(conventions, list):
    for conv in conventions:
        if not isinstance(conv, dict):
            continue
        for token in (conv.get("traces_to", []) or []):
            if isinstance(token, str) and ID_PATTERNS["adr"].match(token):
                referenced_adrs.add(token)

for aid, info in adr_index.items():
    front = info["frontmatter"]
    if front.get("status") != "accepted":
        continue
    if aid not in referenced_adrs:
        emit("adr_accepted_unratified", "warn",
             f"adrs/{aid}.status",
             f"{aid} is status: accepted but no REQ or CONV traces back to it. "
             f"Add a traces_to entry in one of its governs_components (REQ) "
             f"or in the conventions block, or demote to status: proposed "
             f"until the implementing spec lands.")

# ---------- Check 11 — conventions block ----------------------------------

CONV_ID_PAT = re.compile(r"^CONV-\d+$")
VALID_ENFORCED_BY = {"lint", "ci-script", "review", "nothing"}
REQUIRED_CONV_FIELDS = ("rule", "rationale", "enforced_by", "applies_to")

if isinstance(conventions, list):
    seen_conv_ids = {}
    for idx, conv in enumerate(conventions):
        if not isinstance(conv, dict):
            emit("conv_not_mapping", "block",
                 f"conventions[{idx}]",
                 f"conventions entry at index {idx} is not a mapping (got {type(conv).__name__}).")
            continue
        cid = conv.get("id")
        cid_field = f"conventions[{idx}].id"
        if not isinstance(cid, str) or not CONV_ID_PAT.match(cid):
            emit("conv_id_malformed", "block", cid_field,
                 f"conventions entry id {cid!r} does not match CONV-\\d+.")
            cid = f"<idx={idx}>"
        else:
            if cid in seen_conv_ids:
                emit("conv_id_duplicate", "block", cid_field,
                     f"{cid} appears more than once in conventions block "
                     f"(first at index {seen_conv_ids[cid]}, again at {idx}).")
            else:
                seen_conv_ids[cid] = idx
        for field_name in REQUIRED_CONV_FIELDS:
            val = conv.get(field_name)
            if val is None or (isinstance(val, (str, list)) and not val):
                emit("conv_missing_field", "block",
                     f"conventions[{cid}].{field_name}",
                     f"{cid} is missing required field '{field_name}'.")
        enforced_by = conv.get("enforced_by")
        if isinstance(enforced_by, str) and enforced_by and enforced_by not in VALID_ENFORCED_BY:
            emit("conv_enforced_by_invalid", "block",
                 f"conventions[{cid}].enforced_by",
                 f"{cid}.enforced_by {enforced_by!r} is not one of "
                 f"{{lint, ci-script, review, nothing}}.")
        elif enforced_by == "nothing":
            emit("conv_enforced_by_nothing", "warn",
                 f"conventions[{cid}].enforced_by",
                 f"{cid} has enforced_by: nothing — acceptable transitionally, "
                 f"but give it a real handle (lint, ci-script, or review) on next iteration.")
        traces = conv.get("traces_to", []) or []
        if traces and not isinstance(traces, list):
            emit("conv_traces_not_list", "block",
                 f"conventions[{cid}].traces_to",
                 f"{cid}.traces_to must be a list.")
        else:
            for token in traces:
                if not isinstance(token, str):
                    emit("conv_trace_non_string", "block",
                         f"conventions[{cid}].traces_to",
                         f"{cid}.traces_to entry is not a string: {token!r}")
                    continue
                if not ID_PATTERNS["adr"].match(token):
                    emit("conv_trace_not_adr", "warn",
                         f"conventions[{cid}].traces_to",
                         f"{cid}.traces_to entry {token!r} is not an ADR id — "
                         f"conventions only trace to ADRs.")
                elif token not in adr_index:
                    emit("conv_ghost_adr", "block",
                         f"conventions[{cid}].traces_to",
                         f"{cid}.traces_to references {token} which has no file under paths.adrs.")
elif conventions:
    emit("conventions_not_list", "block", "conventions",
         f"conventions block must be a list (got {type(conventions).__name__}).")

# ---------- Check 10 — depends_on resolution + cycles ---------------------

dep_graph = {}
for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    deps = c.get("depends_on")
    field = f"components.{cname}.depends_on"
    if deps is None:
        emit("missing_depends_on", "warn", field,
             f"Component '{cname}' missing depends_on; use `depends_on: []` explicitly.")
        dep_graph[cname] = []
        continue
    if not isinstance(deps, list):
        emit("depends_on_not_list", "block", field,
             f"depends_on must be a list (got {type(deps).__name__}).")
        dep_graph[cname] = []
        continue
    dep_graph[cname] = []
    for d in deps:
        if not isinstance(d, str):
            emit("depends_on_non_string", "block", field, f"depends_on entry is not a string: {d!r}")
            continue
        if d not in component_names:
            emit("ghost_depends_on", "block", field,
                 f"depends_on references '{d}' which is not a declared component.")
            continue
        dep_graph[cname].append(d)

# Cycle detection (DFS)
WHITE, GREY, BLACK = 0, 1, 2
color = {n: WHITE for n in dep_graph}
cycles = []
def dfs(node, stack):
    color[node] = GREY
    stack.append(node)
    for nxt in dep_graph.get(node, []):
        if color.get(nxt) == GREY:
            i = stack.index(nxt)
            cycles.append(stack[i:] + [nxt])
        elif color.get(nxt) == WHITE:
            dfs(nxt, stack)
    stack.pop()
    color[node] = BLACK
for n in list(color.keys()):
    if color[n] == WHITE:
        dfs(n, [])
for cyc in cycles:
    emit("depends_on_cycle", "block", "components.*.depends_on",
         f"Circular depends_on: {' -> '.join(cyc)}")

# ---------- Output --------------------------------------------------------

blocks = sum(1 for f in findings if f["severity"] == "block")
warns = sum(1 for f in findings if f["severity"] == "warn")

conv_count = len(conventions) if isinstance(conventions, list) else 0


result = {
    "summary": {
        "components": len(component_names),
        "sys_reqs": len(sys_req_ids),
        "adrs": len(adr_index),
        "conventions": conv_count,
        "blocks": blocks,
        "warns": warns,
    },
    "findings": findings,
}

if emit_json:
    print(json.dumps(result, indent=2, sort_keys=False))
else:
    print(f"check_spec_links — components={len(component_names)} sys_reqs={len(sys_req_ids)} adrs={len(adr_index)} conventions={conv_count}")
    if not findings:
        print("OK — no findings.")
    else:
        for f in findings:
            sev = "BLOCK" if f["severity"] == "block" else "WARN "
            print(f"  [{sev}] {f['kind']:35s} {f['field']}")
            print(f"          {f['message']}")
            if f.get("fix_hint"):
                print(f"          fix_hint: {f['fix_hint']}")
    print(f"summary: blocks={blocks} warns={warns}")

sys.exit(1 if blocks else 0)
PYEOF
