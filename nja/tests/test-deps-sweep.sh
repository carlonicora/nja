SWEEP="$NJA_SCRIPTS_DIR/nja-deps-sweep.sh"
# Needed directly (not just transitively via $SWEEP) so this suite can call
# nja_yaml_entries itself when run standalone (`run.sh deps-sweep`), where
# test-deps-lib.sh — which would otherwise have sourced this first — never runs.
# shellcheck source=../scripts/nja-deps-lib.sh
. "$NJA_SCRIPTS_DIR/nja-deps-lib.sh"

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
# I3: hermetic — without a stub this now makes 6 live `pnpm view` calls (one
# per catalog/overrides entry the fixture declares), since Task 6 added the
# catalog/overrides sweeps to what this test exercises without giving it a
# stub. Scoped to dependency files: the stub file itself lives inside $repo
# as an untracked fixture, so a full `git status` would never be empty.
repo="$(t_mkrepo)"
stub0="$repo/.latest"
cat > "$stub0" <<'STUB'
eslint	9.44.0
@typescript-eslint/parser	8.70.0
react	19.4.0
@nestjs/common	11.2.0
class-validator	0.15.4
bullmq	6.2.0
STUB
NJA_LATEST_STUB="$stub0" bash "$SWEEP" --root "$repo" --dry-run >/dev/null 2>&1
t_assert_eq "" "$(git -C "$repo" status --short -- '*package.json' pnpm-workspace.yaml pnpm-lock.yaml)" \
  "dry-run leaves the tree clean"
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
# C2: the ORIGINAL form of this assertion checked for the quoted string
# "'catalog:'", but nja_yaml_entries strips quotes on read and the guarded
# row is never printed at all — so a report row leaking the value would show
# unquoted "catalog:", never the quoted form, making that check vacuous
# (it passed even with the guard deleted). Check the unquoted form instead.
t_assert_not_contains "$out" "catalog:" "overrides skips catalog references"
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

# ── C1: a successful --apply must exit 0 and print the "applied" line ───────
# `[ "$wrc" -ne 0 ] && return "$wrc"` as the last statement of the loop body
# meant that on the SUCCESS path (wrc=0) the `&&` test itself is false, so
# its own exit status (1) becomes the while loop's exit status, so the
# function returns 1 even though every write succeeded — indistinguishable
# from a real failure, and the apply phase aborts before "applied" prints.
repo4="$(t_mkrepo)"
stub4="$repo4/.latest"
cat > "$stub4" <<'STUB'
eslint	9.44.0
class-validator	0.15.4
bullmq	6.2.0
STUB
out="$(NJA_LATEST_STUB="$stub4" bash "$SWEEP" --root "$repo4" --apply 2>&1)"
code=$?
t_assert_eq "0" "$code" "a successful --apply exits 0 (C1 regression)"
t_assert_contains "$out" "applied — now run ONE root install" \
  "a successful --apply prints the applied line (C1 regression)"
rm -rf "$repo4"

# ── C2: a dedicated, precise exercise of the catalog: guard ─────────────────
# Reads the overrides block back with nja_yaml_entries (the same parser the
# script itself uses) rather than substring-matching the pretty-printed
# report, so this cannot pass by accident the way the two assertions above
# (see C2 note near line ~80) did before C1 was fixed.
repo5="$(t_mkrepo)"
stub5="$repo5/.latest"
cat > "$stub5" <<'STUB'
react	19.4.0
STUB
NJA_LATEST_STUB="$stub5" bash "$SWEEP" --root "$repo5" --apply >/dev/null 2>&1
react_override="$(nja_yaml_entries "$repo5/pnpm-workspace.yaml" overrides | awk -F'\t' '$1 == "react" { print $2 }')"
t_assert_eq "catalog:" "$react_override" \
  "guard: react's overrides entry is still catalog: after apply (C2 regression)"
rm -rf "$repo5"

# ── I1: the floor rule must resolve a catalog:-declared floor ───────────────
# The literal dreamer @nestjs incident: every manifest said "catalog:", so
# the concrete floor (^11.1.28) lived only in the catalog: block itself.
# declared_floor must resolve the reference back to that value, not treat
# "catalog:" as "no floor declared" the way it treats workspace:/npm:.
repo6="$(t_mkrepo)"
cat > "$repo6/pnpm-workspace.yaml" <<'YAML'
packages:
  - 'apps/*'
  - 'packages/*'

catalog:
  '@nestjs/common': ^11.1.28

overrides:
  '@nestjs/common': ^11.1.20
YAML
printf '{ "name": "fixture-api", "version": "1.0.0", "dependencies": { "@nestjs/common": "catalog:" } }\n' \
  > "$repo6/apps/api/package.json"
cat > "$repo6/.latest" <<'STUB'
@nestjs/common	11.1.24
STUB
t_assert_exit 3 "floor rule catches a catalog:-declared floor (I1: dreamer @nestjs incident)" -- \
  env NJA_LATEST_STUB="$repo6/.latest" bash "$SWEEP" --root "$repo6" --apply
t_assert_contains "$(NJA_LATEST_STUB="$repo6/.latest" bash "$SWEEP" --root "$repo6" --apply 2>&1)" \
  "@nestjs/common" "the catalog-floor refusal names the package (I1)"
rm -rf "$repo6"

# ── I2: never propose or write a downgrade ───────────────────────────────────
# `pnpm view <pkg> version` (the "latest" dist-tag) can legitimately be BELOW
# a pin that is already ahead of it (a prerelease/next build) — dreamer's
# catalog holds exactly such pins. Neither surface may resolve that as an
# update.
repo7="$(t_mkrepo)"
stub7="$repo7/.latest"
cat > "$stub7" <<'STUB'
react	19.1.0
bullmq	5.9.0
STUB
# stdout only: the skip warning itself (stderr) legitimately names the lower
# version as diagnostic text ("say so in the report" is satisfied by that
# warning, not by a table row) — this checks the tabular report specifically,
# i.e. that no row PROPOSES the downgrade.
out="$(NJA_LATEST_STUB="$stub7" bash "$SWEEP" --root "$repo7" --dry-run 2>/dev/null)"
t_assert_not_contains "$out" "19.1.0" "catalog surface never proposes a downgrade (I2)"
t_assert_not_contains "$out" "5.9.0" "overrides surface never proposes a downgrade (I2)"
NJA_LATEST_STUB="$stub7" bash "$SWEEP" --root "$repo7" --apply >/dev/null 2>&1
yaml7="$(cat "$repo7/pnpm-workspace.yaml")"
t_assert_contains "$yaml7" "react: 19.2.8" "catalog pin survives apply when latest is lower (I2)"
t_assert_contains "$yaml7" "bullmq: 6.0.2" "overrides pin survives apply when latest is lower (I2)"
rm -rf "$repo7"

# ── I4: --reject must glob-match on every surface ────────────────────────────
# Surface 1 passes the list straight to `ncu -x`, which glob-matches. The old
# is_rejected did plain string equality, so `--reject '@nestjs/*'` held those
# packages back on the manifest surface but NOT on the catalog surface —
# where @nestjs actually lives in these repos.
repo8="$(t_mkrepo)"
stub8="$repo8/.latest"
cat > "$stub8" <<'STUB'
@nestjs/common	11.2.0
STUB
out="$(NJA_LATEST_STUB="$stub8" bash "$SWEEP" --root "$repo8" --dry-run --reject '@nestjs/*' 2>&1)"
t_assert_not_contains "$out" "@nestjs/common" "glob --reject suppresses a catalog entry via wildcard (I4)"
rm -rf "$repo8"

# ── I5a: report rows must come from a DRY pass, even under --apply ──────────
# ncu -u and the yaml writer run within the SAME --apply invocation that
# assembles the report; reading the FROM value after either has already run
# would show the just-written value instead of the true prior one (the
# reproduction used to confirm this: replacing the report-assembly calls'
# literal `0` with `"$APPLY"` collapses FROM and TO to the same value).
repo9="$(t_mkrepo)"
stub9="$repo9/.latest"
cat > "$stub9" <<'STUB'
eslint	9.44.0
STUB
out="$(NJA_LATEST_STUB="$stub9" bash "$SWEEP" --root "$repo9" --apply 2>&1)"
t_assert_contains "$out" "9.39.5" \
  "apply's report shows the pre-write FROM value, not the just-written one (I5a: dry-pass-first, catalog)"
rm -rf "$repo9"

# I5a, manifest surface (the site the regression actually reproduces at):
# `ncu -u` writes apps/api/package.json in place as a side effect of running,
# and sweep_manifests' own node script then reads THAT SAME (now-mutated)
# file to compute the FROM column — so breaking dry-pass-first here doesn't
# just show a stale value, it makes FROM and TO literally identical (this
# exact case, with "lodash", is how the regression was found). Needs a live
# `ncu` registry lookup (no NJA_LATEST_STUB for the manifest surface, and
# adding one is out of scope for this fix round) — accepted per this
# project's existing precedent of leaving surface 1 non-hermetic (I3 above
# explicitly defers the broader ncu-hermeticity problem).
repo11="$(t_mkrepo)"
printf '{ "name": "fixture-api", "version": "1.0.0", "dependencies": { "lodash": "^4.0.0" } }\n' \
  > "$repo11/apps/api/package.json"
out="$(bash "$SWEEP" --root "$repo11" --apply 2>&1)"
t_assert_contains "$out" "^4.0.0" \
  "apply's report shows the pre-write FROM value, not the just-written one (I5a: dry-pass-first, manifest)"
rm -rf "$repo11"

# ── I5b: nja_yaml_set_version's rc=2 is fatal, exit 1, and names package+file ─
# Now that C1 is fixed, success and a hard write failure must no longer
# share an exit code. Forces rc=2 by making the target directory unwritable
# (mv "$tmp" "$file" fails), so nja_yaml_set_version's setter itself never
# gets a chance to write — this exercises write_yaml_version's own fatal path
# end to end, not just the setter in isolation.
repo10="$(t_mkrepo)"
stub10="$repo10/.latest"
cat > "$stub10" <<'STUB'
eslint	9.44.0
STUB
chmod 555 "$repo10"
out="$(NJA_LATEST_STUB="$stub10" bash "$SWEEP" --root "$repo10" --apply 2>&1)"
code=$?
chmod 755 "$repo10"
t_assert_eq "1" "$code" "a hard write failure (rc=2) exits 1 (I5b)"
t_assert_contains "$out" "eslint" "the rc=2 failure names the package (I5b)"
t_assert_contains "$out" "pnpm-workspace.yaml" "the rc=2 failure names the file (I5b)"
t_assert_not_contains "$out" "applied — now run ONE root install" \
  "the applied line never prints after a hard write failure (I5b)"
rm -rf "$repo10"
