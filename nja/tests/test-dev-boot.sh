#!/usr/bin/env bash
# Tests for nja-dev-boot.sh — Task 9 (launch/teardown) + Task 10 (readiness,
# fatal-pattern detection, final exit-code selection).
#
# Task 9 delivers process-group launch + verified teardown. Task 10 appends
# the readiness poll loop that calls finish() — the "clean boot exits 0" and
# "ports free" assertions Task 9 deliberately deferred (they could not pass
# until finish() was ever reached) are restored below, alongside the new
# readiness-discrimination, fatal-pattern, and occupied-port coverage.
#
# What the Task 9 portion of this suite asserts, and why it is enough for
# that task:
#   - --help, usage, and the `shift 2` regression guard (option parsing)
#   - the bystander test: the single most important test in this plan. It
#     proves the process-group kill path (a) actually reaps every group
#     member, including one that ignores SIGINT, and (b) never reaches
#     outside that group — the one thing a name/pattern kill cannot promise
#     and the reason this whole approach exists. It is made non-flaky (I1)
#     by waiting for the fixture's own log output before teardown happens,
#     so its SIGINT-ignoring children are confirmed to actually exist first.
#   - exit 4 ("teardown unverified") is reachable and reported, not silent
#     (I2), via a test-only NJA_FORCE_TEARDOWN_FAIL hook — a process group
#     that genuinely survives SIGKILL cannot be built portably.
#   - SIGINT/SIGTERM tear down and then terminate the script promptly (I3),
#     rather than reaping the group and continuing to run.
#   - this suite's own bounded-wait timeout paths reap the process group
#     they caused to exist rather than orphaning it (I4) — demonstrated by
#     deliberately forcing one to fire and checking no stray group/ports
#     remain afterward.
#   - the script source contains no pkill / killall / pgrep / broad `ps`
#     listing, ever (defense in depth; the bystander test is the real net).

_ndb_boot="$NJA_SCRIPTS_DIR/nja-dev-boot.sh"
_ndb_fix="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/fake-dev"

# _ndb_bounded_exit <expected-exit> <label> <max-ticks-of-0.1s> -- <cmd...>
# Regression guard for the `shift 2` hang bug (mirrors _dswp_bounded_exit in
# test-deps-sweep.sh, with its own prefix since suites are sourced into one
# namespace): a value-taking option with no value left $1 unshifted and spun
# the parser's while-loop forever. Runs the command in the background and
# polls briefly instead of blocking on it directly, so a reintroduced hang
# fails the assertion instead of hanging the whole suite. Kills only the
# exact PID this function started — never a name/pattern kill. No process
# group is at stake here: arg parsing fails (or would hang) before the
# script ever reaches `set -m`.
_ndb_bounded_exit() {
  local expected="$1" label="$2" ticks="$3"; shift 4   # drop expected, label, ticks, the literal --
  local out; out="$(mktemp -t nja-ndb-out)"
  "$@" >"$out" 2>&1 &
  local pid=$!
  local n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt "$ticks" ]; do
    sleep 0.1
    n=$((n + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    t_fail "$label" "process pid $pid did not exit within $((ticks))00ms — killed it"
  else
    wait "$pid"
    local code=$?
    if [ "$code" -eq "$expected" ]; then t_pass "$label"
    else t_fail "$label" "expected exit $expected got $code: $(cat "$out" | head -c 200)"; fi
  fi
  rm -f "$out"
}

# _ndb_reap_group <pgid> — TERM then KILL a process group this suite itself
# caused to exist (never a name/pattern). Used only from the fallback paths
# below, when the boot script under test cannot be trusted to have torn its
# own group down (I4: a bare `kill -9` on just the wrapper process orphans
# the group it launched, since SIGKILL on the wrapper skips its EXIT trap).
_ndb_reap_group() {
  local pgid="$1"
  # Same structural guard as teardown() in nja-dev-boot.sh: reject empty,
  # non-numeric, and exactly "1" before ever signalling, not just "non-empty".
  case "$pgid" in
    ''|*[!0-9]*|1) return 0 ;;
  esac
  kill -TERM -- "-$pgid" 2>/dev/null
  local w=0
  while [ -n "$(ps -o pid= -g "$pgid" 2>/dev/null)" ] && [ "$w" -lt 50 ]; do
    sleep 0.1; w=$((w + 1))
  done
  if [ -n "$(ps -o pid= -g "$pgid" 2>/dev/null)" ]; then
    kill -KILL -- "-$pgid" 2>/dev/null
    sleep 0.2
  fi
}

# _ndb_boot_bounded <out-file> <max-ticks-of-0.1s> -- <cmd...>
# Runs a dev-boot invocation bounded, so a regression that hangs it fails
# this suite instead of hanging it (I4). Parses the "group:" and "log:"
# lines the script prints as soon as they appear — not only after giving up
# — so that if the bound does expire, the process group and log file it
# created are known and can be reaped/cleaned up rather than orphaned.
# Sets the globals _ndb_last_code (the script's real exit status, or 124 if
# the bound expired and we had to force it), _ndb_last_pgid, _ndb_last_log.
_ndb_boot_bounded() {
  local out="$1" ticks="$2"; shift 3   # drop out, ticks, the literal --
  "$@" >"$out" 2>&1 &
  local pid=$!
  local n=0 pg="" lg=""
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt "$ticks" ]; do
    [ -z "$pg" ] && pg="$(awk '/^  group:/ { print $2 }' "$out" 2>/dev/null)"
    [ -z "$lg" ] && lg="$(awk '/^  log:/ { print $2 }' "$out" 2>/dev/null)"
    sleep 0.1
    n=$((n + 1))
  done
  [ -z "$pg" ] && pg="$(awk '/^  group:/ { print $2 }' "$out" 2>/dev/null)"
  [ -z "$lg" ] && lg="$(awk '/^  log:/ { print $2 }' "$out" 2>/dev/null)"
  # The bound can expire in the window between the script LAUNCHING the dev
  # command (its fixture has already bound the ports) and it PRINTING the
  # "group:" line. Reaping with an empty pgid there is a no-op, so the kill -9
  # below hits only the wrapper and ORPHANS the group — which keeps the fixture
  # holding the ports and makes every subsequent run of this suite fail I4's
  # port precondition. That is a coin flip on machine load, and it is why this
  # suite appeared to fail intermittently. Never force-terminate blind: if the
  # process is alive but has not announced its group yet, wait (bounded) for the
  # announcement so there is always something to reap.
  if kill -0 "$pid" 2>/dev/null && [ -z "$pg" ]; then
    local extra=0
    while kill -0 "$pid" 2>/dev/null && [ -z "$pg" ] && [ "$extra" -lt 100 ]; do
      sleep 0.1
      pg="$(awk '/^  group:/ { print $2 }' "$out" 2>/dev/null)"
      [ -z "$lg" ] && lg="$(awk '/^  log:/ { print $2 }' "$out" 2>/dev/null)"
      extra=$((extra + 1))
    done
  fi
  if kill -0 "$pid" 2>/dev/null; then
    _ndb_reap_group "$pg"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    _ndb_last_code=124
  else
    wait "$pid" 2>/dev/null
    _ndb_last_code=$?
  fi
  _ndb_last_pgid="$pg"
  _ndb_last_log="$lg"
}

t_assert_exit 0 "dev-boot --help exits 0" -- bash "$_ndb_boot" --help

_ndb_outside="$(mktemp -d -t nja-outside)"
t_assert_contains "$(bash "$_ndb_boot" --root "$_ndb_outside" 2>&1)" "not an nja project" \
  "dev-boot is inert outside nja repos"
rm -rf "$_ndb_outside"

# regression: a trailing value-taking option with nothing after it must not hang
_ndb_bounded_exit 1 "--root with no value exits 1, not a hang" 30 -- bash "$_ndb_boot" --root

# regression: a flag where a value belongs must not be silently swallowed
t_assert_exit 1 "--root --help rejects the flag as its value" -- bash "$_ndb_boot" --root --help

# --timeout must additionally reject a non-integer value
t_assert_exit 1 "non-integer --timeout exits 1" -- bash "$_ndb_boot" --timeout notanumber

# regression (I4b): a bare trailing --timeout must not hang either. --timeout
# is the one option with a SECOND guard stacked behind require_optarg's own
# (the integer check just above, at nja-dev-boot.sh:104) — that makes its
# no-hang path the least verified of the three value-taking options before
# this test existed, and this is the documented CPU-spin bug's own option.
# require_optarg must catch the bare trailing flag before the integer check
# ever runs, exactly as it already does for --root above.
_ndb_bounded_exit 1 "--timeout with no value exits 1, not a hang (I4b)" 30 -- bash "$_ndb_boot" --timeout

# ── the bystander test ────────────────────────────────────────────────────────
# An unrelated long-lived process, of exactly the kind a name-pattern kill
# would destroy. It MUST survive. NJA_DEV_CMD spawns a fixture whose children
# ignore SIGINT (but not SIGTERM), so this also proves teardown reaches every
# process-group member, not just the leader.
_ndb_repo="$(t_mkrepo)"

_ndb_bystander_out="$(mktemp -t nja-bystander)"
bash -c 'while :; do sleep 1; done' >"$_ndb_bystander_out" 2>&1 &
_ndb_bystander=$!

_ndb_boot_out="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out" 300 -- \
  env API_PORT=13950 PORT=13951 NJA_DEV_CMD="bash $_ndb_fix/stubborn.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo" --timeout 30

if [ "$_ndb_last_code" -eq 124 ]; then
  t_fail "dev-boot's own process exits after teardown" \
    "boot script did not exit within 30s — killed it and reaped its group $_ndb_last_pgid"
else
  t_pass "dev-boot's own process exits after teardown"
fi

# I1: the race this used to be. Confirm the fixture's children genuinely
# existed before teardown happened — not just that a no-op teardown "passed".
if [ -n "$_ndb_last_log" ] && [ -s "$_ndb_last_log" ]; then
  t_pass "the fixture's log is non-empty at teardown time (I1)"
else
  t_fail "the fixture's log is non-empty at teardown time (I1)" \
    "log path='$_ndb_last_log' — the fixture's children never got to run before teardown"
fi
_ndb_log_content=""
[ -n "$_ndb_last_log" ] && _ndb_log_content="$(cat "$_ndb_last_log" 2>/dev/null)"
t_assert_contains "$_ndb_log_content" "Ready in" \
  "the fixture's SIGINT-ignoring children existed before teardown (I1: stubborn.sh's ready line)"

# The process group the script created must be gone.
if [ -z "$_ndb_last_pgid" ]; then
  t_fail "dev-boot's process group is gone after teardown" \
    "could not find a group pgid in boot output: $(cat "$_ndb_boot_out" | head -c 300)"
elif [ -n "$(ps -o pid= -g "$_ndb_last_pgid" 2>/dev/null)" ]; then
  t_fail "dev-boot's process group is gone after teardown" \
    "pgid $_ndb_last_pgid still has members: $(ps -o pid,args -g "$_ndb_last_pgid" 2>/dev/null | head -c 300)"
else
  t_pass "dev-boot's process group is gone after teardown"
fi

# The bystander — started before the boot script, sharing nothing with its
# process group — must still be alive. This is the whole point of the group
# handle over a name/pattern kill.
if kill -0 "$_ndb_bystander" 2>/dev/null; then
  t_pass "unrelated process survived teardown"
else
  t_fail "unrelated process survived teardown" "the bystander was killed — a pattern kill leaked"
fi
kill "$_ndb_bystander" 2>/dev/null
wait "$_ndb_bystander" 2>/dev/null

rm -f "$_ndb_bystander_out" "$_ndb_boot_out"
[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -rf "$_ndb_repo"

# ── I4: this suite's own timeout path must reap the group, not orphan it ────
# Deliberately bounds the wait shorter than the boot script needs (it has a
# multi-second settle wait — see nja-dev-boot.sh — before it naturally tears
# down), forcing _ndb_boot_bounded's own force-terminate branch to fire even
# though the boot script isn't actually buggy. Proves that branch reaps the
# process group it caused to exist — previously, a bare `kill -9` on the
# wrapper process orphaned a running four-member group holding both ports.
_ndb_repo4="$(t_mkrepo)"
_ndb_boot_out4="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out4" 5 -- \
  env API_PORT=13952 PORT=13953 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo4" --timeout 30

if [ "$_ndb_last_code" -eq 124 ] && [ -n "$_ndb_last_pgid" ]; then
  t_pass "the harness's own timeout path fires and captures a real pgid (I4 setup)"
else
  t_fail "the harness's own timeout path fires and captures a real pgid (I4 setup)" \
    "code=$_ndb_last_code pgid=$_ndb_last_pgid — did not force the timeout path as expected"
fi

if [ -n "$_ndb_last_pgid" ] && [ -z "$(ps -o pid= -g "$_ndb_last_pgid" 2>/dev/null)" ]; then
  t_pass "no stray process group after the harness's forced timeout reap (I4)"
else
  t_fail "no stray process group after the harness's forced timeout reap (I4)" \
    "pgid=$_ndb_last_pgid members: $(ps -o pid,args -g "$_ndb_last_pgid" 2>/dev/null | head -c 300)"
fi

if lsof -ti :13952 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13953 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "both ports free after the harness's forced timeout reap (I4)" "a port is still bound"
else
  t_pass "both ports free after the harness's forced timeout reap (I4)"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out4"
rm -rf "$_ndb_repo4"

# ── I2: exit 4 (teardown unverified) is reachable and reported, not silent ──
# A process group that genuinely survives SIGKILL cannot be built portably,
# so NJA_FORCE_TEARDOWN_FAIL makes teardown_verified() report failure while
# the real teardown still runs for real underneath it — this exercises the
# exit-4 contract and its diagnostic without ever leaving an actual stray
# process.
_ndb_repo5="$(t_mkrepo)"
_ndb_boot_out5="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out5" 150 -- \
  env API_PORT=13954 PORT=13955 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" NJA_FORCE_TEARDOWN_FAIL=1 \
  bash "$_ndb_boot" --root "$_ndb_repo5" --timeout 30

t_assert_eq "4" "$_ndb_last_code" "NJA_FORCE_TEARDOWN_FAIL makes teardown-unverified reachable, exit 4 (I2)"
t_assert_contains "$(cat "$_ndb_boot_out5" 2>/dev/null)" "TEARDOWN UNVERIFIED" \
  "the exit-4 path reports the diagnostic instead of exiting silently (I2)"

if [ -n "$_ndb_last_pgid" ] && [ -z "$(ps -o pid= -g "$_ndb_last_pgid" 2>/dev/null)" ]; then
  t_pass "a forced-unverified report does not itself leave a stray group (I2)"
else
  t_fail "a forced-unverified report does not itself leave a stray group (I2)" \
    "pgid=$_ndb_last_pgid members: $(ps -o pid,args -g "$_ndb_last_pgid" 2>/dev/null | head -c 300)"
fi

if lsof -ti :13954 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13955 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "ports free after a forced-unverified report (I2)" "a port is still bound"
else
  t_pass "ports free after a forced-unverified report (I2)"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out5"
rm -rf "$_ndb_repo5"

# ── I3: SIGINT tears down AND exits non-zero, promptly ──────────────────────
# Previously the INT/TERM trap tore the group down but never called exit,
# so bash resumed the interrupted script and it kept running for several
# more seconds before exiting 0. Measures elapsed time so a regression back
# to that behavior fails this assertion instead of merely being slow.
#
# `set -m` here in THIS launcher (not the script under test) is required for
# the signal to even arrive: POSIX/bash automatically disposes SIGINT (and
# SIGQUIT) as ignored for a plain `cmd &` background job with no job
# control, and a signal ignored on entry to a (non-interactive) shell can
# never be trapped or reset by that shell — the script's own `trap ... INT`
# would be silently inert no matter what it does. Backgrounding under job
# control instead gives the boot script its own process group with normal
# signal disposition, so `kill -INT` on its captured PID actually reaches
# its trap. (Confirmed by direct comparison: identical invocation without
# `set -m` here never runs the script's INT trap at all — teardown still
# happens, but only via the ordinary EXIT-trap fall-through, which is not
# what this assertion is testing.)
#
# Uses dev-ok.sh, not stubborn.sh: stubborn.sh has zero artificial delay
# before it prints its ready lines, so the boot script (whether still in its
# Task 9 settle-wait or, since Task 10, its readiness poll) can complete and
# tear down naturally within roughly the same ~100ms it takes this loop to
# detect the "group:" line and send SIGINT — a real race that this assertion
# lost most runs, passing for the wrong reason (natural completion, not the
# signal path) or failing outright. dev-ok.sh's artificial delay before its
# ready lines (see the fixture — widened once already, when Task 10's
# readiness poll made natural completion fast enough to start racing this
# same signal again) guarantees the script is still alive, boot in progress,
# when SIGINT arrives.
_ndb_repo6="$(t_mkrepo)"
_ndb_boot_out6="$(mktemp -t nja-boot-out)"
set -m
env API_PORT=13956 PORT=13957 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo6" --timeout 30 >"$_ndb_boot_out6" 2>&1 &
_ndb_pid6=$!
set +m

_ndb_n=0
_ndb_pgid6=""
while [ -z "$_ndb_pgid6" ] && [ "$_ndb_n" -lt 100 ]; do
  _ndb_pgid6="$(awk '/^  group:/ { print $2 }' "$_ndb_boot_out6" 2>/dev/null)"
  [ -n "$_ndb_pgid6" ] && break
  sleep 0.1
  _ndb_n=$((_ndb_n + 1))
done

if [ -z "$_ndb_pgid6" ]; then
  t_fail "SIGINT tears down and exits non-zero, promptly (I3)" \
    "boot script never printed its group pgid within 10s"
  kill -9 "$_ndb_pid6" 2>/dev/null
  wait "$_ndb_pid6" 2>/dev/null
else
  _ndb_start6=$SECONDS
  kill -INT "$_ndb_pid6" 2>/dev/null
  _ndb_n=0
  while kill -0 "$_ndb_pid6" 2>/dev/null && [ "$_ndb_n" -lt 100 ]; do
    sleep 0.1
    _ndb_n=$((_ndb_n + 1))
  done
  if kill -0 "$_ndb_pid6" 2>/dev/null; then
    _ndb_reap_group "$_ndb_pgid6"
    kill -9 "$_ndb_pid6" 2>/dev/null
    wait "$_ndb_pid6" 2>/dev/null
    t_fail "SIGINT tears down and exits non-zero, promptly (I3)" \
      "boot script did not exit within 10s of SIGINT — reaped its group $_ndb_pgid6 directly"
  else
    wait "$_ndb_pid6"
    _ndb_code6=$?
    _ndb_elapsed6=$((SECONDS - _ndb_start6))
    if [ "$_ndb_code6" -ne 0 ] \
      && [ -z "$(ps -o pid= -g "$_ndb_pgid6" 2>/dev/null)" ] \
      && [ "$_ndb_elapsed6" -le 5 ]; then
      t_pass "SIGINT tears down and exits non-zero, promptly (I3)"
    else
      t_fail "SIGINT tears down and exits non-zero, promptly (I3)" \
        "exit=$_ndb_code6 elapsed=${_ndb_elapsed6}s group-members=$(ps -o pid= -g "$_ndb_pgid6" 2>/dev/null)"
    fi
  fi
fi

if lsof -ti :13956 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13957 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "ports free after SIGINT teardown (I3)" "a port is still bound"
else
  t_pass "ports free after SIGINT teardown (I3)"
fi

_ndb_log6="$(awk '/^  log:/ { print $2 }' "$_ndb_boot_out6" 2>/dev/null)"
[ -n "$_ndb_log6" ] && rm -f "$_ndb_log6"
rm -f "$_ndb_boot_out6"
rm -rf "$_ndb_repo6"

# ── the script must contain no pattern-kill, ever ────────────────────────────
_ndb_src="$(cat "$_ndb_boot")"
t_assert_not_contains "$_ndb_src" "pkill" "dev-boot never calls pkill"
t_assert_not_contains "$_ndb_src" "killall" "dev-boot never calls killall"
t_assert_not_contains "$_ndb_src" "pgrep" "dev-boot never calls pgrep"
t_assert_not_contains "$_ndb_src" "ps aux" "dev-boot never lists all processes via ps aux (a ps|grep|kill precursor)"
t_assert_not_contains "$_ndb_src" "ps -ef" "dev-boot never lists all processes via ps -ef (a ps|grep|kill precursor)"
t_assert_not_contains "$_ndb_src" "ps -A" "dev-boot never lists all processes via ps -A (a ps|grep|kill precursor)"
t_assert_not_contains "$_ndb_src" "ps -ax" "dev-boot never lists all processes via ps -ax (a ps|grep|kill precursor)"

# Review round 1: the four literal-substring guards above miss any other
# `ps` invocation (e.g. `ps -o ... -u <uid>` or `ps -o ... -p <pid-list>`)
# once it's piped into a filter that could then feed a kill — exactly the
# shape a real pattern-killing teardown took during review, and it passed
# all seven guards that existed at the time. This scans the actual script
# file (not just the concatenated source string) for `ps` followed by a
# pipe into grep/awk/xargs, which the legitimate `ps -o pid= -g "$PGID"`
# idiom used throughout this script never does (it's never piped anywhere).
if grep -nE 'ps[^|]*\|[[:space:]]*(grep|awk|xargs)' "$_ndb_boot" >/dev/null 2>&1; then
  t_fail "dev-boot never pipes ps output into grep/awk/xargs (a pattern-kill precursor)" \
    "$(grep -nE 'ps[^|]*\|[[:space:]]*(grep|awk|xargs)' "$_ndb_boot")"
else
  t_pass "dev-boot never pipes ps output into grep/awk/xargs (a pattern-kill precursor)"
fi

# ── Task 10: readiness discrimination, fatal patterns, exit codes ───────────
#
# _ndb_squat <port> <label> — binds a port in the background with python3,
# never `nc -l` (nc's listen flag is not portable across BSD/GNU builds, and
# a squatter that silently fails to bind makes every port assertion that
# depends on it vacuous — the single most important assertion in this plan,
# "the squatting process was left alone", must never cry wolf).
#
# Three things this earns its keep on:
#   1. Checks the port is free BEFORE binding. A port left bound by an
#      earlier/interrupted run must surface as "port already bound — a leak
#      from an earlier run", not as a python3 crash mid-test.
#   2. Redirects python3's stdout/stderr to /dev/null before backgrounding.
#      Without this, capturing its PID via `$(_ndb_squat ...)` deadlocks the
#      whole suite: command substitution reads until the pipe sees EOF, and
#      a backgrounded child that inherits the pipe's write end (and never
#      exits, by design — it holds the port until killed) means that EOF
#      never comes. This was the actual cause of a suite-wide hang: the
#      python3 process only "worked" by accident when it crashed early on
#      Errno 48 (address in use), closing the pipe; a genuinely successful
#      bind hung forever.
#   3. Confirms BOTH the process is alive and the port is truly LISTENing
#      before declaring success, and fails loudly/immediately (not silently)
#      otherwise — callers must skip any assertion that depends on the
#      squat when this returns non-zero, since it is otherwise meaningless.
# Sets _ndb_squat_pid on success (empty on failure).
_ndb_squat() {
  local port="$1" label="$2" n=0
  _ndb_squat_pid=""

  if lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    t_fail "$label: port $port bound before the squat" \
      "port $port is already bound — a leak from an earlier run, not this test"
    return 1
  fi

  python3 -c '
import socket, sys, time
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
while True:
    time.sleep(1)
' "$port" >/dev/null 2>&1 &
  _ndb_squat_pid=$!

  while kill -0 "$_ndb_squat_pid" 2>/dev/null && ! lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1 && [ "$n" -lt 50 ]; do
    sleep 0.1; n=$((n + 1))
  done

  if kill -0 "$_ndb_squat_pid" 2>/dev/null && lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    t_pass "$label: squatter genuinely bound port $port"
    return 0
  fi

  t_fail "$label: squatter genuinely bound port $port" \
    "alive=$(kill -0 "$_ndb_squat_pid" 2>/dev/null && echo yes || echo no) listening=$(lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1 && echo yes || echo no) — skipping the assertions that depend on it"
  kill -9 "$_ndb_squat_pid" 2>/dev/null
  wait "$_ndb_squat_pid" 2>/dev/null
  _ndb_squat_pid=""
  return 1
}

# _ndb_unsquat <port> <pid> <label> — kill exactly this pid (never a
# pattern) and confirm the port it held is free again afterward, so a leak
# surfaces here as an obvious diagnostic instead of corrupting a later test.
_ndb_unsquat() {
  local port="$1" pid="$2" label="$3" n=0
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  while lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1 && [ "$n" -lt 30 ]; do
    sleep 0.1; n=$((n + 1))
  done
  if lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    t_fail "$label: port $port free after cleanup" "still bound after killing pid $pid"
  else
    t_pass "$label: port $port free after cleanup"
  fi
}

# ── clean boot: readiness discrimination + the two Task 9 deferred asserts ──
# api vs worker readiness are told apart purely by turbo's log-line prefix
# (":dev:" vs ":dev:worker:"), which is what dev-ok.sh's three ready lines
# exercise. "clean boot exits 0" and "reports ports free" were removed from
# Task 9's suite because finish() was never reached then; restored here.
_ndb_repo7="$(t_mkrepo)"
_ndb_boot_out7="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out7" 300 -- \
  env API_PORT=13958 PORT=13959 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo7" --timeout 30

t_assert_eq "0" "$_ndb_last_code" "clean boot exits 0"
_ndb_out7="$(cat "$_ndb_boot_out7" 2>/dev/null)"
t_assert_contains "$_ndb_out7" "api ready" "clean boot reports api ready (not the worker's :dev:worker: lines)"
t_assert_contains "$_ndb_out7" "web ready" "clean boot reports web ready"
t_assert_contains "$_ndb_out7" "worker ready" "clean boot reports worker ready"
t_assert_contains "$_ndb_out7" "ports free" "clean boot reports the ports being released"

if lsof -ti :13958 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13959 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "ports free after clean boot" "a port is still bound"
else
  t_pass "ports free after clean boot"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out7"
rm -rf "$_ndb_repo7"

# ── regression: readiness must still be detected past the pipe-buffer size ──
# Review round 1 found that saw_api()/saw_worker() ended their pipeline in
# `grep -q`, which under `pipefail` false-negatives once an upstream stage
# is still mid-write to a pipe holding more than the kernel's pipe buffer
# (~16KB on this platform) when the match is found and the reader closes
# early (SIGPIPE on the writer, which pipefail then reports as the
# pipeline's status). dev-biglog.sh reproduces the shape that triggers it:
# ready lines first, then ~1.4MB of turbo-shaped (":dev:"-prefixed)
# trailing chatter — exactly what a real web compile does after api's own
# ready line has already landed in the log.
_ndb_repo13="$(t_mkrepo)"
_ndb_boot_out13="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out13" 300 -- \
  env API_PORT=13970 PORT=13971 NJA_DEV_CMD="bash $_ndb_fix/dev-biglog.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo13" --timeout 30

t_assert_eq "0" "$_ndb_last_code" "readiness is detected past the pipe-buffer size (large log)"
_ndb_out13="$(cat "$_ndb_boot_out13" 2>/dev/null)"
t_assert_contains "$_ndb_out13" "api ready" "large-log boot reports api ready"
t_assert_contains "$_ndb_out13" "web ready" "large-log boot reports web ready"
t_assert_contains "$_ndb_out13" "worker ready" "large-log boot reports worker ready"

if lsof -ti :13970 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13971 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "ports free after the large-log boot" "a port is still bound"
else
  t_pass "ports free after the large-log boot"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out13"
rm -rf "$_ndb_repo13"

# ── an unmatched worker regex must degrade to WARN quickly, not silently ────
# burn the rest of --timeout. Review round 1: with api+web ready at ~5s,
# an unmatched worker pattern used to keep the poll loop alive until the
# full --timeout — indistinguishable from a hang at the 180s default.
# NJA_READY_WORKER is deliberately set to a pattern dev-ok.sh's log can
# never contain, forcing the grace-timeout path.
_ndb_repo14="$(t_mkrepo)"
_ndb_boot_out14="$(mktemp -t nja-boot-out)"
_ndb_start14=$SECONDS
_ndb_boot_bounded "$_ndb_boot_out14" 300 -- \
  env API_PORT=13972 PORT=13973 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" \
  NJA_READY_WORKER='THIS_PATTERN_WILL_NEVER_APPEAR_XYZ' \
  bash "$_ndb_boot" --root "$_ndb_repo14" --timeout 30
_ndb_elapsed14=$((SECONDS - _ndb_start14))

t_assert_eq "0" "$_ndb_last_code" "an unmatched worker signal still exits 0 (PASS+WARN, not a failure)"
t_assert_contains "$(cat "$_ndb_boot_out14" 2>/dev/null)" "worker readiness signal never matched" \
  "an unmatched worker signal prints its WARN"
if [ "$_ndb_elapsed14" -lt 25 ]; then
  t_pass "an unmatched worker signal degrades to WARN well inside --timeout, not after it"
else
  t_fail "an unmatched worker signal degrades to WARN well inside --timeout, not after it" \
    "took ${_ndb_elapsed14}s of a 30s timeout — looks like it waited out the full budget"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out14"
rm -rf "$_ndb_repo14"

# ── timeout: a stack that never becomes ready still tears down and exits 2 ──
_ndb_repo8="$(t_mkrepo)"
_ndb_boot_out8="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out8" 200 -- \
  env API_PORT=13960 PORT=13961 NJA_DEV_CMD="bash $_ndb_fix/dev-hang.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo8" --timeout 6

t_assert_eq "2" "$_ndb_last_code" "a boot that never becomes ready exits 2"
t_assert_contains "$(cat "$_ndb_boot_out8" 2>/dev/null)" "ports free" "teardown still runs after a timeout"

if lsof -ti :13960 -sTCP:LISTEN >/dev/null 2>&1 || lsof -ti :13961 -sTCP:LISTEN >/dev/null 2>&1; then
  t_fail "ports free after a readiness timeout" "a port is still bound"
else
  t_pass "ports free after a readiness timeout"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out8"
rm -rf "$_ndb_repo8"

# ── fatal pattern short-circuits the wait ────────────────────────────────────
# Pins the timing: a fatal log line must be caught well inside the timeout,
# not merely eventually. --timeout is 60s; the assertion requires < 30s.
_ndb_repo9="$(t_mkrepo)"
_ndb_boot_out9="$(mktemp -t nja-boot-out)"
_ndb_start9=$SECONDS
_ndb_boot_bounded "$_ndb_boot_out9" 400 -- \
  env API_PORT=13962 PORT=13963 NJA_DEV_CMD="bash $_ndb_fix/dev-fatal.sh" \
  bash "$_ndb_boot" --root "$_ndb_repo9" --timeout 60
_ndb_elapsed9=$((SECONDS - _ndb_start9))

t_assert_eq "2" "$_ndb_last_code" "a fatal log pattern exits 2"
t_assert_contains "$(cat "$_ndb_boot_out9" 2>/dev/null)" "UnknownDependenciesException" \
  "the fatal pattern is quoted in the report"
if [ "$_ndb_elapsed9" -lt 30 ]; then
  t_pass "fatal pattern short-circuits the wait"
else
  t_fail "fatal pattern short-circuits the wait" "took ${_ndb_elapsed9}s of a 60s timeout"
fi

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out9"
rm -rf "$_ndb_repo9"

# ── occupied port aborts with exit 1, and the squatter is left alone ────────
# The squatter is a plain unrelated process holding a port dev-boot wants —
# exactly the kind of thing a name/pattern kill would be tempted to reap.
# It must survive untouched; dev-boot's precondition check must simply
# refuse to start.
_ndb_repo10="$(t_mkrepo)"
_ndb_p10=13964
if _ndb_squat "$_ndb_p10" "occupied-port squatter"; then
  _ndb_pid10="$_ndb_squat_pid"

  t_assert_exit 1 "an occupied port aborts with exit 1" -- \
    env API_PORT="$_ndb_p10" PORT=13965 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" \
    bash "$_ndb_boot" --root "$_ndb_repo10" --timeout 10

  if kill -0 "$_ndb_pid10" 2>/dev/null; then
    t_pass "the squatting process was left alone"
  else
    t_fail "the squatting process was left alone" "we killed a process we did not start"
  fi
  _ndb_unsquat "$_ndb_p10" "$_ndb_pid10" "occupied-port squatter"
fi
rm -rf "$_ndb_repo10"

# ── NJA_FORCE_TEARDOWN_FAIL requires an explicit "1"/"true" ─────────────────
# Previously any non-empty value (including "0") activated the hook. "0"
# must now be a no-op: a clean boot with it set still exits 0.
_ndb_repo11="$(t_mkrepo)"
_ndb_boot_out11="$(mktemp -t nja-boot-out)"
_ndb_boot_bounded "$_ndb_boot_out11" 300 -- \
  env API_PORT=13966 PORT=13967 NJA_DEV_CMD="bash $_ndb_fix/dev-ok.sh" NJA_FORCE_TEARDOWN_FAIL=0 \
  bash "$_ndb_boot" --root "$_ndb_repo11" --timeout 30

t_assert_eq "0" "$_ndb_last_code" "NJA_FORCE_TEARDOWN_FAIL=0 does not activate the force-fail hook"

[ -n "$_ndb_last_log" ] && rm -f "$_ndb_last_log"
rm -f "$_ndb_boot_out11"
rm -rf "$_ndb_repo11"

# ── a precondition failure is never reclassified as "teardown unverified" ───
# NJA_FORCE_TEARDOWN_FAIL only means anything once a process group actually
# exists. With a busy port, dev-boot never reaches `set -m` — PGID stays ""
# — so forcing the hook must NOT turn this exit 1 into exit 4, and must not
# print a diagnostic built around an empty pgid.
_ndb_repo12="$(t_mkrepo)"
_ndb_p12=13968
if _ndb_squat "$_ndb_p12" "precondition-reclass squatter"; then
  _ndb_pid12="$_ndb_squat_pid"

  _ndb_out12="$(env API_PORT="$_ndb_p12" PORT=13969 NJA_FORCE_TEARDOWN_FAIL=1 \
    bash "$_ndb_boot" --root "$_ndb_repo12" --timeout 10 2>&1)"
  _ndb_code12=$?

  t_assert_eq "1" "$_ndb_code12" \
    "a precondition failure with NJA_FORCE_TEARDOWN_FAIL=1 still exits 1, not reclassified to 4"
  t_assert_not_contains "$_ndb_out12" "TEARDOWN UNVERIFIED" \
    "a precondition failure never prints the teardown-unverified diagnostic (no group was ever launched)"

  _ndb_unsquat "$_ndb_p12" "$_ndb_pid12" "precondition-reclass squatter"
fi
rm -rf "$_ndb_repo12"
