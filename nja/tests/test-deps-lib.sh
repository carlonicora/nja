# shellcheck source=../scripts/nja-deps-lib.sh
. "$NJA_SCRIPTS_DIR/nja-deps-lib.sh"

repo="$(t_mkrepo)"

t_assert_eq "$repo" "$(nja_resolve_root "$repo")" "nja_resolve_root returns the git toplevel"
t_assert_contains "$(nja_ok hello)" "hello" "nja_ok prints its argument"
t_assert_contains "$(nja_warn careful)" "careful" "nja_warn prints its argument"

rm -rf "$repo"

repo="$(t_mkrepo)"
ws="$(nja_workspaces "$repo")"

t_assert_contains "$ws" "." "nja_workspaces includes the root"
t_assert_contains "$ws" "apps/api" "nja_workspaces finds apps/api"
t_assert_contains "$ws" "apps/web" "nja_workspaces finds apps/web"
t_assert_contains "$ws" "packages/shared" "nja_workspaces finds packages/shared"
t_assert_contains "$ws" "packages/nestjs-neo4jsonapi" "nja_workspaces finds the submodule package"
t_assert_eq "5" "$(printf '%s\n' "$ws" | grep -c .)" "nja_workspaces finds exactly 5 entries"

# a directory without a package.json is not a workspace
mkdir -p "$repo/apps/scratch"
t_assert_not_contains "$(nja_workspaces "$repo")" "apps/scratch" "dirs without package.json are skipped"

rm -f "$repo/pnpm-workspace.yaml"
t_assert_exit 1 "nja_workspaces fails without pnpm-workspace.yaml" -- nja_workspaces "$repo"

rm -rf "$repo"
