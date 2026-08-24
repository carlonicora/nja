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

# regression: nja_workspaces must return 0 even when packages list ends with a non-existent entry
echo '  - this-dir-does-not-exist' >> "$repo/pnpm-workspace.yaml"
t_assert_exit 0 "nja_workspaces returns 0 with unresolved final package entry" -- nja_workspaces "$repo"
ws_incomplete="$(nja_workspaces "$repo")"
t_assert_eq "5" "$(printf '%s\n' "$ws_incomplete" | grep -c .)" "nja_workspaces still finds 5 entries despite trailing non-existent entry"
t_assert_not_contains "$ws_incomplete" "this-dir-does-not-exist" "non-existent entry is not included"

rm -f "$repo/pnpm-workspace.yaml"
t_assert_exit 1 "nja_workspaces fails without pnpm-workspace.yaml" -- nja_workspaces "$repo"

rm -rf "$repo"

repo="$(t_mkrepo)"
cat_entries="$(nja_yaml_entries "$repo/pnpm-workspace.yaml" catalog)"

t_assert_contains "$cat_entries" "$(printf 'eslint\t^9.39.5')" "catalog: plain key"
t_assert_contains "$cat_entries" "$(printf '@typescript-eslint/parser\t^8.65.0')" "catalog: quoted key unquoted"
t_assert_contains "$cat_entries" "$(printf 'react\t19.2.8')" "catalog: pinned value"
t_assert_contains "$cat_entries" "$(printf '@nestjs/common\t^11.1.28')" "catalog: entry after a comment line"
t_assert_eq "4" "$(printf '%s\n' "$cat_entries" | grep -c .)" "catalog: comments and blanks excluded"
t_assert_not_contains "$cat_entries" "verifyDepsBeforeRun" "catalog: block ends at the next top-level key"

ovr="$(nja_yaml_entries "$repo/pnpm-workspace.yaml" overrides)"
t_assert_contains "$ovr" "$(printf 'class-validator\t^0.15.1')" "overrides: caret range"
t_assert_contains "$ovr" "$(printf 'bullmq\t6.0.2')" "overrides: exact pin"
t_assert_contains "$ovr" "$(printf 'react\tcatalog:')" "overrides: catalog reference retained verbatim"

rm -rf "$repo"

repo="$(t_mkrepo)"
yaml="$repo/pnpm-workspace.yaml"
before="$(cat "$yaml")"

nja_yaml_set_version "$yaml" catalog eslint "^9.40.0"
after="$(cat "$yaml")"

t_assert_contains "$after" "eslint: ^9.40.0" "writer updates the plain catalog entry"
t_assert_contains "$after" "# nestjs peer floors" "writer preserves in-block comments"
t_assert_contains "$after" "# Single source of truth for shared versions." "writer preserves pre-block comments"
t_assert_contains "$after" "verifyDepsBeforeRun: warn" "writer preserves later top-level keys"

# exactly one line changed
changed="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -c '^[<>]')"
t_assert_eq "2" "$changed" "writer changes exactly one line (one < and one >)"

# quoted keys and quoted values keep their quoting
nja_yaml_set_version "$yaml" catalog "@typescript-eslint/parser" "^8.70.0"
t_assert_contains "$(cat "$yaml")" "'@typescript-eslint/parser': ^8.70.0" "writer preserves key quoting"

nja_yaml_set_version "$yaml" overrides bullmq "6.1.0"
t_assert_contains "$(cat "$yaml")" "bullmq: 6.1.0" "writer scopes to the named block"
t_assert_contains "$(cat "$yaml")" "react: 'catalog:'" "writer leaves catalog references alone"

# same key in two blocks: only the named block is touched
nja_yaml_set_version "$yaml" catalog react "19.3.0"
t_assert_contains "$(cat "$yaml")" "react: 19.3.0" "writer updates react in catalog"
t_assert_contains "$(cat "$yaml")" "react: 'catalog:'" "writer does not touch react in overrides"

t_assert_exit 1 "writer fails on an unknown key" -- nja_yaml_set_version "$yaml" catalog nope 1.0.0

rm -rf "$repo"

# ── fix round 1: regressions found by adversarial review ────────────────────

# 1a. a "#" glued to a value (no preceding whitespace) is part of the value,
#     not a comment — it must not be split off and re-appended after the
#     new version.
repo="$(t_mkrepo)"
yaml="$repo/pnpm-workspace.yaml"
cat >> "$yaml" <<'YAML'

hashvals:
  sharp: github:lovell/sharp#v0.35.3
YAML
nja_yaml_set_version "$yaml" hashvals sharp "0.36.0"
line="$(grep '^  sharp:' "$yaml")"
t_assert_eq "  sharp: 0.36.0" "$line" "writer replaces a value containing an unspaced # (glued # is part of the value)"
rm -rf "$repo"

# 1b. fix round 2 regression: a multi-space alignment gap before a trailing
#     comment must be preserved byte-for-byte. The finding-1 fix's first
#     attempt used a single [[:space:]] before "#", which peeled off only
#     the one space adjacent to "#" and discarded the rest of the gap along
#     with the old value — collapsing "6.0.2   # note" to "6.1.0 # note".
#     Assert the exact resulting line, not just that a comment exists.
repo="$(t_mkrepo)"
yaml="$repo/pnpm-workspace.yaml"
cat >> "$yaml" <<'YAML'

gapvals:
  gapkey: 6.0.2   # pinned, see incident
YAML
nja_yaml_set_version "$yaml" gapvals gapkey "6.1.0"
line="$(grep '^  gapkey:' "$yaml")"
t_assert_eq "  gapkey: 6.1.0   # pinned, see incident" "$line" "writer preserves a multi-space gap before a trailing comment exactly"
rm -rf "$repo"

# 1c. a single-space gap before a trailing comment (the common case) must
#     also be preserved exactly.
repo="$(t_mkrepo)"
yaml="$repo/pnpm-workspace.yaml"
cat >> "$yaml" <<'YAML'

gapvals:
  gapkey: 6.0.2 # pinned, see incident
YAML
nja_yaml_set_version "$yaml" gapvals gapkey "6.1.0"
line="$(grep '^  gapkey:' "$yaml")"
t_assert_eq "  gapkey: 6.1.0 # pinned, see incident" "$line" "writer preserves a single-space gap before a trailing comment exactly"
rm -rf "$repo"

# 2. a quoted key containing a colon must not be mistaken for the key/value
#    separator — a later plain key with the same bare name must still be
#    found, and the colon-bearing key must be left untouched.
repo="$(t_mkrepo)"
yaml2="$repo/colon-key.yaml"
cat > "$yaml2" <<'YAML'
catalog:
  'react:native': 0.1.0
  react: 19.2.8
YAML
nja_yaml_set_version "$yaml2" catalog react "19.9.9"
after="$(cat "$yaml2")"
t_assert_contains "$after" "react: 19.9.9" "writer updates the plain key past a colon-bearing quoted key"
t_assert_contains "$after" "'react:native': 0.1.0" "writer leaves the colon-bearing quoted key untouched"
rm -rf "$repo"

# 3. a key that only appears as a nested-map header (no inline scalar value)
#    must not be treated as a match — the header and its indented children
#    must survive untouched, and the call must report "not found" (1), the
#    same contract nja_yaml_entries already enforces on read.
repo="$(t_mkrepo)"
yaml3="$repo/nested.yaml"
cat > "$yaml3" <<'YAML'
catalog:
  react:
    version: 19.2.8
YAML
before="$(cat "$yaml3")"
t_assert_exit 1 "writer does not match a nested-map header with no scalar value" -- nja_yaml_set_version "$yaml3" catalog react "19.9.9"
t_assert_eq "$before" "$(cat "$yaml3")" "writer leaves the nested map (header and child) byte-identical"
rm -rf "$repo"

# 4. exit codes must distinguish "key not found in block" (1, benign) from a
#    hard failure (2) — a missing file or an unwritable directory must not
#    be silently reported as "not found".
repo="$(t_mkrepo)"
yaml="$repo/pnpm-workspace.yaml"
before="$(cat "$yaml")"
t_assert_exit 1 "unknown key still returns 1 (soft, not a hard failure)" -- nja_yaml_set_version "$yaml" catalog nope 1.0.0
t_assert_eq "$before" "$(cat "$yaml")" "the not-found (1) path leaves the file byte-identical"
t_assert_eq "0" "$(find "$repo" -name '*.nja.tmp' | wc -l | tr -d ' ')" "the not-found (1) path leaves no stray temp file"

t_assert_exit 2 "writer returns 2 (hard failure) for a missing file" -- nja_yaml_set_version "$repo/does-not-exist.yaml" catalog eslint "1.0.0"
t_assert_eq "0" "$(find "$repo" -name '*.nja.tmp' | wc -l | tr -d ' ')" "the missing-file (2) path leaves no stray temp file"

chmod 555 "$repo"
t_assert_exit 2 "writer returns 2 (hard failure) for an unwritable directory" -- nja_yaml_set_version "$yaml" catalog eslint "1.0.0"
chmod 755 "$repo"
t_assert_eq "$before" "$(cat "$yaml")" "the unwritable-directory (2) path leaves the file byte-identical"
t_assert_eq "0" "$(find "$repo" -name '*.nja.tmp' | wc -l | tr -d ' ')" "the unwritable-directory (2) path leaves no stray temp file"

rm -rf "$repo"
