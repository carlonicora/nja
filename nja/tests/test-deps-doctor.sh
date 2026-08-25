DOCTOR="$NJA_SCRIPTS_DIR/nja-deps-doctor.sh"

# _ddoc_bounded_exit <expected-exit> <label> <max-ticks-of-0.1s> -- <cmd...>
# Regression guard for the `shift 2` hang bug (see nja-deps-sweep.sh and its
# test suite): a value-taking option with no value left `$1` unshifted and
# spun the parser's while-loop forever. Runs the command in the background
# and polls briefly instead of blocking on it directly, so a reintroduced
# hang fails the assertion instead of hanging the whole suite. Kills only
# the exact PID this function started — never a name/pattern kill.
_ddoc_bounded_exit() {
  local expected="$1" label="$2" ticks="$3"; shift 4   # drop expected, label, ticks, the literal --
  local out; out="$(mktemp -t nja-ddoc-out)"
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

t_assert_exit 0 "doctor --help exits 0" -- bash "$DOCTOR" --help

# regression: a trailing value-taking option with nothing after it must not hang
_ddoc_bounded_exit 1 "--root with no value exits 1, not a hang" 30 -- bash "$DOCTOR" --root

# regression: a flag where a value belongs must not be silently swallowed
t_assert_exit 1 "--root --help rejects the flag as its value" -- bash "$DOCTOR" --root --help

outside="$(mktemp -d -t nja-outside)"
t_assert_contains "$(bash "$DOCTOR" --root "$outside" 2>&1)" "not an nja project" \
  "doctor is inert outside nja repos"
rm -rf "$outside"

# healthy fixture: one resolution per peer, links agree
repo="$(t_mkrepo)"
mkdir -p "$repo/node_modules/.pnpm/react@19.2.8/node_modules/react"
mkdir -p "$repo/node_modules/.pnpm/@nestjs+common@11.1.28/node_modules/@nestjs/common"
mkdir -p "$repo/apps/web/node_modules" "$repo/packages/nestjs-neo4jsonapi/node_modules"
ln -s "$repo/node_modules/.pnpm/react@19.2.8/node_modules/react" "$repo/apps/web/node_modules/react"
t_assert_exit 0 "doctor passes on a healthy tree" -- bash "$DOCTOR" --root "$repo"

# duplicate react
mkdir -p "$repo/node_modules/.pnpm/react@19.4.0/node_modules/react"
out="$(bash "$DOCTOR" --root "$repo" 2>&1)"
t_assert_contains "$out" "react" "doctor names the duplicated package"
t_assert_contains "$out" "19.2.8" "doctor lists the first version"
t_assert_contains "$out" "19.4.0" "doctor lists the second version"
t_assert_exit 2 "doctor exits 2 on a duplicate resolution" -- bash "$DOCTOR" --root "$repo"
rm -rf "$repo/node_modules/.pnpm/react@19.4.0"

# readlink mismatch: the library points at a different react than the app
mkdir -p "$repo/node_modules/.pnpm/react@19.9.9/node_modules/react"
mkdir -p "$repo/packages/nextjs-jsonapi/node_modules"
printf '{ "name": "@carlonicora/nextjs-jsonapi", "version": "3.3.9" }\n' \
  > "$repo/packages/nextjs-jsonapi/package.json"
ln -s "$repo/node_modules/.pnpm/react@19.9.9/node_modules/react" \
  "$repo/packages/nextjs-jsonapi/node_modules/react"
t_assert_exit 2 "doctor exits 2 on a readlink mismatch" -- bash "$DOCTOR" --root "$repo"
t_assert_contains "$(bash "$DOCTOR" --root "$repo" 2>&1)" "apps/web" \
  "the mismatch report names the disagreeing workspaces"

rm -rf "$repo"

# regression: relative symlinks at different nesting depths, both resolving
# to the SAME real target, must not be reported as a mismatch. pnpm's own
# symlinks are relative to the link's own directory (root: "node_modules/pkg
# -> .pnpm/pkg@v/node_modules/pkg"; a nested workspace: "apps/api/
# node_modules/pkg -> ../../../node_modules/.pnpm/pkg@v/node_modules/pkg") —
# raw readlink TEXT differs by depth even when both point at the identical
# real directory. Found by running the doctor against a real pnpm-installed
# tree (dreamer), where it produced a false positive on zod before this test
# was added.
repo3="$(t_mkrepo)"
mkdir -p "$repo3/node_modules/.pnpm/zod@4.4.3/node_modules/zod"
mkdir -p "$repo3/node_modules" "$repo3/apps/api/node_modules"
ln -s ".pnpm/zod@4.4.3/node_modules/zod" "$repo3/node_modules/zod"
ln -s "../../../node_modules/.pnpm/zod@4.4.3/node_modules/zod" "$repo3/apps/api/node_modules/zod"
t_assert_exit 0 "relative symlinks at different depths to the same target are not a mismatch" \
  -- bash "$DOCTOR" --root "$repo3"
rm -rf "$repo3"
