#!/usr/bin/env bash
#
# detect_components_drift.sh — Generic component drift detector.
#
# Reads COMPONENTS.yaml + .workflow/config.yaml. Produces a drift report
# at the path given by `paths.components_drift` in config.
#
# Checks (project-agnostic):
#   - path_missing       : declared component.path does not exist on disk
#   - oversized          : component source file count > constraints.max_source_files
#   - path_collision     : two components share or prefix each other's path
#   - orphan             : source file under paths.source_root matched by source_globs
#                          but not owned by any component (longest-prefix match)
#
# Optional project hook (commands.scan_components in config):
#   - Invoked once per component as: <hook> <component-name> <component-path>
#   - The component's YAML block is fed on stdin
#   - Stdout: a YAML fragment with `component:` and `findings:` (see WORKFLOW.md)
#   - Exit 0 = success. Non-zero = hook errored; finding `hook_error` is recorded.
#   - Timeout: commands.scan_components_timeout seconds (default 30).
#
# Usage:
#   detect_components_drift.sh [--config <path>]   # defaults to .workflow/config.yaml
#
# Exit codes:
#   0 = scan completed (with or without drift findings — drift is data, not failure)
#   2 = unrecoverable script error (missing config, unparseable YAML, etc.)
#
# Dependencies: python3 with PyYAML. If PyYAML is missing, the script prints a
# clear install hint and exits 2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH=".workflow/config.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_PATH="$2"; shift 2 ;;
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

exec python3 - "$CONFIG_PATH" <<'PYEOF'
import datetime
import hashlib
import os
import subprocess
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
project_root = (config_path.parent.parent if config_path.name == "config.yaml" else Path.cwd()).resolve()

# --- Load config -----------------------------------------------------------
try:
    config = yaml.safe_load(config_path.read_text()) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {config_path}: {exc}\n")
    sys.exit(2)

paths = config.get("paths", {}) or {}
commands = config.get("commands", {}) or {}
source_globs = config.get("source_globs", []) or []

components_path_str = paths.get("components", "COMPONENTS.yaml")
drift_path_str = paths.get("components_drift", ".workflow/components_drift.yaml")
source_root_str = paths.get("source_root", ".")
hook_cmd = commands.get("scan_components", "") or ""
hook_timeout = int(commands.get("scan_components_timeout", 30) or 30)

components_path = (project_root / components_path_str).resolve()
drift_path = (project_root / drift_path_str).resolve()
source_root = (project_root / source_root_str).resolve()

if not components_path.exists():
    sys.stderr.write(f"error: components file not found at {components_path}\n")
    sys.exit(2)

# --- Load components -------------------------------------------------------
try:
    raw = components_path.read_text()
    components_doc = yaml.safe_load(raw) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"error: failed to parse {components_path}: {exc}\n")
    sys.exit(2)

components = components_doc.get("components", {}) or {}
components_sha = hashlib.sha256(raw.encode("utf-8")).hexdigest()

findings = []
hook_components_scanned = 0
hook_components_errored = 0

def add_finding(component, kind, source, severity, details):
    findings.append({
        "component": component,
        "kind": kind,
        "source": source,
        "severity": severity,
        "details": details,
    })

# --- Generic check: path_missing ------------------------------------------
component_paths = {}  # name -> resolved Path or None
for name, spec in components.items():
    spec = spec or {}
    declared = spec.get("path")
    if not declared:
        component_paths[name] = None
        continue
    p = (project_root / declared).resolve()
    component_paths[name] = p
    if not p.exists():
        add_finding(name, "path_missing", "generic", "error",
                    {"declared_path": declared})

# --- Generic check: path_collision ----------------------------------------
named_paths = [(n, p) for n, p in component_paths.items() if p is not None and p.exists()]
for i, (n1, p1) in enumerate(named_paths):
    for n2, p2 in named_paths[i+1:]:
        try:
            r1 = p1.relative_to(project_root).as_posix()
            r2 = p2.relative_to(project_root).as_posix()
        except ValueError:
            continue
        if r1 == r2:
            add_finding(None, "path_collision", "generic", "error",
                        {"components": [n1, n2], "path": r1, "kind": "identical"})
        elif (r1 + "/").startswith(r2 + "/") or (r2 + "/").startswith(r1 + "/"):
            add_finding(None, "path_collision", "generic", "warning",
                        {"components": [n1, n2], "paths": [r1, r2], "kind": "prefix"})

# --- Generic check: oversized + orphan (needs source_globs) ---------------
SKIP_DIRS = {".git", "node_modules", "vendor", ".workflow", ".claude", ".agent"};
             "dist", "build", "target", "__pycache__"}

def collect_source_files(root: Path, globs):
    """Return source files matching any glob, recursively. Skips SKIP_DIRS."""
    results = set()
    for g in globs:
        # Path.rglob handles **/ semantics correctly. Strip leading **/ which
        # rglob applies implicitly.
        pattern = g[3:] if g.startswith("**/") else g
        for p in root.rglob(pattern):
            if not p.is_file():
                continue
            if any(part in SKIP_DIRS for part in p.parts):
                continue
            try:
                results.add(p.relative_to(project_root).as_posix())
            except ValueError:
                continue
    return sorted(results)

source_files_by_component = {n: [] for n in components.keys()}
all_source_files = []

if source_globs and source_root.exists():
    all_source_files = collect_source_files(source_root, source_globs)

    # Assign each source file to the component with the longest prefix match
    component_prefixes = []
    for n, p in named_paths:
        try:
            rel_p = p.relative_to(project_root).as_posix().rstrip("/")
            component_prefixes.append((n, rel_p))
        except ValueError:
            continue
    component_prefixes.sort(key=lambda x: len(x[1]), reverse=True)

    for rel_file in all_source_files:
        owner = None
        for n, rel_p in component_prefixes:
            if rel_file == rel_p or rel_file.startswith(rel_p + "/"):
                owner = n
                break
        if owner is None:
            add_finding(None, "orphan", "generic", "info",
                        {"file": rel_file})
        else:
            source_files_by_component[owner].append(rel_file)

    # Oversized check
    for name, spec in components.items():
        spec = spec or {}
        constraints = spec.get("constraints", {}) or {}
        limit = constraints.get("max_source_files")
        if limit is None:
            continue
        actual = len(source_files_by_component.get(name, []))
        if actual > int(limit):
            add_finding(name, "oversized", "generic", "warning",
                        {"actual_files": actual, "limit": int(limit)})

# --- Optional project hook ------------------------------------------------
hook_configured = bool(hook_cmd)
if hook_configured:
    for name, spec in components.items():
        spec = spec or {}
        path_str = spec.get("path", "")
        component_yaml = yaml.safe_dump({name: spec}, sort_keys=False)
        try:
            result = subprocess.run(
                hook_cmd.split() + [name, path_str],
                input=component_yaml,
                capture_output=True,
                text=True,
                timeout=hook_timeout,
                cwd=str(project_root),
                check=False,
            )
        except subprocess.TimeoutExpired:
            add_finding(name, "hook_error", "hook", "error",
                        {"reason": "timeout", "timeout_seconds": hook_timeout})
            hook_components_errored += 1
            continue
        except FileNotFoundError:
            add_finding(name, "hook_error", "hook", "error",
                        {"reason": "hook_command_not_found", "command": hook_cmd})
            hook_components_errored += 1
            continue
        hook_components_scanned += 1
        if result.returncode != 0:
            add_finding(name, "hook_error", "hook", "error",
                        {"reason": "non_zero_exit", "exit_code": result.returncode,
                         "stderr_tail": result.stderr[-500:] if result.stderr else ""})
            hook_components_errored += 1
            continue
        stdout = result.stdout.strip()
        if not stdout:
            continue
        try:
            hook_doc = yaml.safe_load(stdout) or {}
        except yaml.YAMLError as exc:
            add_finding(name, "hook_error", "hook", "error",
                        {"reason": "unparseable_yaml", "error": str(exc)})
            hook_components_errored += 1
            continue
        for f in (hook_doc.get("findings") or []):
            add_finding(
                hook_doc.get("component") or name,
                f.get("kind", "unknown"),
                "hook",
                f.get("severity", "warning"),
                f.get("details") or {k: v for k, v in f.items() if k not in ("kind", "severity")},
            )

# --- Build summary --------------------------------------------------------
by_severity = {"error": 0, "warning": 0, "info": 0}
by_kind = {}
for f in findings:
    sev = f.get("severity", "warning")
    by_severity[sev] = by_severity.get(sev, 0) + 1
    k = f.get("kind", "unknown")
    by_kind[k] = by_kind.get(k, 0) + 1

report = {
    "version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "generated_by": "wf-skill-sa/scripts/detect_components_drift.sh",
    "components_yaml_sha": components_sha,
    "hook": {
        "configured": hook_configured,
        "command": hook_cmd if hook_configured else None,
        "components_scanned": hook_components_scanned,
        "components_errored": hook_components_errored,
    },
    "findings": findings,
    "summary": {
        "total_findings": len(findings),
        "by_severity": by_severity,
        "by_kind": by_kind,
    },
}

drift_path.parent.mkdir(parents=True, exist_ok=True)
drift_path.write_text(yaml.safe_dump(report, sort_keys=False, default_flow_style=False))
print(f"drift report written: {drift_path}", file=sys.stderr)
print(f"  findings: {len(findings)} ({by_severity.get('error', 0)} error, "
      f"{by_severity.get('warning', 0)} warning, {by_severity.get('info', 0)} info)",
      file=sys.stderr)
PYEOF
