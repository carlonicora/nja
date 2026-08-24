#!/usr/bin/env bash
# Test runner for the nja plugin's shell scripts.
#   bash nja/tests/run.sh            # all suites
#   bash nja/tests/run.sh deps-lib   # one suite (matches test-<name>.sh)
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NJA_SCRIPTS_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"

# shellcheck source=./lib.sh
. "$TESTS_DIR/lib.sh"

filter="${1:-}"
for suite in "$TESTS_DIR"/test-*.sh; do
  [ -f "$suite" ] || continue
  name="$(basename "$suite" .sh)"; name="${name#test-}"
  [ -n "$filter" ] && [ "$filter" != "$name" ] && continue
  printf '\n%s\n' "── $name ──────────────────────────────────────────"
  # shellcheck disable=SC1090
  . "$suite"
done

printf '\n%s\n' "──────────────────────────────────────────────────"
if [ "$T_FAILED" -gt 0 ]; then
  printf '%d/%d failed\n' "$T_FAILED" "$T_RUN" >&2
  exit 1
fi
printf 'all %d passed\n' "$T_RUN"
