#!/usr/bin/env bash
# Stop hook: deterministic architecture gate.
#
# Blocks turn completion while BLOCKING architecture violations remain in the
# uncommitted diff. Fast — grep only, no build/test, so it never adds the
# friction the user opted out of for the test suite. Soft on non-git dirs and
# when the linter is unavailable (exits 0 = allow stop).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../scripts/nja-lint.sh"
# shellcheck source=../scripts/nja-detect.sh
. "$SCRIPT_DIR/../scripts/nja-detect.sh" 2>/dev/null || exit 0

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
[ -n "$CWD" ] || CWD="$PWD"

# Per-project kill switch: `touch .claude/nja-gate-off` in a checkout silences
# the gate there (delete the file to re-enable). NJA_GATE_DISABLE=1 works too.
[ -n "${NJA_GATE_DISABLE:-}" ] && exit 0
[ -f "$CWD/.claude/nja-gate-off" ] && exit 0

# Only gate inside a git work tree, only if the linter is present, and ONLY in
# an nja project — the plugin is user-scoped and must stay inert elsewhere.
git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
[ -f "$LINT" ] || exit 0
nja_is_project "$CWD" || exit 0

# Run the linter over the uncommitted diff (it derives scope from git status).
OUT=$(cd "$CWD" && bash "$LINT" 2>/dev/null)
STATUS=$?

if [ "$STATUS" -eq 2 ]; then
  REASON="ARCHITECTURE GATE — blocking violations remain in the uncommitted diff.

These are deterministic checks against the nja-architecture rules. Fix them before finishing:

$OUT

Next steps:
  • Invoke the \`nja-architecture\` skill and open the cited reference doc for each.
  • Fix the code, then finish again — the gate re-runs automatically.
  • If a hit is a genuine false positive, add a comment containing nja-lint-ignore on that line."
  jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
  exit 0
fi

exit 0
