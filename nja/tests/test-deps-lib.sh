# shellcheck source=../scripts/nja-deps-lib.sh
. "$NJA_SCRIPTS_DIR/nja-deps-lib.sh"

repo="$(t_mkrepo)"

t_assert_eq "$repo" "$(nja_resolve_root "$repo")" "nja_resolve_root returns the git toplevel"
t_assert_contains "$(nja_ok hello)" "hello" "nja_ok prints its argument"
t_assert_contains "$(nja_warn careful)" "careful" "nja_warn prints its argument"

rm -rf "$repo"
