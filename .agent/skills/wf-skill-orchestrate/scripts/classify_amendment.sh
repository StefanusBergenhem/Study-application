#!/usr/bin/env bash
#
# classify_amendment.sh — Classify a proposed scope amendment as
# Feature (consumes budget) vs Mechanical Follow-on (free) vs Reject.
#
# Owned by: wf-skill-orchestrate.
# Invoked by: orchestrator on scope-amendment requests from build agents.
#
# Background: a "mechanical follow-on" amendment is a test-file-only
# amendment whose entire content is assertion-value updates on symbols
# (constants, types, signatures) renamed or restructured by the
# immediately-preceding production-code amendment. The follow-on has zero
# risk of expanding feature scope and should not consume the
# `escalation.max_scope_amendments` budget.
#
# This script applies a conservative classifier:
#
#   feature              — default. Any amendment that touches a
#                          non-test file, or any test amendment that
#                          adds new test functions / describe blocks,
#                          or any amendment for which the classifier
#                          lacks signal. Consumes one budget unit.
#
#   mechanical_follow_on — narrow case. ALL added files match the test
#                          file patterns; the diff in each adds NO new
#                          test-function declarations (no new `func Test*`,
#                          no new `it(`, no new `describe(`, no new
#                          `test(`, no new `def test_*`); only existing
#                          assertions are modified.
#
#   reject               — the amendment claims mechanical follow-on
#                          but adds new tests or new non-test files.
#                          Surfaces an abuse attempt; the orchestrator
#                          escalates rather than auto-applying.
#
# Test file patterns the classifier recognises (best-effort, additive):
#   - paths ending in _test.go, .test.ts, .test.tsx, .test.js, .test.jsx
#   - paths ending in _test.py, test_*.py
#   - paths under a top-level tests/, test/, spec/ directory
#   - any custom pattern passed via --test-pattern (repeatable)
#
# Usage:
#   classify_amendment.sh --task-id <id> --diff <path-to-diff-file>
#                         [--test-pattern <regex>]... [--claim <kind>]
#
# Inputs:
#   --task-id      Sprint task id (for logging context).
#   --diff         Path to a unified diff file showing the proposed
#                  amendment (e.g., output of `git diff` against the
#                  current task branch tip).
#   --test-pattern Regex for an additional test file pattern (matched
#                  against the file path). Repeatable.
#   --claim        The amendment's claimed kind, if any
#                  (`feature` | `mechanical_follow_on`). If `claim` is
#                  `mechanical_follow_on` but the classifier disagrees,
#                  the script returns `reject` instead of `feature`.
#
# Output (stdout):
#   feature
#   mechanical_follow_on
#   reject
#
# Exit codes:
#   0 = classification emitted
#   2 = script error (missing args, unreadable diff)

set -euo pipefail

task_id=""
diff_path=""
claim=""
extra_patterns=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task-id)      task_id="$2"; shift 2 ;;
        --diff)         diff_path="$2"; shift 2 ;;
        --test-pattern) extra_patterns+=("$2"); shift 2 ;;
        --claim)        claim="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,55p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)  echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$task_id" || -z "$diff_path" ]]; then
    echo "error: --task-id and --diff are required" >&2
    exit 2
fi

if [[ ! -f "$diff_path" ]]; then
    echo "error: diff file not found at $diff_path" >&2
    exit 2
fi

# Default test-file patterns. Extra patterns appended via --test-pattern.
default_patterns=(
    '_test\.go$'
    '\.test\.(ts|tsx|js|jsx)$'
    '\.spec\.(ts|tsx|js|jsx)$'
    '_test\.py$'
    '(^|/)test_[^/]+\.py$'
    '(^|/)tests?/'
    '(^|/)spec/'
)
all_patterns=("${default_patterns[@]}" "${extra_patterns[@]}")

# Build a combined egrep pattern.
joined_pattern="$(IFS='|'; echo "${all_patterns[*]}")"

# Extract the list of files in the diff (handle "diff --git a/.. b/..").
files_changed="$(awk '
    /^diff --git / {
        # Capture the second path (b/<path>) which is the post-amend name.
        match($0, / b\/[^ ]+$/)
        if (RSTART) {
            print substr($0, RSTART + 3, RLENGTH - 3)
        }
    }
' "$diff_path")"

if [[ -z "$files_changed" ]]; then
    # No file changes detected — not classifiable. Treat as feature (safe default).
    echo "feature"
    exit 0
fi

# Classify each file: test or not?
non_test_files=()
test_files=()
while IFS= read -r f; do
    if echo "$f" | grep -Eq "$joined_pattern"; then
        test_files+=("$f")
    else
        non_test_files+=("$f")
    fi
done <<< "$files_changed"

# If ANY non-test files are touched, this is a feature amendment.
if [[ "${#non_test_files[@]}" -gt 0 ]]; then
    if [[ "$claim" == "mechanical_follow_on" ]]; then
        echo "reject"
        exit 0
    fi
    echo "feature"
    exit 0
fi

# All-test amendment. Check whether any new test-function declarations
# were added. We look at lines starting with `+` (added) for known
# test-declaration patterns. False-positive-risk patterns are kept narrow.
new_test_decl_patterns=(
    '^\+\s*func\s+Test[A-Z_]'             # Go
    '^\+\s*func\s+Benchmark[A-Z_]'         # Go benchmarks
    '^\+\s*describe\s*\('                  # Jest/Vitest/Jasmine/Mocha JS
    '^\+\s*it\s*\('                        # JS test cases (top-level)
    '^\+\s*test\s*\('                      # JS test cases (top-level)
    '^\+\s*def\s+test_'                    # Python pytest / unittest method
    '^\+\s*class\s+Test[A-Z_]'             # Python unittest TestCase class
)
new_decl_pattern="$(IFS='|'; echo "${new_test_decl_patterns[*]}")"

if grep -Eq "$new_decl_pattern" "$diff_path"; then
    # Added new tests — not a pure mechanical follow-on.
    if [[ "$claim" == "mechanical_follow_on" ]]; then
        echo "reject"
        exit 0
    fi
    echo "feature"
    exit 0
fi

# All-test amendment with no new test declarations → mechanical follow-on.
echo "mechanical_follow_on"
exit 0
