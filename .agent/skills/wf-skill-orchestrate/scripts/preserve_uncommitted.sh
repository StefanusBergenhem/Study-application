#!/usr/bin/env bash
#
# preserve_uncommitted.sh — Commit any tracked uncommitted files on a
# worktree before re-dispatching a build agent.
#
# Owned by: wf-skill-orchestrate.
# Invoked by: orchestrator on the build re-dispatch path (Build Return
# Protocol — after build_blocked has been applied, before re-dispatching).
#
# Problem solved: a build agent may halt with uncommitted tracked changes
# (implementation files staged, tests committed; or impl files modified but
# not committed because of an aborted commit). Without intervention, a
# subsequent merge would silently drop the uncommitted work. This helper
# preserves it under a structured commit so the merge carries everything.
#
# What it does NOT do: stage untracked files (`??` entries). Untracked
# files at re-dispatch time are usually scratch artifacts (logs, test
# fixtures, etc.) and should not be auto-committed. The build agent
# itself decides which new files to add to the next commit.
#
# Usage:
#   preserve_uncommitted.sh <worktree-path> <task-id>
#
# Output (stdout):
#   clean                           — no tracked uncommitted files; nothing committed
#   committed <short-sha>           — auto-commit created with the given SHA
#
# Exit codes:
#   0 = success (either clean or committed)
#   1 = git operation failed
#   2 = invalid arguments / worktree not found

set -euo pipefail

worktree_path="${1:-}"
task_id="${2:-}"

if [[ -z "$worktree_path" || -z "$task_id" ]]; then
    echo "usage: preserve_uncommitted.sh <worktree-path> <task-id>" >&2
    exit 2
fi

if [[ ! -d "$worktree_path/.git" && ! -f "$worktree_path/.git" ]]; then
    echo "error: $worktree_path is not a git worktree" >&2
    exit 2
fi

# Parse tracked uncommitted entries from porcelain v1.
# Format: "XY path" where:
#   X = index status (M, A, D, R, C, ...)
#   Y = worktree status (M, A, D, ...)
# Untracked entries are "?? path"; ignored states are "!! path".
# We want anything where either X or Y is non-space and non-? (i.e. tracked
# with changes).
#
# `git status --porcelain=v1` is stable across versions.

status_output="$(git -C "$worktree_path" status --porcelain=v1)"

# Filter: include lines where X or Y is in [MADRC]. Exclude `??` and `!!`.
tracked_changes="$(echo "$status_output" | awk '
    {
        x = substr($0, 1, 1)
        y = substr($0, 2, 1)
        if (x ~ /[MADRC]/ || y ~ /[MADRC]/) {
            # Strip leading 2 chars + space; print the path.
            print substr($0, 4)
        }
    }
')"

if [[ -z "$tracked_changes" ]]; then
    echo "clean"
    exit 0
fi

# Stage only the tracked uncommitted files. Never use `git add -A` or
# `git add .` — that would scoop up untracked scratch.
#
# Note: rename entries (R) include "old -> new" in the path; we split on " -> "
# and stage the new name.
files_to_stage=()
while IFS= read -r path; do
    if [[ "$path" == *" -> "* ]]; then
        path="${path##* -> }"
    fi
    # Strip surrounding quotes if git emitted them for paths with special chars.
    path="${path%\"}"
    path="${path#\"}"
    files_to_stage+=("$path")
done <<< "$tracked_changes"

# Build the commit message body listing the preserved files.
body_lines=""
for f in "${files_to_stage[@]}"; do
    body_lines+="• ${f}"$'\n'
done

# Stage and commit. Use --no-verify? NO — never bypass hooks. If a pre-commit
# hook fails, that is a signal worth surfacing rather than masking.
( cd "$worktree_path" && \
  git add -- "${files_to_stage[@]}" && \
  git commit -m "$(cat <<EOF
chore(${task_id}): preserve uncommitted files from prior build_blocked halt

Auto-committed by wf-skill-orchestrate/scripts/preserve_uncommitted.sh
before re-dispatch to prevent a silent merge drop.

Preserved files:
${body_lines}
EOF
)" \
) >/dev/null 2>&1

sha="$(git -C "$worktree_path" rev-parse --short HEAD)"
echo "committed ${sha}"
exit 0
