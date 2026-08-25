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

# NJA_LATEST_STUB=<file> makes version resolution read "pkg<TAB>version" from a
# file instead of the network, so these tests are hermetic.
repo="$(t_mkrepo)"
stub="$repo/.latest"
cat > "$stub" <<'STUB'
eslint	9.44.0
@typescript-eslint/parser	8.70.0
react	19.4.0
@nestjs/common	11.2.0
class-validator	0.15.4
bullmq	6.2.0
STUB

out="$(NJA_LATEST_STUB="$stub" bash "$SWEEP" --root "$repo" --dry-run 2>&1)"
t_assert_contains "$out" "catalog" "catalog surface appears in the report"
t_assert_contains "$out" "eslint" "catalog reports eslint"
t_assert_contains "$out" "overrides" "overrides surface appears in the report"
t_assert_contains "$out" "bullmq" "overrides reports bullmq"
t_assert_not_contains "$out" "'catalog:'" "overrides skips catalog references"
# Scoped to the dependency files (not full `git status`): the stub itself
# lives inside $repo as an untracked ".latest" fixture file, so a full
# status would always show it regardless of what the sweep did.
t_assert_eq "" "$(git -C "$repo" status --short -- '*package.json' pnpm-workspace.yaml pnpm-lock.yaml)" \
  "catalog dry-run writes nothing"

# reject is honoured on every surface
out="$(NJA_LATEST_STUB="$stub" bash "$SWEEP" --root "$repo" --dry-run --reject eslint,bullmq 2>&1)"
# "eslint" alone would also match the unrejected "@typescript-eslint/parser"
# row, so assert on eslint's own target version (unique among the stub).
t_assert_not_contains "$out" "9.44.0" "reject suppresses a catalog entry"
t_assert_not_contains "$out" "bullmq" "reject suppresses an override entry"

# apply writes, preserving comments
NJA_LATEST_STUB="$stub" bash "$SWEEP" --root "$repo" --apply >/dev/null 2>&1
yaml="$(cat "$repo/pnpm-workspace.yaml")"
t_assert_contains "$yaml" "eslint: ^9.44.0" "apply updates the catalog entry"
t_assert_contains "$yaml" "# nestjs peer floors" "apply preserves comments"
t_assert_contains "$yaml" "react: 'catalog:'" "apply leaves catalog references alone"
rm -rf "$repo"

# floor rule: an override below a declared manifest range is refused
repo2="$(t_mkrepo)"
printf '{ "name": "fixture-api", "version": "1.0.0", "dependencies": { "class-validator": "^0.15.9" } }\n' \
  > "$repo2/apps/api/package.json"
# Must differ from the fixture's current override (^0.15.1) or there is no
# proposed update to check against the floor at all, and must sit below the
# manifest floor declared above (^0.15.9) to actually exercise the refusal.
cat > "$repo2/.latest" <<'STUB'
class-validator	0.15.4
STUB
t_assert_exit 3 "sweep refuses to lower a declared floor" -- \
  env NJA_LATEST_STUB="$repo2/.latest" bash "$SWEEP" --root "$repo2" --apply
t_assert_contains "$(NJA_LATEST_STUB="$repo2/.latest" bash "$SWEEP" --root "$repo2" --apply 2>&1)" \
  "class-validator" "the refusal names the package"
rm -rf "$repo2"
