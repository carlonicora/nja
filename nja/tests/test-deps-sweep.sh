SWEEP="$NJA_SCRIPTS_DIR/nja-deps-sweep.sh"

t_assert_exit 0 "sweep is executable and --help exits 0" -- bash "$SWEEP" --help

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
