#!/usr/bin/env bash
# nja-fleet-waves — run one verification stage across every fleet member.
#
# Two scheduling modes, and the difference is not a preference:
#   lint/build/test   parallel, in chunks of --width
#   boot              STRICTLY SERIAL. Every member points at one Neo4j and
#                     one Redis, and two members claim the same ports.
#
# Chunked waves rather than a sliding window: macOS ships bash 3.2, which has
# no `wait -n`. With a handful of members the difference is a few seconds and
# the simpler scheduler is the one that can be reasoned about.
#
# Fail-fast applies WITHIN a member, never ACROSS members: the comparison
# between members is the diagnostic. A member that fails must not prevent its
# neighbours from running.
#
# Usage:
#   nja-fleet-waves.sh --roster <file> --stage <lint|build|test|boot>
#                      [--width <n>] [--logs <dir>]
#
# Env seams:
#   NJA_FLEET_WIDTH      default parallel width (default 3)
#   NJA_FLEET_STAGE_CMD  test-only: the command run per member instead of the
#                        real `pnpm <stage>`. Same convention as NJA_DEV_CMD.
#
# Exit codes:
#   0  every member passed
#   1  usage or environment error
#   2  one or more members failed
#   4  (boot only) the queue was ABORTED because nja-dev-boot.sh reported
#      exit 4 — teardown unverified, something may still be running
set -uo pipefail

NJA_WAVES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-fleet-lib.sh
. "$NJA_WAVES_DIR/nja-fleet-lib.sh"

ROSTER=""
STAGE=""
WIDTH="${NJA_FLEET_WIDTH:-3}"
LOGS=""

usage() {
  cat <<'USAGE'
nja-fleet-waves.sh --roster <file> --stage <lint|build|test|boot> [--width <n>] [--logs <dir>]

  --roster  one member path per line; # comments and blank lines ignored
  --stage   lint | build | test (parallel) or boot (strictly serial)
  --width   parallel width for lint/build/test (default 3, or NJA_FLEET_WIDTH)
  --logs    directory for per-member .log and .rc files
USAGE
}

require_optarg() {
  local opt="$1" remaining="$2" val="${3:-}"
  if [ "$remaining" -lt 2 ]; then
    printf '%s requires a value\n' "$opt" >&2; usage >&2; exit 1
  fi
  case "$val" in
    -*) printf '%s requires a value, got option-like argument: %s\n' "$opt" "$val" >&2
        usage >&2; exit 1 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --roster) require_optarg --roster "$#" "${2:-}"; ROSTER="$2"; shift 2 ;;
    --stage)  require_optarg --stage  "$#" "${2:-}"; STAGE="$2";  shift 2 ;;
    --width)  require_optarg --width  "$#" "${2:-}"; WIDTH="$2";  shift 2 ;;
    --logs)   require_optarg --logs   "$#" "${2:-}"; LOGS="$2";   shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -f "$ROSTER" ] || { printf 'roster not found: %s\n' "$ROSTER" >&2; exit 1; }
case "$STAGE" in
  lint|build|test|boot) ;;
  *) printf 'unknown stage: %s\n' "$STAGE" >&2; usage >&2; exit 1 ;;
esac
case "$WIDTH" in
  ''|*[!0-9]*) printf -- '--width must be a positive integer\n' >&2; exit 1 ;;
  0) printf -- '--width must be at least 1\n' >&2; exit 1 ;;
esac

LOGS="${LOGS:-$(nja_fleet_state_dir)/logs}"
mkdir -p "$LOGS" || { printf 'cannot create log dir: %s\n' "$LOGS" >&2; exit 1; }

MEMBERS="$(grep -v '^[[:space:]]*#' "$ROSTER" | grep -v '^[[:space:]]*$')"
[ -n "$MEMBERS" ] || { printf 'roster is empty: %s\n' "$ROSTER" >&2; exit 1; }

# The command one member runs for this stage. The env seam exists so the test
# suite can exercise the SCHEDULER without a real monorepo — it never changes
# what a real run executes.
stage_cmd() {
  if [ -n "${NJA_FLEET_STAGE_CMD:-}" ]; then
    printf '%s' "$NJA_FLEET_STAGE_CMD"
  elif [ "$1" = "boot" ]; then
    # No --root: nja-dev-boot.sh resolves the enclosing git toplevel, and
    # run_one has already cd'd into the member.
    printf '%s/nja-dev-boot.sh' "$NJA_WAVES_DIR"
  else
    printf 'pnpm %s' "$1"
  fi
}

# run_one <member> <stage> — writes <name>.<stage>.log and <name>.<stage>.rc.
# The rc file is how the parent learns the exit code: bash 3.2 cannot
# `wait -n`, and pairing PIDs to names by hand is the kind of bookkeeping
# that silently mismatches.
run_one() {
  local m="$1" st="$2" name cmd
  name="$(basename "$m")"
  cmd="$(stage_cmd "$st")"
  ( cd "$m" 2>/dev/null && eval "$cmd" ) >"$LOGS/$name.$st.log" 2>&1
  printf '%s\n' "$?" > "$LOGS/$name.$st.rc"
}

run_parallel() {
  local st="$1" n=0 rc=0 m name code
  # shellcheck disable=SC2086  # roster paths are word-split deliberately
  for m in $MEMBERS; do
    run_one "$m" "$st" &
    n=$((n + 1))
    if [ "$n" -ge "$WIDTH" ]; then wait; n=0; fi
  done
  wait
  # shellcheck disable=SC2086
  for m in $MEMBERS; do
    name="$(basename "$m")"
    code="$(cat "$LOGS/$name.$st.rc" 2>/dev/null || printf '1')"
    if [ "$code" = "0" ]; then
      nja_ok "$name  $st"
    else
      nja_fail "$name  $st  exit $code  ($LOGS/$name.$st.log)"
      rc=2
    fi
  done
  return "$rc"
}

# run_serial <stage> — the boot queue. One member at a time, in roster order.
#
# Serial is a HARD requirement, not a tuning choice: every member points at
# one Neo4j and one Redis, and two members claim the same ports.
#
# nja-dev-boot.sh exit 4 (teardown unverified — a process group may still be
# running) ABORTS the queue. In single-repo mode exit 4 is an emergency to
# report; here it is also a stop, because the next member's boot would fail
# on a port that is not free and that failure looks exactly like a dependency
# break. Continuing manufactures false failures.
#
# Note the ordering: the rc file is written by run_one BEFORE the exit-4
# check, so the aborting member's own result is never lost.
run_serial() {
  local st="$1" rc=0 m name code
  # shellcheck disable=SC2086
  for m in $MEMBERS; do
    name="$(basename "$m")"
    run_one "$m" "$st"
    code="$(cat "$LOGS/$name.$st.rc" 2>/dev/null || printf '1')"

    if [ "$code" = "4" ]; then
      nja_fail "$name  $st  exit 4 — teardown unverified, a process group may still be running"
      nja_say ""
      nja_say "ABORTING the remaining boot queue."
      nja_say "Continuing would start the next member against ports this one may still hold,"
      nja_say "and that failure is indistinguishable from a dependency break."
      nja_say "Inspect with the ps line nja-dev-boot.sh printed, in $LOGS/$name.$st.log."
      nja_say "Do NOT free the port and do NOT kill by name — resolve the group it named."
      return 4
    fi

    if [ "$code" = "0" ]; then
      nja_ok "$name  $st"
    else
      nja_fail "$name  $st  exit $code  ($LOGS/$name.$st.log)"
      rc=2
    fi
  done
  return "$rc"
}

if [ "$STAGE" = "boot" ]; then
  run_serial "$STAGE"
  exit $?
fi

run_parallel "$STAGE"
exit $?
