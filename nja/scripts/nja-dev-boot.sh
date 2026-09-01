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
#   NJA_FORCE_TEARDOWN_FAIL   test-only: set to exactly "1" or "true" (any
#                   other value, including unset or "0", is a no-op) to make
#                   teardown_verified() report failure (exit 4) even though
#                   the real teardown succeeded, so that path can be
#                   exercised without a process group that genuinely
#                   survives SIGKILL. Only takes effect when a process group
#                   was actually created — it can never reclassify a
#                   precondition failure (no group ever launched) as
#                   "teardown unverified".
#
# Exit codes:
#   0    booted and tore down cleanly
#   1    precondition failure (port busy, usage)
#   2    boot failed (timeout or fatal log pattern)
#   4    teardown unverified — SOMETHING MAY STILL BE RUNNING (wins over
#        any other pending exit code, including 130/143 below)
#   130/143   interrupted by SIGINT/SIGTERM — teardown still ran first
#
# Known limit: a SECOND Ctrl-C arriving while teardown itself is running
# (i.e. after the first INT/TERM has already cleared its own trap via
# `trap - INT TERM` in on_signal, below) falls through to bash's default
# SIGINT disposition, which can abort teardown mid-flight. That exits 130
# rather than the usual 4, and the group's fate is whatever the aborted
# teardown left behind. Not fixed here — documented as a known gap.
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

# `-iTCP:PORT`, not `-i :PORT`: the bare form matches UDP bindings too, and
# `-sTCP:LISTEN` does not filter them out. On macOS /usr/libexec/rapportd holds
# UDP on assorted high ports, so a repo whose api port collided with one was
# reported busy by a process that was not ours and the boot aborted (observed on
# a 3722 api port, 2026-08-30). TCP-only is what "is a server listening here"
# actually means.
port_busy() { lsof -tiTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
group_alive() { [ -n "$(ps -o pid= -g "$1" 2>/dev/null)" ]; }

# ── teardown — the only kill path in this script ─────────────────────────────
# PGID is the process group we created below via `set -m`. This is the whole
# reason for the process-group approach: killing by name or pattern is
# forbidden (several nja repos run at once with byte-identical command
# lines), and the worker process has no port to target. The group handle is
# the only thing that can reach api + web + worker together.
PGID=""
teardown() {
  # Structurally refuse to signal anything but a genuine, specific group:
  # empty (nothing launched), non-numeric (garbage), exactly "1" (which
  # `kill -- -1` would broadcast to every process this user can signal), or
  # exactly "0" (`kill -- -0` targets the CALLER's own process group — i.e.
  # this script's own) are all rejected before a kill is ever attempted —
  # not merely relying on `[ -n "$PGID" ]`, which says nothing about what a
  # non-empty PGID actually contains. "0" is unreachable in practice ($! is
  # never 0), but rejecting it keeps the guard structurally exhaustive
  # rather than relying on that being true.
  case "$PGID" in
    ''|*[!0-9]*|1|0) return 0 ;;
  esac
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

# teardown_verified — the single place that decides whether the group is
# confirmed gone, and the single place that reports (to stderr) when it is
# not. Both the signal path below and finish() (Task 10) go through this, so
# the "TEARDOWN UNVERIFIED" diagnostic and the exit-4 contract live in
# exactly one place rather than being duplicated.
#
# NJA_FORCE_TEARDOWN_FAIL is a test-only override: a process group that
# genuinely survives SIGKILL cannot be constructed portably in a test, so
# this makes teardown_verified() REPORT failure regardless of teardown()'s
# real outcome. teardown() itself still runs for real either way — this
# never causes an actual stray process, only a forced diagnostic.
#
# The override requires an explicit "1" or "true" — NJA_FORCE_TEARDOWN_FAIL=0
# must NOT activate it (an earlier version treated any non-empty value,
# including "0", as truthy).
#
# It is also gated on a group having actually existed ($was_pgid non-empty):
# when a precondition failure (e.g. port busy) exits before `set -m` ever
# ran, PGID is still "" and there is nothing to tear down — forcing "exit 4,
# teardown unverified" in that case would reclassify a precondition failure
# and print an incoherent diagnostic (an empty pgid pasted into `ps -g `).
teardown_verified() {
  local was_pgid="$PGID" ok=0
  teardown || ok=1
  if [ -n "$was_pgid" ]; then
    case "${NJA_FORCE_TEARDOWN_FAIL:-}" in
      1|true) ok=1 ;;
    esac
  fi
  if [ "$ok" -ne 0 ]; then
    if [ -n "$was_pgid" ]; then
      nja_fail "TEARDOWN UNVERIFIED — group $was_pgid may still be running"
      nja_say "      Inspect: ps -o pid,pgid,args -g $was_pgid"
    else
      nja_fail "TEARDOWN UNVERIFIED — no process group was ever created to verify"
    fi
    return 4
  fi
  return 0
}

# ── exit / signal handling ───────────────────────────────────────────────────
# The EXIT trap is the only place teardown_verified() runs on a normal
# return; it leaves a successful exit's code alone but a failed teardown
# always wins — exit 4 overrides whatever was otherwise pending. Safe to run
# more than once: teardown() clears PGID on success, so a second call from
# here after on_signal has already torn down is a no-op.
on_exit() {
  teardown_verified
  local td=$?
  [ "$td" -eq 0 ] || exit "$td"
}
trap on_exit EXIT

# INT/TERM must tear the group down AND terminate this script — without an
# explicit exit here, bash resumes whatever was interrupted and the script
# keeps running (measured: ~6.5s of continued execution after a SIGINT that
# had already reaped the group). Task 10 appends a readiness poll loop right
# after finish() below; without this fix, Ctrl-C during that loop would kill
# the dev stack but leave the loop spinning against a dead log for up to
# --timeout seconds. `trap - INT TERM` first so a second signal arriving
# mid-teardown falls back to bash's default handling instead of re-entering
# this function.
on_signal() {
  trap - INT TERM
  exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

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

# ── settle ───────────────────────────────────────────────────────────────────
# Task 9 has no readiness detection yet (Task 10 adds the NJA_READY_* poll
# loop that calls finish() below). Without any pause here, this task's own
# flow falls off the end of the script and the EXIT trap tears the group
# down within roughly a millisecond of it being created — before a real dev
# stack's own children even exist. This wait is deliberately generic (not
# tied to any readiness pattern) and bounded: wait for $LOG to have any
# content at all, up to ~5s, then proceed regardless, exactly like the rest
# of this task's flow. It is not a substitute for Task 10's real check.
SETTLE_WAITED=0
while [ ! -s "$LOG" ] && [ "$SETTLE_WAITED" -lt 50 ]; do
  sleep 0.1
  SETTLE_WAITED=$((SETTLE_WAITED + 1))
done

# ── teardown and verify ──────────────────────────────────────────────────────
# Task 10 appends the readiness poll loop after this point, and that loop is
# what calls finish() — with 0 once NJA_READY_API/WEB/WORKER all match in
# $LOG, or 2 on timeout / a fatal pattern. Until that loop exists, finish()
# is defined but never invoked: this task's own flow simply falls off the
# end of the script, and the EXIT trap above is what tears the group down
# (via the same teardown_verified() this function calls).
finish() {
  local code="$1"
  teardown_verified
  local td=$?
  [ "$td" -eq 0 ] || exit "$td"
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

# ── readiness ────────────────────────────────────────────────────────────────
# turbo prefixes output with "<package>:<task>:". apps/api defines both `dev`
# and `dev:worker`, so the worker's lines carry ":dev:worker:" and the api's do
# not — a package-name-agnostic discriminator that holds across all six repos.
NEST_READY='Nest application successfully started|Application is running on'
NJA_READY_API="${NJA_READY_API:-$NEST_READY}"
# The worker does NOT print the api's ready line. A NestJS app started in worker
# mode binds no HTTP server, so "Nest application successfully started" /
# "Application is running on" never appear and worker readiness silently
# degraded to a WARN on every repo in the fleet (observed in two repos,
# 2026-08-30). These apps announce themselves with "Worker process started";
# keep the api patterns as a fallback for repos whose worker does serve HTTP.
NJA_READY_WORKER="${NJA_READY_WORKER:-Worker process started|$NEST_READY}"
NJA_READY_WEB="${NJA_READY_WEB:-Ready in|started server on|Local:}"

FATAL='UnknownDependenciesException|Cannot find module|ERR_MODULE_NOT_FOUND|ERR_PNPM_|UnhandledPromiseRejection'

# None of these may end a pipeline with `grep -q`: under `pipefail`, `-q`
# exits the instant it finds a match and closes its stdin, and if an
# upstream stage is still mid-write to a pipe that already holds more data
# than the kernel pipe buffer (~16KB on macOS — trivially exceeded once a
# real dev log accrues webpack/compile chatter after the ready line), that
# upstream process gets SIGPIPE and exits 141. With pipefail, THAT becomes
# the pipeline's reported status even though a match was genuinely found —
# a false negative that grows more likely, not less, the longer the stack
# has been up. Verified empirically on this platform: a 3-stage pipe ending
# in `grep -q` against a real BSD grep (not any interactive-shell grep
# shim) went from 0/10 false negatives at 16000B to 7/10 at 18000B to
# 10/10 at 30000B and beyond, up to 19MB. `grep -c` cannot short-circuit —
# it must consume all its input to produce an accurate count — so it never
# closes the pipe early and the upstream never sees SIGPIPE. Piping that
# single count line into `grep -qv '^0$'` reads one short line, which is
# not a pipe-buffer risk. Confirmed 0/10 false negatives at every size
# tested, including 19MB, with this form.
saw_api()    { grep -E ':dev:' "$LOG" 2>/dev/null | grep -v ':dev:worker:' | grep -cE "$NJA_READY_API" | grep -qv '^0$'; }
saw_worker() { grep -E ':dev:worker:' "$LOG" 2>/dev/null | grep -cE "$NJA_READY_WORKER" | grep -qv '^0$'; }
saw_web()    { grep -cE "$NJA_READY_WEB" "$LOG" 2>/dev/null | grep -qv '^0$'; }
saw_fatal()  { grep -cE "$FATAL" "$LOG" 2>/dev/null | grep -qv '^0$'; }

# A repo whose worker never logs a recognizable ready line degrades to a
# WARN+PASS (below), never a failure — but without a bound, that degrade
# would only happen after burning the ENTIRE --timeout (minutes, at the
# 180s default), which is indistinguishable from the hang this tool exists
# to detect. Once api+web are both ready, the worker signal gets a short
# grace window instead of the rest of --timeout; NJA_WORKER_GRACE is
# overridable for a repo whose worker is just genuinely slower to boot.
#
# The window is chosen from EVIDENCE rather than fixed, because the two cases it
# has to separate are very different:
#   - no `dev:worker` stream in the log at all -> the repo has no worker, so
#     degrade fast (this is what the bound exists for).
#   - a `dev:worker` stream IS present but has not signalled yet -> the worker
#     really is booting, and 10s is nowhere near enough. MEASURED 2026-08-31 in
#     only35: the api reported ready at 10:51:15.609 and the worker's own
#     "Worker process started" landed at 10:51:55.202 — a 39.6s gap, because the
#     worker compiles its own tsconfig and boots a second Nest graph. Every run
#     there warned "worker readiness signal never matched" even though the
#     worker was healthy and the pattern matched, purely because of this window.
# A fixed window cannot bound the second case either: only35's worker loads ten
# ML models before it signals, so how long it takes is a property of the machine,
# not a constant. The window is therefore PROGRESS-BASED — every time the worker
# stream emits a new line the deadline is pushed out again, so "slow but alive"
# keeps waiting while "stuck and silent" still degrades promptly. --timeout
# remains the hard ceiling.
# An explicit NJA_WORKER_GRACE always wins over all of it.
NJA_WORKER_GRACE_NO_STREAM=10
NJA_WORKER_GRACE_QUIET=45

api_ok=0; web_ok=0; worker_ok=0; waited=0; worker_deadline=""
while [ "$waited" -lt "$TIMEOUT" ]; do
  if saw_fatal; then
    nja_fail "fatal pattern in the dev log:"
    grep -E "$FATAL" "$LOG" | head -5 | sed 's/^/        /'
    nja_say ""
    nja_say "  If this is UnknownDependenciesException, it is almost certainly a duplicate"
    nja_say "  peer resolution — run nja-deps-doctor.sh and read hazards.md §1."
    finish 2
  fi

  [ "$api_ok" -eq 0 ] && saw_api && port_busy "$API_PORT" && { api_ok=1; nja_ok "api ready (port $API_PORT)"; }
  [ "$web_ok" -eq 0 ] && saw_web && port_busy "$WEB_PORT" && { web_ok=1; nja_ok "web ready (port $WEB_PORT)"; }
  [ "$worker_ok" -eq 0 ] && saw_worker && { worker_ok=1; nja_ok "worker ready"; }

  [ "$api_ok" -eq 1 ] && [ "$web_ok" -eq 1 ] && [ "$worker_ok" -eq 1 ] && break

  if [ "$api_ok" -eq 1 ] && [ "$web_ok" -eq 1 ] && [ "$worker_ok" -eq 0 ]; then
    _wlines=$(grep -cE ':dev:worker:' "$LOG" 2>/dev/null || echo 0)
    if [ -n "${NJA_WORKER_GRACE:-}" ]; then
      _grace="$NJA_WORKER_GRACE"
    elif [ "$_wlines" -gt 0 ]; then
      _grace="$NJA_WORKER_GRACE_QUIET"
    else
      _grace="$NJA_WORKER_GRACE_NO_STREAM"
    fi
    # a new worker line means it is still booting: push the deadline out again
    if [ -z "$worker_deadline" ] || [ "$_wlines" -gt "${worker_lines_seen:-0}" ]; then
      worker_lines_seen="$_wlines"
      worker_deadline=$((waited + _grace))
    fi
    [ "$waited" -ge "$worker_deadline" ] && break
  fi

  if ! group_alive "$PGID"; then
    nja_fail "the dev stack exited before becoming ready"
    tail -60 "$LOG" | sed 's/^/        /'
    finish 2
  fi

  sleep 2; waited=$((waited + 2))
done

if [ "$api_ok" -eq 0 ] || [ "$web_ok" -eq 0 ]; then
  nja_fail "not ready after ${TIMEOUT}s (api=$api_ok web=$web_ok worker=$worker_ok)"
  tail -60 "$LOG" | sed 's/^/        /'
  finish 2
fi

# An unmatched log regex must never masquerade as a boot failure.
if [ "$worker_ok" -eq 0 ]; then
  nja_warn "worker readiness signal never matched — api and web booted and no fatal"
  nja_say "        pattern appeared, so this is reported as a PASS. Override the pattern"
  nja_say "        with NJA_READY_WORKER if this repo logs differently."
fi

nja_ok "dev stack booted"
finish 0
