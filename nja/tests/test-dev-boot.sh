#!/usr/bin/env bash
# Tests for nja-dev-boot.sh — Task 9 scope only.
#
# Task 9 delivers process-group launch + verified teardown. The readiness
# poll loop that calls finish() (and therefore the "ports free" message and
# a guaranteed exit-0-on-clean-boot) does not exist until Task 10, so this
# suite does not assert on either — asserting them now would either fail
# forever or require weakening the script to fake a pass. Both are refused.
#
# What this suite DOES assert, and why it is enough for this task:
#   - --help, usage, and the `shift 2` regression guard (option parsing)
#   - the bystander test: the single most important test in this plan. It
#     proves the process-group kill path (a) actually reaps every group
#     member, including one that ignores SIGINT, and (b) never reaches
#     outside that group — the one thing a name/pattern kill cannot promise
#     and the reason this whole approach exists.
#   - the script source contains no pkill / killall / pattern kill, ever.

BOOT="$NJA_SCRIPTS_DIR/nja-dev-boot.sh"
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/fake-dev"

# _ndb_bounded_exit <expected-exit> <label> <max-ticks-of-0.1s> -- <cmd...>
# Regression guard for the `shift 2` hang bug (mirrors _dswp_bounded_exit in
# test-deps-sweep.sh, with its own prefix since suites are sourced into one
# namespace): a value-taking option with no value left $1 unshifted and spun
# the parser's while-loop forever. Runs the command in the background and
# polls briefly instead of blocking on it directly, so a reintroduced hang
# fails the assertion instead of hanging the whole suite. Kills only the
# exact PID this function started — never a name/pattern kill.
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

t_assert_exit 0 "dev-boot --help exits 0" -- bash "$BOOT" --help

outside="$(mktemp -d -t nja-outside)"
t_assert_contains "$(bash "$BOOT" --root "$outside" 2>&1)" "not an nja project" \
  "dev-boot is inert outside nja repos"
rm -rf "$outside"

# regression: a trailing value-taking option with nothing after it must not hang
_ndb_bounded_exit 1 "--root with no value exits 1, not a hang" 30 -- bash "$BOOT" --root

# regression: a flag where a value belongs must not be silently swallowed
t_assert_exit 1 "--root --help rejects the flag as its value" -- bash "$BOOT" --root --help

# --timeout must additionally reject a non-integer value
t_assert_exit 1 "non-integer --timeout exits 1" -- bash "$BOOT" --timeout notanumber

# ── the bystander test ────────────────────────────────────────────────────────
# An unrelated long-lived process, of exactly the kind a name-pattern kill
# would destroy. It MUST survive. NJA_DEV_CMD spawns a fixture whose children
# ignore SIGINT (but not SIGTERM), so this also proves teardown reaches every
# process-group member, not just the leader.
repo="$(t_mkrepo)"
export API_PORT=13950 PORT=13951

bystander_out="$(mktemp -t nja-bystander)"
bash -c 'while :; do sleep 1; done' >"$bystander_out" 2>&1 &
BYSTANDER=$!

boot_out="$(mktemp -t nja-boot-out)"
NJA_DEV_CMD="bash $FIX/stubborn.sh" \
  bash "$BOOT" --root "$repo" --timeout 30 >"$boot_out" 2>&1 &
BOOT_PID=$!

# Bounded: a regression in teardown must fail this assertion, not hang the
# whole suite waiting on a boot script that never exits.
n=0
while kill -0 "$BOOT_PID" 2>/dev/null && [ "$n" -lt 300 ]; do
  sleep 0.1
  n=$((n + 1))
done
if kill -0 "$BOOT_PID" 2>/dev/null; then
  kill -9 "$BOOT_PID" 2>/dev/null
  wait "$BOOT_PID" 2>/dev/null
  t_fail "dev-boot's own process exits after teardown" \
    "boot script pid $BOOT_PID did not exit within 30s — killed it"
else
  wait "$BOOT_PID" 2>/dev/null
  t_pass "dev-boot's own process exits after teardown"
fi

# The process group the script created must be gone.
pgid="$(awk '/^  group:/ { print $2 }' "$boot_out")"
if [ -z "$pgid" ]; then
  t_fail "dev-boot's process group is gone after teardown" \
    "could not find a group pgid in boot output: $(cat "$boot_out" | head -c 300)"
elif [ -n "$(ps -o pid= -g "$pgid" 2>/dev/null)" ]; then
  t_fail "dev-boot's process group is gone after teardown" \
    "pgid $pgid still has members: $(ps -o pid,args -g "$pgid" 2>/dev/null | head -c 300)"
else
  t_pass "dev-boot's process group is gone after teardown"
fi

# The bystander — started before the boot script, sharing nothing with its
# process group — must still be alive. This is the whole point of the group
# handle over a name/pattern kill.
if kill -0 "$BYSTANDER" 2>/dev/null; then
  t_pass "unrelated process survived teardown"
else
  t_fail "unrelated process survived teardown" "the bystander was killed — a pattern kill leaked"
fi
kill "$BYSTANDER" 2>/dev/null
wait "$BYSTANDER" 2>/dev/null
rm -f "$bystander_out" "$boot_out"

# the script must contain no pattern-kill, ever
src="$(cat "$BOOT")"
t_assert_not_contains "$src" "pkill" "dev-boot never calls pkill"
t_assert_not_contains "$src" "killall" "dev-boot never calls killall"

rm -rf "$repo"
