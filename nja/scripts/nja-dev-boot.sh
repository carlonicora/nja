#!/usr/bin/env bash
# nja-dev-boot — start the dev stack, confirm it boots, tear it down cleanly.
#
# `pnpm dev` starts THREE persistent processes: api (port), web (port), and a
# worker with NO port. Ports alone cannot tear that down, and killing by name
# is forbidden — several nja repos run at once on this machine with identical
# command lines, so a pattern cannot tell them apart. The handle is the
# process group we create and own.
#
# macOS has no setsid; `set -m` makes a backgrounded subshell its own group
# leader (PGID == PID), which `kill -- -PGID` then addresses.
#
# SIGTERM before SIGKILL is load-bearing: scripts/dev.sh in the real repos
# traps EXIT/INT/TERM to remove apps/web/.next-dev.lock. SIGKILL skips that
# trap, the lock survives, and the next `pnpm dev` reads it as an unclean
# exit and wipes apps/web/.next — a slow cold rebuild caused by our own
# teardown. So: TERM first, wait, escalate to KILL only if the group
# survives.
#
# Usage: nja-dev-boot.sh [--root <path>] [--timeout <seconds>]
#
# Env seams:
#   NJA_DEV_CMD     command to launch (default: pnpm dev). Word-split.
#   NJA_READY_API / NJA_READY_WEB / NJA_READY_WORKER   readiness regexes
#                   (consumed by the Task 10 readiness poll loop)
#
# Exit codes:
#   0  booted and tore down cleanly
#   1  precondition failure (port busy, usage)
#   2  boot failed (timeout or fatal log pattern) — arrives in Task 10
#   4  teardown unverified — SOMETHING MAY STILL BE RUNNING
set -uo pipefail

NJA_BOOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-detect.sh
. "$NJA_BOOT_DIR/nja-detect.sh"

# Deliberately not sourcing nja-deps-lib.sh: that library exists for the
# dependency-surface scripts (sweep, doctor). This script's only shared
# dependency is the project detector; its own output helpers stay local.
nja_say()  { printf '%s\n' "$*"; }
nja_ok()   { printf '  ✓ %s\n' "$*"; }
nja_warn() { printf '  ⚠ %s\n' "$*"; }
nja_fail() { printf '  ✖ %s\n' "$*" >&2; }

usage() {
  printf 'nja-dev-boot.sh [--root <path>] [--timeout <seconds>]\n'
}

# require_optarg <option> <remaining-count> <candidate-value>
# Guards every value-taking option below. `shift 2` in bash is all-or-nothing:
# with only one argument left it shifts nothing, so a bare trailing `--root`
# (or `--timeout`) would leave $1 unchanged and spin the while-loop forever
# — reproduced elsewhere as a real process pinned at 99.6% CPU. A value that
# itself looks like another flag (e.g. `--root --help`) is never legitimate
# here either — every real value is a path or an integer, neither of which
# starts with "-". Mirrors the guard already shipped in nja-deps-sweep.sh and
# nja-deps-doctor.sh; kept local to this script rather than shared via
# nja-deps-lib.sh, per the same convention those two scripts use.
require_optarg() {
  local opt="$1" remaining="$2" val="${3:-}"
  if [ "$remaining" -lt 2 ]; then
    printf '%s requires a value\n' "$opt" >&2
    usage >&2
    exit 1
  fi
  case "$val" in
    -*)
      printf '%s requires a value, got option-like argument: %s\n' "$opt" "$val" >&2
      usage >&2
      exit 1
      ;;
  esac
}

ROOT=""
TIMEOUT=180
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      require_optarg --root "$#" "${2:-}"
      ROOT="$2"; shift 2 ;;
    --timeout)
      require_optarg --timeout "$#" "${2:-}"
      case "$2" in
        ''|*[!0-9]*)
          printf -- '--timeout requires an integer value (seconds), got: %s\n' "$2" >&2
          usage >&2
          exit 1
          ;;
      esac
      TIMEOUT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

if git -C "${ROOT:-$PWD}" rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git -C "${ROOT:-$PWD}" rev-parse --show-toplevel)"
else
  ROOT="$(cd "${ROOT:-$PWD}" && pwd)"
fi

if ! nja_is_project "$ROOT"; then
  nja_say "nja-dev-boot: $ROOT is not an nja project — nothing to do."
  exit 0
fi

# ── ports ────────────────────────────────────────────────────────────────────
env_value() {
  local key="$1" f
  for f in "$ROOT/.env" "$ROOT/.env.example"; do
    [ -f "$f" ] || continue
    awk -F= -v k="$key" '$1 == k { print $2; exit }' "$f" | tr -d '"'"'"' \r'
  done | grep -m1 . || true
}

API_PORT="${API_PORT:-$(env_value API_PORT)}"; API_PORT="${API_PORT:-3950}"
WEB_PORT="${PORT:-$(env_value PORT)}";          WEB_PORT="${WEB_PORT:-3951}"

port_busy() { lsof -ti :"$1" -sTCP:LISTEN >/dev/null 2>&1; }
group_alive() { [ -n "$(ps -o pid= -g "$1" 2>/dev/null)" ]; }

# ── teardown — the only kill path in this script ─────────────────────────────
# PGID is the process group we created below via `set -m`. This is the whole
# reason for the process-group approach: killing by name or pattern is
# forbidden (several nja repos run at once with byte-identical command
# lines), and the worker process has no port to target. The group handle is
# the only thing that can reach api + web + worker together.
PGID=""
teardown() {
  [ -n "$PGID" ] || return 0
  kill -TERM -- "-$PGID" 2>/dev/null
  local waited=0
  while [ "$waited" -lt 20 ]; do
    group_alive "$PGID" || { PGID=""; return 0; }
    sleep 1; waited=$((waited + 1))
  done
  nja_warn "group $PGID ignored SIGTERM after 20s — escalating to SIGKILL"
  kill -KILL -- "-$PGID" 2>/dev/null
  sleep 1
  if group_alive "$PGID"; then return 1; fi
  PGID=""
  return 0
}
trap 'teardown >/dev/null 2>&1' EXIT INT TERM

# ── preconditions ────────────────────────────────────────────────────────────
for p in "$API_PORT" "$WEB_PORT"; do
  if port_busy "$p"; then
    nja_fail "port $p is already in use — refusing to start"
    nja_say "      That process is not ours. Stop it yourself, then re-run."
    nja_say "      Inspect it with: lsof -i :$p"
    exit 1
  fi
done

# ── launch ───────────────────────────────────────────────────────────────────
LOG="$(mktemp -t nja-dev-boot)"
nja_say "── booting ───────────────────────────────────────"
nja_say "  root:    $ROOT"
nja_say "  ports:   api=$API_PORT web=$WEB_PORT"
nja_say "  log:     $LOG"

cd "$ROOT" || exit 1
set -m
( ${NJA_DEV_CMD:-pnpm dev} ) >"$LOG" 2>&1 &
PGID=$!
set +m
nja_say "  group:   $PGID"

# ── teardown and verify ──────────────────────────────────────────────────────
# Task 10 appends the readiness poll loop after this point, and that loop is
# what calls finish() — with 0 once NJA_READY_API/WEB/WORKER all match in
# $LOG, or 2 on timeout / a fatal pattern. Until that loop exists, finish()
# is defined but never invoked: this task's own flow simply falls off the
# end of the script, and the EXIT trap above is what tears the group down.
finish() {
  local code="$1"
  if ! teardown; then
    nja_fail "TEARDOWN UNVERIFIED — group $PGID may still be running"
    nja_say "      Inspect: ps -o pid,pgid,args -g $PGID"
    exit 4
  fi
  local p
  for p in "$API_PORT" "$WEB_PORT"; do
    if port_busy "$p"; then
      nja_fail "TEARDOWN UNVERIFIED — port $p is still bound"
      exit 4
    fi
  done
  nja_ok "group terminated; ports free"
  if [ -f "$ROOT/apps/web/.next-dev.lock" ]; then
    nja_warn "apps/web/.next-dev.lock survived — dev.sh's trap did not run;"
    nja_say "        the next pnpm dev will clear apps/web/.next"
  fi
  nja_say "  log kept at: $LOG"
  exit "$code"
}
