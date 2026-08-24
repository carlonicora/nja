SWEEP="$NJA_SCRIPTS_DIR/nja-deps-sweep.sh"

# _dswp_bounded_exit <expected-exit> <label> <max-ticks-of-0.1s> -- <cmd...>
# Regression guard for the `shift 2` hang bug: a value-taking option with no
# value left `$1` unshifted and spun the parser's while-loop forever. Runs
# the command in the background and polls briefly instead of blocking on it
# directly, so a reintroduced hang fails the assertion instead of hanging
# the whole suite. Kills only the exact PID this function started — never a
# name/pattern kill.
_dswp_bounded_exit() {
  local expected="$1" label="$2" ticks="$3"; shift 4   # drop expected, label, ticks, the literal --
  local out; out="$(mktemp -t nja-dswp-out)"
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

t_assert_exit 0 "sweep is executable and --help exits 0" -- bash "$SWEEP" --help

# regression: a trailing value-taking option with nothing after it must not hang
_dswp_bounded_exit 1 "--root with no value exits 1, not a hang" 30 -- bash "$SWEEP" --root
_dswp_bounded_exit 1 "--reject with no value exits 1, not a hang" 30 -- bash "$SWEEP" --reject

# regression: a flag where a value belongs must not be silently swallowed
t_assert_exit 1 "--root --dry-run rejects the flag as its value" -- bash "$SWEEP" --root --dry-run

# non-nja directory: inert
outside="$(mktemp -d -t nja-outside)"
out="$(bash "$SWEEP" --root "$outside" --dry-run 2>&1)"
t_assert_contains "$out" "not an nja project" "sweep is inert outside nja repos"
t_assert_exit 0 "sweep exits 0 outside nja repos" -- bash "$SWEEP" --root "$outside" --dry-run
rm -rf "$outside"

# missing pnpm-workspace.yaml: usage error
bare="$(mktemp -d -t nja-bare)"
printf '{ "name": "x", "dependencies": { "@carlonicora/nextjs-jsonapi": "1.0.0" } }\n' > "$bare/package.json"
t_assert_exit 1 "sweep exits 1 without pnpm-workspace.yaml" -- bash "$SWEEP" --root "$bare" --dry-run
rm -rf "$bare"

# dry-run writes nothing
repo="$(t_mkrepo)"
bash "$SWEEP" --root "$repo" --dry-run >/dev/null 2>&1
t_assert_eq "" "$(git -C "$repo" status --short)" "dry-run leaves the tree clean"
rm -rf "$repo"
