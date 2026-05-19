#!/usr/bin/env bash
#
# sync_spec_mirrors.sh — Auto-mirror bidirectional spec links so the SA can
# edit one side and the script populates the other.
#
# Owned by: wf-skill-spec-references (shared spec-layer machinery).
# Invoked by: SA at end of Phase 4a (before dispatching arbitrator). Producer-owns; the arbitrator does not invoke this directly.
#
# What it syncs (union semantics — both sides become the union of what each had):
#
#   1. SYS-REQ.allocated_to  <-->  component REQ.derives_from
#   2. ADR.governs_components <-->  component.governed_by_adrs
#   3. ADR.supersedes        <-->  ADR.superseded_by
#
# Comments and unrelated formatting are preserved (line-by-line edit).
#
# Usage:
#   sync_spec_mirrors.sh [--config <path>] [--check] [--json]
#
# Modes:
#   default — apply changes, write files in place. Reports what changed.
#   --check — dry-run. Report drift but do not modify files. Exit 1 on drift.
#
# Exit codes:
#   0 = no drift (or apply mode succeeded)
#   1 = drift detected (in --check mode) or apply mode found nothing to do
#       but inputs are inconsistent in a way the script cannot reconcile
#   2 = script error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH=".workflow/config.yaml"
CHECK_ONLY=0
EMIT_JSON=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --check) CHECK_ONLY=1; shift ;;
        --json) EMIT_JSON=1; shift ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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

exec python3 - "$CONFIG_PATH" "$CHECK_ONLY" "$EMIT_JSON" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("error: PyYAML is required.\n")
    sys.exit(2)

config_path = Path(sys.argv[1]).resolve()
check_only = sys.argv[2] == "1"
emit_json = sys.argv[3] == "1"
project_root = (
    config_path.parent.parent if config_path.name == "config.yaml" else Path.cwd()
).resolve()

config = yaml.safe_load(config_path.read_text()) or {}
paths = config.get("paths", {}) or {}
components_path = (project_root / paths.get("components", "COMPONENTS.yaml")).resolve()
adrs_dir = (project_root / paths.get("adrs", "docs/adrs")).resolve()

if not components_path.exists():
    sys.stderr.write(f"error: components file not found at {components_path}\n")
    sys.exit(2)

doc = yaml.safe_load(components_path.read_text()) or {}
sys_reqs = doc.get("system_requirements", []) or []
components = doc.get("components", {}) or {}

changes = []  # human-readable change log
def log(kind, path, before, after):
    changes.append({"kind": kind, "path": path, "before": before, "after": after})

# ---------- Step 1: compute the desired state for every link --------------

# 1a — SYS-REQ.allocated_to  <-->  component REQ.derives_from
sys_req_ids = {sr["id"] for sr in sys_reqs if isinstance(sr, dict) and "id" in sr}

# Each SYS-REQ -> union set of components allocated to it.
target_allocated = {sid: set() for sid in sys_req_ids}
# Each component -> union per SYS-REQ that the component derives from
#                    (so we know what derives_from each REQ should carry).
# For derives_from we DON'T touch the per-REQ side (multiple REQs in one
# component may each carry their own derives_from). Instead we propagate
# upward: if any REQ in a component has derives_from: [X], then allocated_to
# of X must include that component.

# Read both sides into unions.
for sr in sys_reqs:
    if isinstance(sr, dict) and "id" in sr:
        for c in (sr.get("allocated_to") or []):
            if isinstance(c, str):
                target_allocated[sr["id"]].add(c)

for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    for req in (c.get("requirements") or []):
        if not isinstance(req, dict):
            continue
        for sid in (req.get("derives_from") or []):
            if isinstance(sid, str) and sid in sys_req_ids:
                target_allocated[sid].add(cname)

# 1b — ADR.governs_components  <-->  component.governed_by_adrs
adr_files = {}  # adr_id -> {file, frontmatter, frontmatter_text}
adr_text = {}   # adr_id -> full file text

if adrs_dir.exists():
    for f in sorted(adrs_dir.glob("ADR-*.md")):
        text = f.read_text()
        m = re.match(r"---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
        if not m:
            continue
        try:
            front = yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError:
            continue
        if isinstance(front, dict) and "id" in front:
            adr_files[front["id"]] = {
                "file": f,
                "frontmatter": front,
                "frontmatter_span": (m.start(1), m.end(1)),
            }
            adr_text[front["id"]] = text

target_governs = {aid: set() for aid in adr_files}
for aid, info in adr_files.items():
    for c in (info["frontmatter"].get("governs_components") or []):
        if isinstance(c, str):
            target_governs[aid].add(c)

target_governed_by = {cname: set() for cname in components}
for cname, c in components.items():
    if not isinstance(c, dict):
        continue
    for aid in (c.get("governed_by_adrs") or []):
        if isinstance(aid, str):
            target_governed_by[cname].add(aid)

# Reconcile to union.
for aid, info in adr_files.items():
    for cname in target_governs[aid]:
        if cname in target_governed_by:
            target_governed_by[cname].add(aid)
for cname, adrs in target_governed_by.items():
    for aid in adrs:
        if aid in target_governs:
            target_governs[aid].add(cname)

# 1c — ADR supersedes / superseded_by
target_supersedes = {aid: info["frontmatter"].get("supersedes") for aid, info in adr_files.items()}
target_superseded_by = {aid: info["frontmatter"].get("superseded_by") for aid, info in adr_files.items()}
# Mirror each declaration.
for aid, sup in list(target_supersedes.items()):
    if sup and sup in target_superseded_by:
        if target_superseded_by[sup] is None:
            target_superseded_by[sup] = aid
for aid, sb in list(target_superseded_by.items()):
    if sb and sb in target_supersedes:
        if target_supersedes[sb] is None:
            target_supersedes[sb] = aid

# ---------- Step 2: write component file (line-by-line) -------------------

def fmt_list(items):
    if not items:
        return "[]"
    return "[" + ", ".join(items) + "]"

def update_components_file():
    text = components_path.read_text()
    lines = text.split("\n")

    # State: which SYS-REQ or component are we currently in?
    cur_sys_req = None
    cur_component = None
    in_sys_req_block = False  # are we inside system_requirements:?
    in_components_block = False
    out = []

    sys_req_id_re = re.compile(r"^\s*-\s*id:\s*(SYS-REQ-[\w\-]+)\s*$")
    component_key_re = re.compile(r"^  ([\w-]+):\s*$")  # under "components:" - 2-space indent
    allocated_re = re.compile(r"^(\s*)allocated_to:\s*\[?.*\]?\s*$")
    governed_by_re = re.compile(r"^(\s*)governed_by_adrs:\s*\[?.*\]?\s*$")
    top_key_re = re.compile(r"^([\w-]+):\s*$")

    for i, line in enumerate(lines):
        # Top-level key transitions
        m_top = top_key_re.match(line)
        if m_top:
            top = m_top.group(1)
            if top == "system_requirements":
                in_sys_req_block = True
                in_components_block = False
                cur_sys_req = None
            elif top == "components":
                in_sys_req_block = False
                in_components_block = True
                cur_component = None
                cur_sys_req = None
            else:
                in_sys_req_block = False
                in_components_block = False
                cur_sys_req = None
                cur_component = None
            out.append(line)
            continue

        # SYS-REQ id detection
        if in_sys_req_block:
            m_id = sys_req_id_re.match(line)
            if m_id:
                cur_sys_req = m_id.group(1)
                out.append(line)
                continue
            # allocated_to rewrite
            m_alloc = allocated_re.match(line)
            if m_alloc and cur_sys_req:
                indent = m_alloc.group(1)
                desired = sorted(target_allocated.get(cur_sys_req, set()))
                new_line = f"{indent}allocated_to: {fmt_list(desired)}"
                if line.rstrip() != new_line.rstrip():
                    log("allocated_to", f"system_requirements[{cur_sys_req}]",
                        line.strip(), new_line.strip())
                out.append(new_line)
                continue
            out.append(line)
            continue

        # Component detection
        if in_components_block:
            m_comp = component_key_re.match(line)
            if m_comp and m_comp.group(1) in components:
                cur_component = m_comp.group(1)
                out.append(line)
                continue
            # governed_by_adrs rewrite (only if we're inside a known component)
            m_gov = governed_by_re.match(line)
            if m_gov and cur_component:
                indent = m_gov.group(1)
                desired = sorted(target_governed_by.get(cur_component, set()),
                                 key=lambda x: (int(re.search(r"\d+", x).group()) if re.search(r"\d+", x) else 0, x))
                new_line = f"{indent}governed_by_adrs: {fmt_list(desired)}"
                if line.rstrip() != new_line.rstrip():
                    log("governed_by_adrs", f"components.{cur_component}",
                        line.strip(), new_line.strip())
                out.append(new_line)
                continue
            out.append(line)
            continue

        out.append(line)

    new_text = "\n".join(out)
    if new_text != text:
        if not check_only:
            components_path.write_text(new_text)
        return True
    return False

# Also: append `governed_by_adrs:` to components that don't have it but need it.
# (When a new ADR's governs_components introduces a back-link to a component
# that had no governed_by_adrs line at all, we need to insert one.)
def insert_missing_governed_by_adrs():
    """For each component whose target set is non-empty but the line is absent,
    insert `governed_by_adrs: [...]` right after the `depends_on:` line."""
    text = components_path.read_text()
    lines = text.split("\n")
    out = []
    in_components_block = False
    cur_component = None
    cur_block_lines = []
    cur_block_has_field = False
    pending_insert = None  # (line_index_to_insert_after, new_line)

    component_key_re = re.compile(r"^  ([\w-]+):\s*$")
    governed_by_re = re.compile(r"^\s*governed_by_adrs:\s*")
    depends_on_re = re.compile(r"^(\s*)depends_on:\s*")
    top_key_re = re.compile(r"^([\w-]+):\s*$")

    inserts = []  # list of (index, new_line)
    for i, line in enumerate(lines):
        if top_key_re.match(line):
            in_components_block = (top_key_re.match(line).group(1) == "components")
            cur_component = None
            continue
        if in_components_block:
            m = component_key_re.match(line)
            if m and m.group(1) in components:
                cur_component = m.group(1)
                continue

    # Now find for each component whether it has governed_by_adrs already; if
    # not but target is non-empty, find the depends_on line and queue an insert.
    for cname in components:
        target = target_governed_by.get(cname, set())
        if not target:
            continue
        # Re-walk lines to find this component's block start and check for field
        block_start = None
        block_end = len(lines)
        in_block = False
        for i, line in enumerate(lines):
            if top_key_re.match(line):
                if top_key_re.match(line).group(1) == "components":
                    in_block = True
                else:
                    in_block = False
                continue
            if in_block:
                m = component_key_re.match(line)
                if m:
                    if m.group(1) == cname:
                        block_start = i
                    elif block_start is not None:
                        block_end = i
                        break
        if block_start is None:
            continue
        block_lines = lines[block_start:block_end]
        has_field = any(governed_by_re.match(l) for l in block_lines)
        if has_field:
            continue
        # Find depends_on inside the block; insert after it
        for rel, l in enumerate(block_lines):
            dm = depends_on_re.match(l)
            if dm:
                indent = dm.group(1)
                desired = sorted(target, key=lambda x: (int(re.search(r"\d+", x).group()) if re.search(r"\d+", x) else 0, x))
                new_line = f"{indent}governed_by_adrs: {fmt_list(desired)}"
                inserts.append((block_start + rel + 1, new_line))
                log("governed_by_adrs", f"components.{cname}", "(absent)", new_line.strip())
                break

    if not inserts:
        return False

    # Apply inserts (high-to-low index order to keep indices stable)
    inserts.sort(key=lambda x: -x[0])
    new_lines = lines[:]
    for idx, new_line in inserts:
        new_lines.insert(idx, new_line)
    new_text = "\n".join(new_lines)
    if new_text != text:
        if not check_only:
            components_path.write_text(new_text)
        return True
    return False

changed_components = update_components_file()
inserted_missing = insert_missing_governed_by_adrs()

# ---------- Step 3: ADR files — frontmatter edits ------------------------

def fmt_frontmatter_value(v):
    if v is None:
        return "null"
    return str(v)

def update_adr_file(aid):
    info = adr_files[aid]
    f = info["file"]
    text = adr_text[aid]
    fm_start, fm_end = info["frontmatter_span"]
    front_text = text[fm_start:fm_end]
    new_front = front_text

    # Update governs_components
    desired_gov = sorted(target_governs.get(aid, set()))
    gov_re = re.compile(r"^(governs_components:\s*)\[.*\]\s*$", re.MULTILINE)
    if gov_re.search(new_front):
        new_front = gov_re.sub(rf"\1{fmt_list(desired_gov)}", new_front)
    else:
        # missing line — add it before the closing of frontmatter (rare)
        new_front = new_front.rstrip() + f"\ngovers_components: {fmt_list(desired_gov)}\n"

    # Update supersedes / superseded_by
    new_sup = target_supersedes.get(aid)
    new_sb = target_superseded_by.get(aid)

    sup_re = re.compile(r"^(supersedes:\s*).*$", re.MULTILINE)
    sb_re = re.compile(r"^(superseded_by:\s*).*$", re.MULTILINE)
    if sup_re.search(new_front):
        new_front = sup_re.sub(rf"\1{fmt_frontmatter_value(new_sup)}", new_front)
    if sb_re.search(new_front):
        new_front = sb_re.sub(rf"\1{fmt_frontmatter_value(new_sb)}", new_front)

    if new_front != front_text:
        new_text = text[:fm_start] + new_front + text[fm_end:]
        # log per-field changes (best-effort by comparing originals)
        old_gov = set(info["frontmatter"].get("governs_components") or [])
        new_gov = set(desired_gov)
        if old_gov != new_gov:
            log("governs_components", f"adrs/{aid}",
                fmt_list(sorted(old_gov)), fmt_list(sorted(new_gov)))
        if info["frontmatter"].get("supersedes") != new_sup:
            log("supersedes", f"adrs/{aid}",
                str(info["frontmatter"].get("supersedes")), str(new_sup))
        if info["frontmatter"].get("superseded_by") != new_sb:
            log("superseded_by", f"adrs/{aid}",
                str(info["frontmatter"].get("superseded_by")), str(new_sb))
        if not check_only:
            f.write_text(new_text)
        return True
    return False

changed_adrs = 0
for aid in adr_files:
    if update_adr_file(aid):
        changed_adrs += 1

# ---------- Output --------------------------------------------------------

summary = {
    "mode": "check" if check_only else "apply",
    "changes": len(changes),
    "components_file_changed": changed_components or inserted_missing,
    "adr_files_changed": changed_adrs,
}

result = {"summary": summary, "changes": changes}

if emit_json:
    print(json.dumps(result, indent=2))
else:
    print(f"sync_spec_mirrors ({'check' if check_only else 'apply'}) — {len(changes)} change(s)")
    for ch in changes:
        print(f"  [{ch['kind']:18s}] {ch['path']}")
        print(f"      before: {ch['before']}")
        print(f"      after : {ch['after']}")
    if not changes:
        print("OK — already in sync.")

# In --check mode, exit 1 on any drift
sys.exit(1 if (check_only and changes) else 0)
PYEOF
