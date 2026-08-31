fleet="$(t_mkfleet 3)"

t_assert_eq "3" "$(find "$fleet" -mindepth 1 -maxdepth 1 -type d -not -name origin | grep -c .)" "t_mkfleet creates 3 members"

m1="$fleet/member-1"
t_assert_exit 0 "member is a git repo" -- git -C "$m1" rev-parse --show-toplevel
t_assert_exit 0 "member has an origin remote" -- git -C "$m1" remote get-url origin
t_assert_exit 0 "backend submodule is a git repo" -- git -C "$m1/packages/nestjs-neo4jsonapi" rev-parse HEAD
t_assert_exit 0 "frontend submodule is a git repo" -- git -C "$m1/packages/nextjs-jsonapi" rev-parse HEAD

be1="$(git -C "$m1/packages/nestjs-neo4jsonapi" rev-parse HEAD)"
be2="$(git -C "$fleet/member-2/packages/nestjs-neo4jsonapi" rev-parse HEAD)"
t_assert_eq "$be1" "$be2" "all members pin the same backend SHA"

t_assert_eq "master" "$(git -C "$m1/packages/nestjs-neo4jsonapi" rev-parse --abbrev-ref HEAD)" "submodules are on master, not detached"
t_assert_eq "0" "$(git -C "$m1" status --porcelain | grep -c . || true)" "a fresh member is clean"

rm -rf "$fleet"

# shellcheck source=../scripts/nja-fleet-lib.sh
. "$NJA_SCRIPTS_DIR/nja-fleet-lib.sh"

# ── state dir ───────────────────────────────────────────────────────────────
NJA_FLEET_HOME=/tmp/nja-fleet-test
t_assert_eq "/tmp/nja-fleet-test/2026-08-28" "$(nja_fleet_state_dir 2026-08-28)" "state dir joins home and date"

# ── origin identity ─────────────────────────────────────────────────────────
fleet="$(t_mkfleet 3)"
t_assert_eq "https://example.test/member-1" "$(nja_fleet_origin "$fleet/member-1")" "origin strips the .git suffix"

bare="$(cd "$(mktemp -d -t nja-noremote)" && pwd -P)"; git -C "$bare" init -q
t_assert_exit 1 "origin fails when there is no remote" -- nja_fleet_origin "$bare"
rm -rf "$bare"

# ── modal SHA ───────────────────────────────────────────────────────────────
t_assert_eq "aaa" "$(nja_fleet_modal_sha aaa aaa aaa)" "unanimous is modal"
t_assert_eq "aaa" "$(nja_fleet_modal_sha aaa aaa bbb)" "2 of 3 is a strict majority"
t_assert_exit 3 "3-way split has no modal SHA" -- nja_fleet_modal_sha aaa bbb ccc
t_assert_exit 3 "2/2 tie has no modal SHA" -- nja_fleet_modal_sha aaa aaa bbb bbb
t_assert_eq "" "$(nja_fleet_modal_sha aaa bbb ccc 2>/dev/null)" "no modal SHA prints nothing"
t_assert_exit 3 "no arguments has no modal SHA" -- nja_fleet_modal_sha

# ── facts ───────────────────────────────────────────────────────────────────
facts="$(nja_fleet_facts "$fleet/member-1")"
t_assert_eq "11" "$(printf '%s' "$facts" | awk -F'\t' '{print NF}')" "facts line has 11 fields"
t_assert_eq "member-1" "$(printf '%s' "$facts" | cut -f1)" "field 1 is the member name"
t_assert_eq "0" "$(printf '%s' "$facts" | cut -f4)" "field 4 is the root dirty count"
t_assert_eq "master" "$(printf '%s' "$facts" | cut -f7)" "field 7 is the backend branch"

# ── eligibility ─────────────────────────────────────────────────────────────
mbe="$(git -C "$fleet/member-1/packages/nestjs-neo4jsonapi" rev-parse HEAD)"
mfe="$(git -C "$fleet/member-1/packages/nextjs-jsonapi" rev-parse HEAD)"
t_assert_exit 0 "a clean member at the modal SHAs is eligible" -- nja_fleet_eligibility "$facts" "$mbe" "$mfe"

printf 'dirt\n' > "$fleet/member-1/scratch.txt"
dirty_facts="$(nja_fleet_facts "$fleet/member-1")"
t_assert_exit 1 "a dirty root is ineligible" -- nja_fleet_eligibility "$dirty_facts" "$mbe" "$mfe"
t_assert_contains "$(nja_fleet_eligibility "$dirty_facts" "$mbe" "$mfe")" "root tree dirty" "the reason names the dirty root"
rm -f "$fleet/member-1/scratch.txt"

git -C "$fleet/member-2/packages/nestjs-neo4jsonapi" checkout -q --detach HEAD
det_facts="$(nja_fleet_facts "$fleet/member-2")"
t_assert_exit 1 "a detached submodule is ineligible" -- nja_fleet_eligibility "$det_facts" "$mbe" "$mfe"
t_assert_contains "$(nja_fleet_eligibility "$det_facts" "$mbe" "$mfe")" "not on master" "the reason names the detached submodule"

t_assert_contains "$(nja_fleet_eligibility "$facts" "deadbeef" "$mfe")" "not at the fleet SHA" "a member off the modal SHA is ineligible"

rm -rf "$fleet"
