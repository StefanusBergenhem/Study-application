#!/usr/bin/env bash
#
# render_spec_html.sh — Render the project's spec layer as one self-contained
# interactive HTML document.
#
# User-facing. Owned by wf-skill-init, which copies this script (and its
# assets/ siblings) into .workflow/scripts/ during set-up. End-users invoke
# it directly:
#
#   ./.workflow/scripts/render_spec_html.sh
#
# Inputs (resolved in this order: CLI flag → config → default):
#   --config <path>             defaults to .workflow/config.yaml
#   --components <path>         defaults to paths.components in config
#   --adrs <dir|file>           defaults to paths.adrs in config (dir of *.md
#                               with YAML frontmatter)
#   --out <path>                defaults to paths.architecture_html in config,
#                               else .workflow/.transient/architecture.html
#   --title <str>               defaults to project.name in config
#
# Outputs:
#   - One self-contained HTML file at --out (CSS + JS + Mermaid inlined).
#
# Exit codes:
#   0 = rendered
#   2 = configuration / input error
#
# Dependencies: python3 with PyYAML.
# Project-agnostic: the script reads only fields defined by the wf SA template
# (components.yaml.tmpl + adr.md.tmpl) and emits a generic architecture page.
#
# Asset resolution: probes (in order)
#   1. $WF_RENDER_ASSETS                              (env override)
#   2. $SCRIPT_DIR/assets/                            (copied into .workflow/scripts/)
#   3. $SCRIPT_DIR/../assets/                         (running from wf source layout)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_assets_dir() {
    local probe
    if [[ -n "${WF_RENDER_ASSETS:-}" && -d "$WF_RENDER_ASSETS" ]]; then
        (cd "$WF_RENDER_ASSETS" && pwd); return 0
    fi
    for probe in "$SCRIPT_DIR/assets" "$SCRIPT_DIR/../assets"; do
        if [[ -f "$probe/architecture.html.tmpl" ]]; then
            (cd "$probe" && pwd); return 0
        fi
    done
    return 1
}

if ! ASSETS_DIR="$(resolve_assets_dir)"; then
    echo "error: could not locate architecture assets (architecture.html.tmpl, architecture.css, architecture.js)" >&2
    echo "       looked in: \$WF_RENDER_ASSETS, $SCRIPT_DIR/assets, $SCRIPT_DIR/../assets" >&2
    echo "       if you copied this script manually, also copy the assets/ sibling directory." >&2
    exit 2
fi

CONFIG_PATH=".workflow/config.yaml"
COMPONENTS_OVERRIDE=""
ADRS_OVERRIDE=""
OUT_OVERRIDE=""
TITLE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG_PATH="$2"; shift 2 ;;
        --components) COMPONENTS_OVERRIDE="$2"; shift 2 ;;
        --adrs)       ADRS_OVERRIDE="$2"; shift 2 ;;
        --out)        OUT_OVERRIDE="$2"; shift 2 ;;
        --title)      TITLE_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# render_spec_html\.sh/,/^set -euo pipefail/p' "$0" | sed '$d'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required" >&2
    exit 2
fi

export WF_RENDER_CONFIG="$CONFIG_PATH"
export WF_RENDER_COMPONENTS="$COMPONENTS_OVERRIDE"
export WF_RENDER_ADRS="$ADRS_OVERRIDE"
export WF_RENDER_OUT="$OUT_OVERRIDE"
export WF_RENDER_TITLE="$TITLE_OVERRIDE"
export WF_RENDER_ASSETS="$ASSETS_DIR"

exec python3 - <<'PYEOF'
import datetime
import hashlib
import html
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


# ─── Inputs ─────────────────────────────────────────────────────────────────

config_path_str = os.environ.get("WF_RENDER_CONFIG") or ".workflow/config.yaml"
components_override = os.environ.get("WF_RENDER_COMPONENTS") or ""
adrs_override = os.environ.get("WF_RENDER_ADRS") or ""
out_override = os.environ.get("WF_RENDER_OUT") or ""
title_override = os.environ.get("WF_RENDER_TITLE") or ""
assets_dir = Path(os.environ.get("WF_RENDER_ASSETS") or ".").resolve()

config_path = Path(config_path_str)
project_root = Path.cwd().resolve()

config = {}
if config_path.exists():
    try:
        config = yaml.safe_load(config_path.read_text()) or {}
    except yaml.YAMLError as exc:
        sys.stderr.write(f"error: failed to parse {config_path}: {exc}\n")
        sys.exit(2)
    # If config was found inside a .workflow/ dir, treat its parent's parent as root.
    if config_path.is_absolute():
        cp = config_path.resolve()
        if cp.parent.name == ".workflow":
            project_root = cp.parent.parent

paths = (config.get("paths") or {})
project = (config.get("project") or {})

def resolve(p):
    if not p:
        return None
    pp = Path(p)
    return pp if pp.is_absolute() else (project_root / pp).resolve()

components_path = resolve(components_override) or resolve(paths.get("components"))
adrs_path       = resolve(adrs_override)       or resolve(paths.get("adrs"))
out_path        = resolve(out_override)        or resolve(paths.get("architecture_html")) \
                                               or (project_root / ".workflow" / ".transient" / "architecture.html")
title           = title_override or project.get("name") or project_root.name

if not components_path or not components_path.exists():
    sys.stderr.write(f"error: components file not found: {components_path}\n")
    sys.exit(2)

raw_components = components_path.read_text()
try:
    spec = yaml.safe_load(raw_components) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {components_path}: {exc}\n")
    sys.exit(2)

components_sha = hashlib.sha256(raw_components.encode("utf-8")).hexdigest()

sys_reqs    = spec.get("system_requirements") or []
components  = spec.get("components") or {}
conventions = spec.get("conventions") or []
dep_rules   = spec.get("dependency_rules") or []


# ─── ADR loading ─────────────────────────────────────────────────────────────

adrs = []  # list of dicts: { id, status, title, date, governs_components, traces_to, supersedes, superseded_by, body_md, path }

def parse_frontmatter(text):
    """Return (frontmatter_dict, body_str). If no frontmatter, returns ({}, text)."""
    if not text.startswith("---"):
        return {}, text
    # Find closing ---
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, flags=re.DOTALL)
    if not m:
        return {}, text
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        fm = {}
    return fm, m.group(2)

if adrs_path:
    if adrs_path.is_dir():
        adr_files = sorted(adrs_path.glob("*.md")) + sorted(adrs_path.glob("*.MD"))
    elif adrs_path.is_file():
        adr_files = [adrs_path]
    else:
        adr_files = []

    for ap in adr_files:
        try:
            text = ap.read_text()
        except OSError:
            continue
        fm, body = parse_frontmatter(text)
        adr_id = str(fm.get("id") or ap.stem).strip()
        adrs.append({
            "id": adr_id,
            "status": str(fm.get("status") or "").strip(),
            "title": str(fm.get("title") or adr_id).strip(),
            "date": str(fm.get("date") or "").strip(),
            "governs_components": fm.get("governs_components") or [],
            "traces_to": fm.get("traces_to") or [],
            "supersedes": fm.get("supersedes"),
            "superseded_by": fm.get("superseded_by"),
            "body_md": body,
            "path": str(ap.relative_to(project_root)) if ap.is_relative_to(project_root) else str(ap),
        })
    # Order by id numeric where possible
    def adr_sort_key(a):
        m = re.match(r"ADR-(\d+)", a["id"])
        return (0, int(m.group(1))) if m else (1, a["id"])
    adrs.sort(key=adr_sort_key)


# ─── Helpers: anchor IDs, ref recognisers, escapes ───────────────────────────

def slug(s):
    return re.sub(r"[^a-z0-9_-]+", "-", str(s).lower()).strip("-")

def comp_anchor(name):   return f"comp-{slug(name)}"
def req_anchor(req_id):  return slug(req_id)   # REQ-AUTH-001 → req-auth-001
def conv_anchor(cid):    return slug(cid)      # CONV-001 → conv-001
def adr_anchor(adr_id):  return slug(adr_id)   # ADR-007 → adr-007
def sys_req_anchor(rid): return slug(rid)      # sys-req-001

def esc(s):
    return html.escape("" if s is None else str(s), quote=True)

# Recognise references inside arbitrary text. Order matters: SYS-REQ before REQ.
ID_PATTERNS = [
    ("sys-req",        re.compile(r"\bSYS-REQ-\d+\b")),
    ("req",            re.compile(r"\bREQ-[A-Z0-9][A-Z0-9_-]*-\d+\b")),
    ("conv",           re.compile(r"\bCONV-\d+\b")),
    ("adr",            re.compile(r"\bADR-\d+\b")),
    ("capability",     re.compile(r"\bCAP-\d+\b")),
    ("ext-constraint", re.compile(r"\bEXT-\d+\b")),
]

# Pre-built sets of known ids for `broken` detection
KNOWN_IDS = set()
KNOWN_COMPONENTS = set(components.keys())


# ─── Index building ──────────────────────────────────────────────────────────

# nodes: id → { kind, title, summary, anchor, owner_component? }
nodes = {}
# forward edges: src_id → set of dst_id (for backlink computation)
edges = []
# kind labels (for popover badge)
KIND_LABELS = {
    "sys-req": "system req",
    "req": "requirement",
    "conv": "convention",
    "adr": "ADR",
    "comp": "component",
    "capability": "capability",
    "ext-constraint": "external constraint",
}

def add_node(node_id, kind, title="", summary="", anchor=None, owner=None):
    if not node_id:
        return
    if node_id in nodes:
        return
    nodes[node_id] = {
        "kind": kind,
        "title": title[:240],
        "summary": (summary or "")[:300],
        "anchor": anchor or slug(node_id),
        "owner_component": owner,
    }
    KNOWN_IDS.add(node_id)

# Components
for cname, spec_block in components.items():
    spec_block = spec_block or {}
    add_node(cname, "comp",
             title=cname,
             summary=(spec_block.get("path") or "") + (" · " + spec_block.get("status", "") if spec_block.get("status") else ""),
             anchor=comp_anchor(cname))

# SYS-REQs
for sr in sys_reqs:
    if not isinstance(sr, dict):
        continue
    sid = sr.get("id")
    add_node(sid, "sys-req",
             title=sr.get("type", "").upper(),
             summary=sr.get("statement", ""),
             anchor=sys_req_anchor(sid))

# Conventions (CONV-NNN)
for conv in conventions:
    if not isinstance(conv, dict):
        continue
    cid = conv.get("id")
    add_node(cid, "conv",
             title=conv.get("enforced_by", "").upper(),
             summary=conv.get("rule", ""),
             anchor=conv_anchor(cid))

# Component REQs
for cname, spec_block in components.items():
    spec_block = spec_block or {}
    for req in (spec_block.get("requirements") or []):
        if not isinstance(req, dict):
            continue
        rid = req.get("id")
        add_node(rid, "req",
                 title=req.get("type", "").upper(),
                 summary=req.get("statement", ""),
                 anchor=req_anchor(rid),
                 owner=cname)

# ADRs
for adr in adrs:
    add_node(adr["id"], "adr",
             title=adr.get("title", ""),
             summary=adr.get("status", ""),
             anchor=adr_anchor(adr["id"]))


# ─── Reference rendering ────────────────────────────────────────────────────

def render_ref(rid, kind=None):
    """Render a single ID reference as a clickable <a>. Marks broken if unknown."""
    rid = str(rid).strip()
    if not rid:
        return ""
    # Detect kind if not supplied
    if kind is None:
        for k, pat in ID_PATTERNS:
            if pat.fullmatch(rid):
                kind = k
                break
        if kind is None:
            kind = "capability"
    node = nodes.get(rid)
    if node:
        cls = f"ref ref-{kind}"
        href = "#" + node["anchor"]
        return f'<a class="{cls}" href="{esc(href)}" data-ref="{esc(rid)}">{esc(rid)}</a>'
    else:
        cls = f"ref ref-{kind} broken"
        return f'<a class="{cls}" title="not found in spec" data-ref="{esc(rid)}">{esc(rid)}</a>'

def render_comp_ref(name):
    """Render a component-name reference."""
    name = str(name).strip()
    if not name:
        return ""
    if name in KNOWN_COMPONENTS:
        return f'<a class="ref ref-comp" href="#{comp_anchor(name)}" data-ref="{esc(name)}">{esc(name)}</a>'
    return f'<span class="ref ref-comp broken">{esc(name)}</span>'

def linkify_text(text):
    """Linkify all known ID patterns in a free-text body. HTML-escapes first."""
    if not text:
        return ""
    text = html.escape(str(text), quote=False)
    # Replace ID patterns. Build a regex that matches any kind, longest-first.
    combined = re.compile(
        r"\b(SYS-REQ-\d+|REQ-[A-Z0-9][A-Z0-9_-]*-\d+|CONV-\d+|ADR-\d+|CAP-\d+|EXT-\d+)\b"
    )
    def repl(m):
        s = m.group(0)
        # Determine kind
        if s.startswith("SYS-REQ-"): k = "sys-req"
        elif s.startswith("REQ-"):    k = "req"
        elif s.startswith("CONV-"):   k = "conv"
        elif s.startswith("ADR-"):    k = "adr"
        elif s.startswith("CAP-"):    k = "capability"
        elif s.startswith("EXT-"):    k = "ext-constraint"
        else:                          k = "capability"
        return render_ref(s, k)
    return combined.sub(repl, text)


# ─── Edges (for backlinks) ──────────────────────────────────────────────────

def add_edge(src, dst):
    if not src or not dst:
        return
    src = str(src); dst = str(dst)
    if src == dst:
        return
    edges.append((src, dst))

# SYS-REQ → allocated_to → component
for sr in sys_reqs:
    if not isinstance(sr, dict): continue
    for c in (sr.get("allocated_to") or []):
        add_edge(sr.get("id"), c)
    for t in (sr.get("traces_to") or []):
        add_edge(sr.get("id"), t)

# component REQ → derives_from / traces_to
for cname, spec_block in components.items():
    spec_block = spec_block or {}
    for adr_id in (spec_block.get("governed_by_adrs") or []):
        add_edge(cname, adr_id)
    for dep in (spec_block.get("depends_on") or []):
        add_edge(cname, dep)
    for req in (spec_block.get("requirements") or []):
        if not isinstance(req, dict): continue
        for df in (req.get("derives_from") or []):
            add_edge(req.get("id"), df)
        for t in (req.get("traces_to") or []):
            add_edge(req.get("id"), t)

# Convention → traces_to (typically ADRs)
for conv in conventions:
    if not isinstance(conv, dict): continue
    for t in (conv.get("traces_to") or []):
        add_edge(conv.get("id"), t)

# ADR → governs_components / traces_to
for adr in adrs:
    for c in (adr.get("governs_components") or []):
        add_edge(adr["id"], c)
    for t in (adr.get("traces_to") or []):
        add_edge(adr["id"], t)

# Build backlinks: dst → list of src
backlinks = {}
for src, dst in edges:
    backlinks.setdefault(dst, []).append(src)


# ─── HTML fragment renderers ────────────────────────────────────────────────

def render_ac_list(items):
    if not items: return ""
    lis = "".join(f"<li>{linkify_text(i)}</li>" for i in items)
    return f"<ul>{lis}</ul>"

def render_chip_list(items, renderer):
    if not items: return '<span style="color:var(--ink-mute);font-style:italic;font-size:12.5px;">none</span>'
    return "".join(renderer(i) for i in items)

def render_backlinks_for(node_id):
    refs = backlinks.get(node_id) or []
    if not refs:
        return ""
    refs_unique = []
    seen = set()
    for r in refs:
        if r in seen: continue
        seen.add(r)
        refs_unique.append(r)
    chips = []
    for r in refs_unique:
        if r in KNOWN_COMPONENTS:
            chips.append(render_comp_ref(r))
        else:
            chips.append(render_ref(r))
    return (
        '<div class="backlinks">'
        '<div class="label">Referenced by</div>'
        f'<div class="refs">{" ".join(chips)}</div>'
        '</div>'
    )

def render_kind_badge(req_type):
    rt = (req_type or "").lower()
    return f'<span class="kind k-{esc(rt)}">{esc(rt)}</span>' if rt else ""

def render_status_pill(status):
    s = (status or "").lower()
    if not s: return ""
    return f'<span class="status-pill {esc(s)}">{esc(s)}</span>'

def render_sys_req(sr):
    if not isinstance(sr, dict): return ""
    sid = sr.get("id", "?")
    rtype = sr.get("type", "")
    statement = linkify_text(sr.get("statement", ""))
    ac = sr.get("acceptance_criteria") or []
    allocated = sr.get("allocated_to") or []
    traces = sr.get("traces_to") or []
    nfr = sr.get("nfr_elements") or {}
    parts = []
    parts.append(f'<article class="entry" id="{sys_req_anchor(sid)}" data-search-text="{esc(sid + " " + (sr.get("statement") or ""))}">')
    parts.append('<header>')
    parts.append(f'<h3>{esc(sid)}</h3>')
    parts.append(render_kind_badge(rtype))
    parts.append(f'<a class="anchor-id" href="#{sys_req_anchor(sid)}">#</a>')
    parts.append('</header>')
    parts.append(f'<div class="statement">{statement}</div>')
    parts.append('<dl class="detail">')
    if ac:
        parts.append('<dt>Acceptance</dt><dd>' + render_ac_list(ac) + '</dd>')
    if nfr:
        nfr_items = [f'<li><strong>{esc(k)}</strong>: {linkify_text(v)}</li>' for k, v in nfr.items()]
        parts.append('<dt>NFR shape</dt><dd><ul>' + "".join(nfr_items) + '</ul></dd>')
    if allocated:
        parts.append('<dt>Allocated to</dt><dd>' + render_chip_list(allocated, render_comp_ref) + '</dd>')
    if traces:
        parts.append('<dt>Traces to</dt><dd>' + render_chip_list(traces, render_ref) + '</dd>')
    parts.append('</dl>')
    parts.append(render_backlinks_for(sid))
    parts.append('</article>')
    return "\n".join(parts)

def render_exposes_item(item):
    """Render an `exposes` entry: bare string OR DbC contract block."""
    if isinstance(item, str):
        return f'<code>{esc(item)}</code>'
    if not isinstance(item, dict):
        return f'<code>{esc(str(item))}</code>'
    name = item.get("name", "?")
    sig = item.get("signature") or {}
    style = item.get("style", "")
    pre = item.get("preconditions") or []
    post = item.get("postconditions") or {}
    inv = item.get("invariants") or []
    errors = item.get("typed_errors") or []
    # Build signature line
    sig_line = ""
    if isinstance(sig, dict):
        params = sig.get("parameters") or []
        if isinstance(params, list):
            ps = []
            for p in params:
                if isinstance(p, dict):
                    ps.append(f"{p.get('name','')}: {p.get('type','')}".strip(": "))
                else:
                    ps.append(str(p))
            ret = sig.get("return_type", "")
            sig_line = f"({', '.join(ps)})"
            if ret: sig_line += " → " + ret
    style_tag = f' <span style="color:var(--ink-mute);font-size:11px;">[{esc(style)}]</span>' if style else ""

    out = ['<div class="contract">']
    out.append(f'<div class="contract-name">{esc(name)}{style_tag}</div>')
    if sig_line:
        out.append(f'<div class="contract-sig">{esc(sig_line)}</div>')
    if pre:
        out.append('<div class="clause-label">Preconditions</div><ul>')
        for p in pre: out.append(f'<li>{linkify_text(p)}</li>')
        out.append('</ul>')
    if isinstance(post, dict):
        for branch, clauses in post.items():
            if not clauses: continue
            out.append(f'<div class="clause-label">Postconditions · {esc(branch)}</div><ul>')
            for c in clauses: out.append(f'<li>{linkify_text(c)}</li>')
            out.append('</ul>')
    elif isinstance(post, list) and post:
        out.append('<div class="clause-label">Postconditions</div><ul>')
        for c in post: out.append(f'<li>{linkify_text(c)}</li>')
        out.append('</ul>')
    if inv:
        out.append('<div class="clause-label">Invariants</div><ul>')
        for c in inv: out.append(f'<li>{linkify_text(c)}</li>')
        out.append('</ul>')
    if errors:
        out.append('<div class="clause-label">Typed errors</div><ul>')
        for e in errors:
            if isinstance(e, dict):
                out.append(f'<li><code>{esc(e.get("name",""))}</code> — {linkify_text(e.get("when",""))}</li>')
            else:
                out.append(f'<li><code>{esc(str(e))}</code></li>')
        out.append('</ul>')
    out.append('</div>')
    return "\n".join(out)

def render_component_req(req, owner):
    rid = req.get("id", "?")
    statement = linkify_text(req.get("statement", ""))
    parts = []
    parts.append(f'<div class="sub-entry" id="{req_anchor(rid)}" data-search-text="{esc(rid + " " + (req.get("statement") or ""))}">')
    parts.append('<header>')
    parts.append(f'<strong style="font-family:var(--font-mono);font-size:12.5px;letter-spacing:0.04em;">{esc(rid)}</strong>')
    parts.append(render_kind_badge(req.get("type")))
    parts.append(f'<a class="anchor-id" href="#{req_anchor(rid)}">#</a>')
    parts.append('</header>')
    parts.append(f'<div class="statement">{statement}</div>')
    parts.append('<dl class="detail">')
    ac = req.get("acceptance_criteria") or []
    if ac:
        parts.append('<dt>Acceptance</dt><dd>' + render_ac_list(ac) + '</dd>')
    nfr = req.get("nfr_elements") or {}
    if nfr:
        nfr_items = [f'<li><strong>{esc(k)}</strong>: {linkify_text(v)}</li>' for k, v in nfr.items()]
        parts.append('<dt>NFR shape</dt><dd><ul>' + "".join(nfr_items) + '</ul></dd>')
    df = req.get("derives_from") or []
    if df:
        parts.append('<dt>Derives from</dt><dd>' + render_chip_list(df, render_ref) + '</dd>')
    tr = req.get("traces_to") or []
    if tr:
        parts.append('<dt>Traces to</dt><dd>' + render_chip_list(tr, render_ref) + '</dd>')
    parts.append('</dl>')
    bl = render_backlinks_for(rid)
    if bl: parts.append(bl)
    parts.append('</div>')
    return "\n".join(parts)

def render_convention(conv):
    """Render a single convention entry."""
    if not isinstance(conv, dict):
        return ""
    cid = conv.get("id", "?")
    rule = conv.get("rule", "")
    rationale = conv.get("rationale", "")
    enforced_by = conv.get("enforced_by", "")
    applies_to = conv.get("applies_to") or []
    traces = conv.get("traces_to") or []
    parts = []
    parts.append(f'<article class="entry" id="{conv_anchor(cid)}" data-search-text="{esc(cid + " " + rule + " " + rationale)}">')
    parts.append('<header>')
    parts.append(f'<h3>{esc(cid)}</h3>')
    if enforced_by:
        parts.append(f'<span class="kind k-{esc(enforced_by)}">{esc(enforced_by)}</span>')
    parts.append(f'<a class="anchor-id" href="#{conv_anchor(cid)}">#</a>')
    parts.append('</header>')
    parts.append(f'<div class="statement">{linkify_text(rule)}</div>')
    parts.append('<dl class="detail">')
    if rationale:
        parts.append(f'<dt>Why</dt><dd>{linkify_text(rationale)}</dd>')
    if applies_to:
        chips = "".join(f'<code style="font-family:var(--font-mono);font-size:12px;background:var(--rule-soft);padding:1px 6px;margin-right:4px;">{esc(p)}</code>' for p in applies_to)
        parts.append(f'<dt>Applies to</dt><dd>{chips}</dd>')
    if traces:
        parts.append('<dt>Traces to</dt><dd>' + render_chip_list(traces, render_ref) + '</dd>')
    parts.append('</dl>')
    bl = render_backlinks_for(cid)
    if bl: parts.append(bl)
    parts.append('</article>')
    return "\n".join(parts)


def render_component(name, spec_block):
    spec_block = spec_block or {}
    path = spec_block.get("path", "")
    status = spec_block.get("status", "")
    reqs = spec_block.get("requirements") or []
    exposes = spec_block.get("exposes") or []
    deps = spec_block.get("depends_on") or []
    adrs_g = spec_block.get("governed_by_adrs") or []
    constraints = spec_block.get("constraints") or {}
    notes = spec_block.get("notes", "")

    search_haystack = name + " " + path + " " + " ".join(
        (r.get("statement") or "") for r in reqs if isinstance(r, dict)
    )

    parts = []
    parts.append(f'<article class="entry" id="{comp_anchor(name)}" data-search-text="{esc(search_haystack)}">')
    parts.append('<header>')
    parts.append(f'<h3><em>{esc(name)}</em></h3>')
    if path:
        parts.append(f'<code style="font-family:var(--font-mono);font-size:12px;color:var(--ink-mute);">{esc(path)}</code>')
    parts.append(render_status_pill(status))
    parts.append(f'<a class="anchor-id" href="#{comp_anchor(name)}">#</a>')
    parts.append('</header>')

    parts.append('<dl class="detail">')
    if deps:
        parts.append('<dt>Depends on</dt><dd>' + render_chip_list(deps, render_comp_ref) + '</dd>')
    if adrs_g:
        parts.append('<dt>Governed by</dt><dd>' + render_chip_list(adrs_g, render_ref) + '</dd>')
    if constraints:
        items = ", ".join(f"{esc(k)}={esc(v)}" for k, v in constraints.items())
        parts.append(f'<dt>Constraints</dt><dd><code>{items}</code></dd>')
    if notes:
        parts.append(f'<dt>Notes</dt><dd>{linkify_text(notes)}</dd>')
    parts.append('</dl>')

    if exposes:
        parts.append('<div style="margin-top:18px;">')
        parts.append('<h4 style="font-family:var(--font-mono);font-size:11px;letter-spacing:0.18em;text-transform:uppercase;color:var(--ink-mute);margin:0 0 8px;font-weight:600;">Exposes</h4>')
        bare = [e for e in exposes if isinstance(e, str)]
        rich = [e for e in exposes if isinstance(e, dict)]
        if bare:
            parts.append('<div style="margin-bottom:10px;display:flex;flex-wrap:wrap;gap:6px;">')
            for s in bare: parts.append(f'<code style="font-family:var(--font-mono);font-size:12.5px;background:var(--rule-soft);padding:2px 7px;">{esc(s)}</code>')
            parts.append('</div>')
        for r in rich:
            parts.append(render_exposes_item(r))
        parts.append('</div>')

    if reqs:
        parts.append('<div class="subentries">')
        parts.append(f'<h4>Requirements · {len(reqs)}</h4>')
        for r in reqs:
            if isinstance(r, dict):
                parts.append(render_component_req(r, name))
        parts.append('</div>')

    bl = render_backlinks_for(name)
    if bl: parts.append(bl)
    parts.append('</article>')
    return "\n".join(parts)


# ─── Tiny markdown → HTML for ADR bodies ────────────────────────────────────

def md_inline(text):
    """Inline formatting: code, strong, em, links. Operates on already-escaped text segments."""
    # Inline code first (so we don't process *inside* it)
    out = []
    parts = re.split(r"(`[^`]+`)", text)
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) >= 2:
            out.append(f'<code>{html.escape(part[1:-1])}</code>')
        else:
            seg = html.escape(part)
            seg = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", seg)
            seg = re.sub(r"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)", r"<em>\1</em>", seg)
            seg = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', seg)
            # Linkify IDs after markdown
            seg = re.sub(
                r"\b(SYS-REQ-\d+|REQ-[A-Z0-9][A-Z0-9_-]*-\d+|CONV-\d+|ADR-\d+|E\d+\.[FN][A-Z]?-?\d+|E\d+)\b",
                lambda m: render_ref(m.group(0)),
                seg,
            )
            out.append(seg)
    return "".join(out)

def md_to_html(md):
    """Minimal markdown renderer covering what ADRs use."""
    if not md:
        return ""
    lines = md.splitlines()
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Fenced code block
        m = re.match(r"^```(\S*)\s*$", line)
        if m:
            i += 1
            code_lines = []
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # consume closing ```
            out.append("<pre><code>" + html.escape("\n".join(code_lines)) + "</code></pre>")
            continue
        # Heading
        h = re.match(r"^(#{1,6})\s+(.*)$", line)
        if h:
            level = len(h.group(1))
            out.append(f"<h{level}>{md_inline(h.group(2))}</h{level}>")
            i += 1
            continue
        # Horizontal rule
        if re.match(r"^---+\s*$", line) or re.match(r"^\*\*\*+\s*$", line):
            out.append("<hr>")
            i += 1
            continue
        # Blockquote
        if line.startswith(">"):
            block = []
            while i < len(lines) and lines[i].startswith(">"):
                block.append(lines[i].lstrip(">").lstrip())
                i += 1
            out.append("<blockquote>" + md_inline(" ".join(block)) + "</blockquote>")
            continue
        # Unordered list
        if re.match(r"^[-*+]\s+", line):
            items = []
            while i < len(lines) and re.match(r"^[-*+]\s+", lines[i]):
                items.append(re.sub(r"^[-*+]\s+", "", lines[i]))
                i += 1
            out.append("<ul>" + "".join(f"<li>{md_inline(x)}</li>" for x in items) + "</ul>")
            continue
        # Ordered list
        if re.match(r"^\d+\.\s+", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\.\s+", lines[i]):
                items.append(re.sub(r"^\d+\.\s+", "", lines[i]))
                i += 1
            out.append("<ol>" + "".join(f"<li>{md_inline(x)}</li>" for x in items) + "</ol>")
            continue
        # Blank line
        if not line.strip():
            i += 1
            continue
        # Paragraph (gather until blank)
        para = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and \
              not re.match(r"^(#{1,6}\s|[-*+]\s|\d+\.\s|>|```|---+\s*$)", lines[i]):
            para.append(lines[i])
            i += 1
        out.append("<p>" + md_inline(" ".join(para)) + "</p>")
    return "\n".join(out)


# ─── ADR section rendering ──────────────────────────────────────────────────

def render_adr(adr):
    aid = adr["id"]
    parts = []
    search_haystack = aid + " " + (adr.get("title") or "") + " " + (adr.get("body_md") or "")[:500]
    parts.append(f'<article class="entry" id="{adr_anchor(aid)}" data-search-text="{esc(search_haystack)}">')
    parts.append('<header>')
    parts.append(f'<h3>{esc(aid)} · <em>{esc(adr.get("title", ""))}</em></h3>')
    parts.append(render_status_pill(adr.get("status", "")))
    if adr.get("date"):
        parts.append(f'<span style="font-family:var(--font-mono);font-size:11px;color:var(--ink-mute);">{esc(adr["date"])}</span>')
    parts.append(f'<a class="anchor-id" href="#{adr_anchor(aid)}">#</a>')
    parts.append('</header>')
    parts.append('<dl class="detail">')
    gc = adr.get("governs_components") or []
    if gc:
        parts.append('<dt>Governs</dt><dd>' + render_chip_list(gc, render_comp_ref) + '</dd>')
    tr = adr.get("traces_to") or []
    if tr:
        parts.append('<dt>Traces to</dt><dd>' + render_chip_list(tr, render_ref) + '</dd>')
    if adr.get("supersedes"):
        parts.append('<dt>Supersedes</dt><dd>' + render_ref(adr["supersedes"]) + '</dd>')
    if adr.get("superseded_by"):
        parts.append('<dt>Superseded by</dt><dd>' + render_ref(adr["superseded_by"]) + '</dd>')
    if adr.get("path"):
        parts.append(f'<dt>Source</dt><dd><code>{esc(adr["path"])}</code></dd>')
    parts.append('</dl>')
    parts.append('<div class="adr-body">' + md_to_html(adr.get("body_md") or "") + '</div>')
    bl = render_backlinks_for(aid)
    if bl: parts.append(bl)
    parts.append('</article>')
    return "\n".join(parts)


# ─── Mermaid diagram ────────────────────────────────────────────────────────

def build_mermaid():
    if not components:
        return "graph LR\n  empty[no components]"
    out = ["graph LR"]
    # Nodes
    for cname in components.keys():
        nid = "n_" + re.sub(r"[^a-zA-Z0-9_]", "_", cname)
        out.append(f'  {nid}["{cname}"]')
    # Edges
    name_to_id = {c: "n_" + re.sub(r"[^a-zA-Z0-9_]", "_", c) for c in components.keys()}
    for cname, spec_block in components.items():
        spec_block = spec_block or {}
        for dep in (spec_block.get("depends_on") or []):
            if dep in name_to_id:
                out.append(f"  {name_to_id[cname]} --> {name_to_id[dep]}")
    return "\n".join(out)


# ─── Navigation rail ────────────────────────────────────────────────────────

def build_nav():
    parts = []
    parts.append('<h3>Sections</h3><ul>')
    parts.append('<li><a href="#overview">Overview</a></li>')
    parts.append(f'<li><a href="#system-requirements">System requirements <span class="count">{len(sys_reqs)}</span></a></li>')
    if conventions:
        parts.append(f'<li><a href="#conventions">Conventions <span class="count">{len(conventions)}</span></a></li>')
    parts.append(f'<li><a href="#components">Components <span class="count">{len(components)}</span></a></li>')
    parts.append(f'<li><a href="#adrs">ADRs <span class="count">{len(adrs)}</span></a></li>')
    parts.append('</ul>')

    if sys_reqs:
        parts.append('<h3>System reqs</h3><ul>')
        for sr in sys_reqs:
            if not isinstance(sr, dict): continue
            sid = sr.get("id", "?")
            parts.append(f'<li><a href="#{sys_req_anchor(sid)}">{esc(sid)}</a></li>')
        parts.append('</ul>')

    if conventions:
        parts.append('<h3>Conventions</h3><ul>')
        for conv in conventions:
            if not isinstance(conv, dict): continue
            cid = conv.get("id", "?")
            parts.append(f'<li><a href="#{conv_anchor(cid)}">{esc(cid)}</a></li>')
        parts.append('</ul>')

    if components:
        parts.append('<h3>Components</h3><ul>')
        for cname, spec_block in components.items():
            spec_block = spec_block or {}
            count = len(spec_block.get("requirements") or [])
            count_html = f' <span class="count">{count}</span>' if count else ""
            parts.append(f'<li><a href="#{comp_anchor(cname)}">{esc(cname)}{count_html}</a></li>')
        parts.append('</ul>')

    if adrs:
        parts.append('<h3>ADRs</h3><ul>')
        for adr in adrs:
            parts.append(f'<li><a href="#{adr_anchor(adr["id"])}">{esc(adr["id"])} · {esc(adr["title"][:48])}</a></li>')
        parts.append('</ul>')

    return "\n".join(parts)


# ─── Overview cards + subhead ───────────────────────────────────────────────

req_count = sum(len((c or {}).get("requirements") or []) for c in components.values())

def card(label, value, sub=""):
    sub_html = f'<span class="sub">{esc(sub)}</span>' if sub else ""
    return f'<div class="card"><div class="label">{esc(label)}</div><div class="val">{esc(value)}{sub_html}</div></div>'

overview_cards = "".join([
    card("Components",    str(len(components))),
    card("System reqs",   str(len(sys_reqs))),
    card("Component reqs",str(req_count)),
    card("Conventions",   str(len(conventions))),
    card("ADRs",          str(len(adrs))),
    card("Dep. rules",    str(len(dep_rules))),
])

# Status mix in subhead
status_counts = {}
for c in components.values():
    s = ((c or {}).get("status") or "unknown").upper()
    status_counts[s] = status_counts.get(s, 0) + 1
subhead_parts = []
for s, n in sorted(status_counts.items(), key=lambda x: -x[1]):
    subhead_parts.append(f'<div class="stat"><strong>{n}</strong>{esc(s)}</div>')
adr_status_counts = {}
for a in adrs:
    s = (a.get("status") or "unknown").upper()
    adr_status_counts[s] = adr_status_counts.get(s, 0) + 1
for s, n in sorted(adr_status_counts.items(), key=lambda x: -x[1]):
    subhead_parts.append(f'<div class="stat"><strong>{n}</strong>ADR {esc(s)}</div>')

subhead_html = "\n".join(subhead_parts) or '<div class="stat">no status data</div>'


# ─── Dependency rules block ─────────────────────────────────────────────────

def render_dep_rules():
    if not dep_rules: return ""
    items = "".join(f"<li>{linkify_text(r)}</li>" for r in dep_rules)
    return (
        '<div style="margin-top:24px;">'
        '<h4 style="font-family:var(--font-mono);font-size:11px;letter-spacing:0.18em;text-transform:uppercase;color:var(--ink-mute);margin:0 0 8px;font-weight:600;">Dependency rules</h4>'
        f'<ul style="margin:0;padding-left:18px;">{items}</ul>'
        '</div>'
    )


# ─── Assemble final HTML ────────────────────────────────────────────────────

tmpl_path = assets_dir / "architecture.html.tmpl"
css_path = assets_dir / "architecture.css"
js_path  = assets_dir / "architecture.js"
if not tmpl_path.exists() or not css_path.exists() or not js_path.exists():
    sys.stderr.write(f"error: missing template assets under {assets_dir}\n")
    sys.exit(2)

tmpl = tmpl_path.read_text()
css = css_path.read_text()
js  = js_path.read_text()

# Build node index JSON
spec_json = {
    "kinds": KIND_LABELS,
    "nodes": {nid: {"kind": n["kind"], "title": n["title"], "summary": n["summary"]}
              for nid, n in nodes.items()},
}

# H1 with emphasis on project name
h1_html = f"{esc(title)} <em>architecture</em>"

generated_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
lede = (
    f"Spec-layer snapshot for {esc(title)}. {len(components)} components governed by "
    f"{len(adrs)} architecture decisions, with {len(sys_reqs)} system-level requirements "
    f"allocated across them."
)

# Conventions section is rendered only when the block is non-empty; the
# template still receives a placeholder string so the substitution succeeds.
if conventions:
    conventions_section_html = (
        '<section class="section" id="conventions">'
        '<h2><span class="num">§ 3</span>Conventions</h2>'
        '<p class="lede">Repository-hygiene rules — how the codebase is organized. '
        'Distinct from requirements (which describe system behavior) and from '
        'ADRs (which document load-bearing decisions with alternatives weighed).</p>'
        + "\n".join(render_convention(c) for c in conventions)
        + '</section>'
    )
else:
    conventions_section_html = ""

replacements = {
    "{{TITLE}}":               esc(title),
    "{{H1_HTML}}":             h1_html,
    "{{CSS}}":                 css,
    "{{JS}}":                  js,
    "{{GENERATED_AT}}":        esc(generated_at),
    "{{COMPONENTS_SHA_SHORT}}":esc(components_sha[:12]),
    "{{ADR_COUNT}}":           str(len(adrs)),
    "{{COMP_COUNT}}":          str(len(components)),
    "{{SYS_REQ_COUNT}}":       str(len(sys_reqs)),
    "{{REQ_COUNT}}":           str(req_count),
    "{{CONV_COUNT}}":          str(len(conventions)),
    "{{SUBHEAD_STATS}}":       subhead_html,
    "{{NAV_HTML}}":            build_nav(),
    "{{OVERVIEW_LEDE}}":       lede,
    "{{OVERVIEW_CARDS}}":      overview_cards,
    "{{MERMAID_SRC}}":         html.escape(build_mermaid(), quote=False),
    "{{DEPENDENCY_RULES_HTML}}": render_dep_rules(),
    "{{SYS_REQ_HTML}}":        "\n".join(render_sys_req(sr) for sr in sys_reqs),
    "{{CONVENTIONS_SECTION_HTML}}": conventions_section_html,
    "{{COMP_SECTION_NUM}}":    "4" if conventions else "3",
    "{{ADR_SECTION_NUM}}":     "5" if conventions else "4",
    "{{COMPONENTS_HTML}}":     "\n".join(render_component(c, components[c]) for c in components.keys()),
    "{{ADRS_HTML}}":           "\n".join(render_adr(a) for a in adrs),
    "{{SPEC_JSON}}":           json.dumps(spec_json, ensure_ascii=False)
                                .replace("</", "<\\/"),  # safe inside <script>
}

html_out = tmpl
for k, v in replacements.items():
    html_out = html_out.replace(k, v)

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(html_out)

size_kb = out_path.stat().st_size // 1024
print(f"rendered: {out_path}  ({size_kb} KB)", file=sys.stderr)
print(f"  components: {len(components)}  sys_reqs: {len(sys_reqs)}  reqs: {req_count}  conventions: {len(conventions)}  adrs: {len(adrs)}",
      file=sys.stderr)
PYEOF
