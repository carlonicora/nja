# nja-update-dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `nja-update-dependencies` skill to the nja plugin that sweeps every dependency surface of an nja monorepo, verifies the result with lint/build/dev-boot/test, and leaves the working tree uncommitted.

**Architecture:** Three deterministic bash scripts under `nja/scripts/` (sweep, doctor, dev-boot) sharing one sourced library, plus a `SKILL.md` that orchestrates them through a seven-phase procedure with explicit user gates. The scripts own everything mechanical — YAML parsing, duplicate-resolution detection, process-group teardown — so the model handles only judgment calls. This mirrors the plugin's existing split between `scripts/nja-lint.sh` and `skills/nja-architecture/`.

**Tech Stack:** bash (macOS-compatible), `awk`, `git`, `pnpm`, `node`, `ncu` (npm-check-updates 17.x), `lsof`. Markdown for the skill and references. No `jq`, no npm dependencies, no build step.

**Spec:** `docs/superpowers/specs/2026-08-24-nja-update-dependencies-design.md`

## Global Constraints

- **Repo:** `/Users/carlo/Development/nja` (the plugin repo, not an app). Current branch is `main`. **Create a feature branch before Task 1** — do not commit to `main`.
- **Commits:** the plan includes a commit step per task, but this repo's owner commits by choice. **Ask once, before the first commit, whether to commit per task or leave everything uncommitted.** Honour the answer for every later task.
- **Shebang and flags:** every script starts `#!/usr/bin/env bash` then `set -uo pipefail` — matching `nja/scripts/nja-lint.sh`. Not `set -e`: these scripts inspect non-zero exits deliberately.
- **macOS first.** No `setsid` (absent on Darwin). No GNU-only flags. **No in-place `sed -i`** — BSD `sed` requires `sed -i ''` and GNU rejects it; write with `awk` to a temp file and `mv`.
- **Allowed external commands:** `bash`, `git`, `pnpm`, `node`, `ncu`, `lsof`, `ps`, `awk`, `sed`, `grep`, `mktemp`. **No `jq`** — use `node -e` for JSON.
- **nja gating:** every executable script sources `nja/scripts/nja-detect.sh` and exits `0` with a notice when `nja_is_project` returns false.
- **Process safety (non-negotiable):** never `pkill`, `killall`, or any kill by name/pattern. Only a captured PGID, or a port verified free before launch. This rule comes from `~/.claude/CLAUDE.md`; violating it has already destroyed unrelated work once.
- **Exit codes, exactly as specified:**
  - `nja-deps-sweep.sh` — `0` ok, `1` usage/environment, `3` refused to lower a declared floor
  - `nja-deps-doctor.sh` — `0` pass (WARNs allowed), `1` delegated script failed / environment, `2` duplicate resolution or readlink mismatch
  - `nja-dev-boot.sh` — `0` booted and tore down, `1` precondition failure, `2` boot failed, `4` teardown unverified (something may still be running)
- **Plugin version target:** `1.12.0`, written in `nja/.claude-plugin/plugin.json` and in **both** blocks of `.claude-plugin/marketplace.json`.
- **Test command for every task:** `bash nja/tests/run.sh` from the repo root.

---

## File Structure

**New — shared library**

- `nja/scripts/nja-deps-lib.sh` — sourced, never executed. Output helpers, root resolution, `pnpm-workspace.yaml` parsing (workspaces, catalog, overrides), and the comment-preserving version writer. *This file is a plan-level refinement of spec §4, which listed three scripts: `nja-deps-sweep.sh` and `nja-deps-doctor.sh` both need workspace discovery, and duplicating a YAML parser across two scripts would be worse than adding a fourth file.*

**New — executables**

- `nja/scripts/nja-deps-sweep.sh` — the three-surface sweep (spec §5)
- `nja/scripts/nja-deps-doctor.sh` — mechanical post-install checks (spec §6)
- `nja/scripts/nja-dev-boot.sh` — process-group boot check (spec §7). Sources `nja-detect.sh` only; it needs no YAML parsing.

**New — tests** (no test infrastructure exists in this repo yet; the plugin is pure bash + markdown)

- `nja/tests/run.sh` — runner; sources every `test-*.sh`, reports, exits non-zero on failure
- `nja/tests/lib.sh` — assertions and the fixture-repo builder
- `nja/tests/test-deps-lib.sh`, `test-deps-sweep.sh`, `test-deps-doctor.sh`, `test-dev-boot.sh`
- `nja/tests/fixtures/fake-dev/` — `dev-ok.sh`, `dev-hang.sh`, `dev-fatal.sh`, `stubborn.sh`

**New — skill**

- `nja/skills/nja-update-dependencies/SKILL.md`
- `nja/skills/nja-update-dependencies/references/hazards.md`
- `nja/skills/nja-update-dependencies/evals/README.md`, `01-dirty-tree.md`, `02-held-major.md`, `03-doctor-duplicate.md`, `04-boot-failure.md`

**Modified**

- `nja/.claude-plugin/plugin.json` — version
- `.claude-plugin/marketplace.json` — version, both blocks
- `README.md` — one row in the Skills table

---

### Task 1: Test harness and library skeleton

**Files:**
- Create: `nja/tests/run.sh`
- Create: `nja/tests/lib.sh`
- Create: `nja/scripts/nja-deps-lib.sh`
- Test: `nja/tests/test-deps-lib.sh`

**Interfaces:**
- Consumes: `nja/scripts/nja-detect.sh` (exists) — defines `nja_is_project <dir>`
- Produces:
  - `t_assert_eq <expected> <actual> <label>`, `t_assert_contains <haystack> <needle> <label>`, `t_assert_not_contains <haystack> <needle> <label>`, `t_assert_exit <expected-code> <label> -- <cmd...>`
  - `t_mkrepo` → prints the path of a fresh fixture repo (git-initialised, nja-detectable)
  - `nja_say`, `nja_ok`, `nja_warn`, `nja_fail`, `nja_resolve_root [path]`

- [ ] **Step 1: Create the feature branch**

```bash
cd /Users/carlo/Development/nja
git checkout -b feat/nja-update-dependencies
```

- [ ] **Step 2: Write the test harness**

Create `nja/tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Minimal assertion harness for the nja plugin's shell scripts.
# Sourced by nja/tests/run.sh; never executed directly.

T_RUN=0
T_FAILED=0
T_CURRENT="(none)"

t_case() { T_CURRENT="$1"; }

t_pass() { T_RUN=$((T_RUN + 1)); printf '  ✓ %s\n' "$1"; }
t_fail() {
  T_RUN=$((T_RUN + 1)); T_FAILED=$((T_FAILED + 1))
  printf '  ✖ %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '      %s\n' "$2" >&2
  return 0
}

t_assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then t_pass "$label"
  else t_fail "$label" "expected [$expected] got [$actual]"; fi
}

t_assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) t_pass "$label" ;;
    *) t_fail "$label" "missing [$needle] in: $(printf '%s' "$haystack" | head -c 400)" ;;
  esac
}

t_assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in
    *"$needle"*) t_fail "$label" "unexpected [$needle] present" ;;
    *) t_pass "$label" ;;
  esac
}

# t_assert_exit <expected> <label> -- <command...>
t_assert_exit() {
  local expected="$1" label="$2"; shift 3   # drop expected, label, and the literal --
  "$@" >/dev/null 2>&1
  local code=$?
  if [ "$code" -eq "$expected" ]; then t_pass "$label"
  else t_fail "$label" "expected exit $expected got $code"; fi
}

# t_mkrepo — a fresh nja-detectable fixture repo. Prints its path.
t_mkrepo() {
  local d; d="$(mktemp -d -t nja-fixture)"
  mkdir -p "$d/apps/api" "$d/apps/web" "$d/packages/shared" "$d/packages/nestjs-neo4jsonapi"
  cat > "$d/package.json" <<'JSON'
{ "name": "fixture", "version": "1.0.0", "private": true,
  "dependencies": { "@carlonicora/nestjs-neo4jsonapi": "workspace:*" } }
JSON
  printf '{ "name": "fixture-api", "version": "1.0.0" }\n' > "$d/apps/api/package.json"
  printf '{ "name": "fixture-web", "version": "1.0.0" }\n' > "$d/apps/web/package.json"
  printf '{ "name": "@fixture/shared", "version": "1.0.0", "private": true }\n' > "$d/packages/shared/package.json"
  printf '{ "name": "@carlonicora/nestjs-neo4jsonapi", "version": "3.2.2" }\n' > "$d/packages/nestjs-neo4jsonapi/package.json"
  cat > "$d/pnpm-workspace.yaml" <<'YAML'
packages:
  - 'apps/*'
  - 'packages/*'

# Single source of truth for shared versions.
catalog:
  eslint: ^9.39.5
  '@typescript-eslint/parser': ^8.65.0
  react: 19.2.8
  # nestjs peer floors
  '@nestjs/common': ^11.1.28

verifyDepsBeforeRun: warn

overrides:
  react: 'catalog:'
  class-validator: ^0.15.1
  bullmq: 6.0.2
YAML
  git -C "$d" init -q
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
  printf '%s\n' "$d"
}
```

Create `nja/tests/run.sh`:

```bash
#!/usr/bin/env bash
# Test runner for the nja plugin's shell scripts.
#   bash nja/tests/run.sh            # all suites
#   bash nja/tests/run.sh deps-lib   # one suite (matches test-<name>.sh)
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NJA_SCRIPTS_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"

# shellcheck source=./lib.sh
. "$TESTS_DIR/lib.sh"

filter="${1:-}"
for suite in "$TESTS_DIR"/test-*.sh; do
  [ -f "$suite" ] || continue
  name="$(basename "$suite" .sh)"; name="${name#test-}"
  [ -n "$filter" ] && [ "$filter" != "$name" ] && continue
  printf '\n%s\n' "── $name ──────────────────────────────────────────"
  # shellcheck disable=SC1090
  . "$suite"
done

printf '\n%s\n' "──────────────────────────────────────────────────"
if [ "$T_FAILED" -gt 0 ]; then
  printf '%d/%d failed\n' "$T_FAILED" "$T_RUN" >&2
  exit 1
fi
printf 'all %d passed\n' "$T_RUN"
```

- [ ] **Step 3: Write the failing test for the library skeleton**

Create `nja/tests/test-deps-lib.sh`:

```bash
# shellcheck source=../scripts/nja-deps-lib.sh
. "$NJA_SCRIPTS_DIR/nja-deps-lib.sh"

repo="$(t_mkrepo)"

t_assert_eq "$repo" "$(nja_resolve_root "$repo")" "nja_resolve_root returns the git toplevel"
t_assert_contains "$(nja_ok hello)" "hello" "nja_ok prints its argument"
t_assert_contains "$(nja_warn careful)" "careful" "nja_warn prints its argument"

rm -rf "$repo"
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-lib`
Expected: FAIL — `nja-deps-lib.sh: No such file or directory`

- [ ] **Step 5: Write the minimal library**

Create `nja/scripts/nja-deps-lib.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for the nja dependency scripts (sweep, doctor).
# SOURCED, never executed.
#
# Everything here is deterministic and side-effect free except
# nja_yaml_set_version, which is the single writer of pnpm-workspace.yaml.

NJA_DEPS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-detect.sh
. "$NJA_DEPS_LIB_DIR/nja-detect.sh"

# ── output ───────────────────────────────────────────────────────────────────
nja_say()  { printf '%s\n' "$*"; }
nja_ok()   { printf '  ✓ %s\n' "$*"; }
nja_warn() { printf '  ⚠ %s\n' "$*"; }
nja_fail() { printf '  ✖ %s\n' "$*" >&2; }

# ── root ─────────────────────────────────────────────────────────────────────
# nja_resolve_root [path] — the repo root, or the given path if not a git repo.
nja_resolve_root() {
  local p="${1:-$PWD}"
  if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$p" rev-parse --show-toplevel
  else
    (cd "$p" && pwd)
  fi
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-lib`
Expected: PASS — 3 assertions

- [ ] **Step 7: Commit** (ask first — see Global Constraints)

```bash
chmod +x nja/tests/run.sh
git add nja/tests/run.sh nja/tests/lib.sh nja/tests/test-deps-lib.sh nja/scripts/nja-deps-lib.sh
git commit -m "test(deps): add shell test harness and nja-deps-lib skeleton"
```

---

### Task 2: Workspace discovery

**Files:**
- Modify: `nja/scripts/nja-deps-lib.sh` (append)
- Test: `nja/tests/test-deps-lib.sh` (append)

**Interfaces:**
- Consumes: `nja_resolve_root` (Task 1)
- Produces: `nja_workspaces <root>` — prints one repo-relative directory per line, `.` first (the root manifest), then every directory matched by the `packages:` globs that contains a `package.json`, in glob-expansion (sorted) order. Returns 1 if `pnpm-workspace.yaml` is absent.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-deps-lib.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-lib`
Expected: FAIL — `nja_workspaces: command not found`

- [ ] **Step 3: Implement workspace discovery**

Append to `nja/scripts/nja-deps-lib.sh`:

```bash
# ── pnpm-workspace.yaml: packages ────────────────────────────────────────────
# nja_workspaces <root>
# One repo-relative directory per line: "." (the root manifest) plus every
# directory matched by the `packages:` globs that holds a package.json.
# Hardcoding the six historical paths is what left a360ai (three apps, no
# scripts/update.sh) unswept — always discover.
nja_workspaces() {
  local root="$1" yaml="$1/pnpm-workspace.yaml"
  [ -f "$yaml" ] || return 1
  printf '.\n'
  local glob base entry
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    case "$glob" in
      */\*)
        base="${glob%/\*}"
        [ -d "$root/$base" ] || continue
        for entry in "$root/$base"/*/; do
          [ -f "${entry}package.json" ] || continue
          entry="${entry%/}"
          printf '%s/%s\n' "$base" "${entry##*/}"
        done
        ;;
      *)
        [ -f "$root/$glob/package.json" ] && printf '%s\n' "$glob"
        ;;
    esac
  done <<EOF
$(nja_yaml_list "$yaml" packages)
EOF
}

# nja_yaml_list <file> <block> — the "- item" entries of a top-level block.
nja_yaml_list() {
  awk -v want="$2" '
    index($0, want ":") == 1 { inb = 1; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    inb && /^[[:space:]]*-/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", line)
      if (line != "") print line
    }
  ' "$1"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-lib`
Expected: PASS — 10 assertions total

- [ ] **Step 5: Verify against all six real repos**

```bash
for d in a360ai dreamer neural-erp only35 phlow wyrdli; do
  printf '%s: ' "$d"
  bash -c '. nja/scripts/nja-deps-lib.sh; nja_workspaces "$HOME/Development/'"$d"'" | tr "\n" " "'
  echo
done
```

Expected: `a360ai` lists `apps/api apps/corpus apps/web` (three apps); the other five list `apps/api apps/web`. All six list `packages/nestjs-neo4jsonapi packages/nextjs-jsonapi packages/shared` and a leading `.`.

- [ ] **Step 6: Commit**

```bash
git add nja/scripts/nja-deps-lib.sh nja/tests/test-deps-lib.sh
git commit -m "feat(deps): discover workspaces from pnpm-workspace.yaml globs"
```

---

### Task 3: Catalog and overrides parsing

**Files:**
- Modify: `nja/scripts/nja-deps-lib.sh` (append)
- Test: `nja/tests/test-deps-lib.sh` (append)

**Interfaces:**
- Consumes: nothing new
- Produces: `nja_yaml_entries <file> <block>` — prints `key<TAB>value` per entry of a top-level `key: value` block, skipping comment and blank lines and stripping surrounding quotes from both key and value.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-deps-lib.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-lib`
Expected: FAIL — `nja_yaml_entries: command not found`

- [ ] **Step 3: Implement the entry parser**

Append to `nja/scripts/nja-deps-lib.sh`:

```bash
# ── pnpm-workspace.yaml: key/value blocks ────────────────────────────────────
# nja_yaml_entries <file> <block>  →  "key<TAB>value" per entry.
# Mirrors the parser in each app's scripts/check-dep-drift.js, which is the
# reference implementation for the quoting these files actually use.
nja_yaml_entries() {
  awk -v want="$2" '
    index($0, want ":") == 1 { inb = 1; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    !inb                     { next }
    /^[[:space:]]*#/         { next }
    /^[[:space:]]*$/         { next }
    /^[[:space:]]*-/         { next }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      idx = index(line, ":")
      if (idx == 0) next
      k = substr(line, 1, idx - 1)
      v = substr(line, idx + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", k)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", v)
      if (k == "" || v == "") next
      printf "%s\t%s\n", k, v
    }
  ' "$1"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-lib`
Expected: PASS — 19 assertions total

- [ ] **Step 5: Verify against dreamer's real file**

```bash
bash -c '. nja/scripts/nja-deps-lib.sh
  n=$(nja_yaml_entries "$HOME/Development/dreamer/pnpm-workspace.yaml" catalog | grep -c .)
  m=$(nja_yaml_entries "$HOME/Development/dreamer/pnpm-workspace.yaml" overrides | grep -c .)
  echo "catalog=$n overrides=$m"'
```

Expected exactly: `catalog=21 overrides=29`. Of the 29 override entries, 13 are
`catalog:` references (skipped by the sweep) and 16 carry concrete ranges. Those
16 plus the 21 catalog entries are the 37 packages `ncu` has never been able to
see in this repo.

- [ ] **Step 6: Commit**

```bash
git add nja/scripts/nja-deps-lib.sh nja/tests/test-deps-lib.sh
git commit -m "feat(deps): parse catalog and overrides blocks from pnpm-workspace.yaml"
```

---

### Task 4: Comment-preserving version writer

**Files:**
- Modify: `nja/scripts/nja-deps-lib.sh` (append)
- Test: `nja/tests/test-deps-lib.sh` (append)

**Interfaces:**
- Consumes: nothing new
- Produces: `nja_yaml_set_version <file> <block> <key> <new-version>` — rewrites only the version token on that key's line inside that block, in place. Preserves indentation, key quoting, value quoting, trailing comments, and every other line byte-for-byte. Returns 1 and writes nothing if the key is not found in that block.

This is the highest-risk function in the plan: `pnpm-workspace.yaml` carries load-bearing commentary (the `verifyDepsBeforeRun`, `autoInstallPeers`, and per-override rationale blocks explain incidents that cost real debugging time). Losing it would be a genuine regression, so the test asserts on the diff shape, not just the value.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-deps-lib.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-lib`
Expected: FAIL — `nja_yaml_set_version: command not found`

- [ ] **Step 3: Implement the writer**

Append to `nja/scripts/nja-deps-lib.sh`:

```bash
# nja_yaml_set_version <file> <block> <key> <new-version>
# The ONLY writer of pnpm-workspace.yaml. Substitutes the version token and
# nothing else — indentation, quoting, trailing comments and every other line
# survive byte-for-byte. These files carry incident commentary that is worth
# more than the versions; a reformatting write would be a regression.
nja_yaml_set_version() {
  local file="$1" block="$2" key="$3" new="$4"
  local tmp="$file.nja.tmp"
  awk -v want="$block" -v key="$key" -v new="$new" '
    BEGIN { inb = 0; done = 0 }
    index($0, want ":") == 1 { inb = 1; print; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    {
      if (inb && !done && $0 !~ /^[[:space:]]*#/) {
        idx = index($0, ":")
        if (idx > 0) {
          k = substr($0, 1, idx - 1)
          bare = k
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", bare)
          gsub(/^['"'"'"]+|['"'"'"]+$/, "", bare)
          if (bare == key) {
            rest = substr($0, idx + 1)
            match(rest, /^[[:space:]]*/); gap = substr(rest, 1, RLENGTH)
            val = substr(rest, RLENGTH + 1)
            trail = ""
            if (match(val, /[[:space:]]*#.*$/)) {
              trail = substr(val, RSTART)
              val = substr(val, 1, RSTART - 1)
            }
            q = ""
            if (substr(val, 1, 1) == "\047" || substr(val, 1, 1) == "\"") q = substr(val, 1, 1)
            printf "%s:%s%s%s%s%s\n", k, gap, q, new, q, trail
            done = 1
            next
          }
        }
      }
      print
    }
    END { exit(done ? 0 : 1) }
  ' "$file" > "$tmp"
  local code=$?
  if [ "$code" -ne 0 ]; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$file"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-lib`
Expected: PASS — 30 assertions total

- [ ] **Step 5: Prove non-destructiveness on dreamer's real file**

```bash
cp ~/Development/dreamer/pnpm-workspace.yaml /tmp/ws-real.yaml
cp /tmp/ws-real.yaml /tmp/ws-edit.yaml
bash -c '. nja/scripts/nja-deps-lib.sh; nja_yaml_set_version /tmp/ws-edit.yaml catalog eslint "^9.99.0"'
diff /tmp/ws-real.yaml /tmp/ws-edit.yaml
```

Expected: exactly two diff lines (`< eslint: ^9.39.5`, `> eslint: ^9.99.0`). Every comment block intact.

- [ ] **Step 6: Commit**

```bash
git add nja/scripts/nja-deps-lib.sh nja/tests/test-deps-lib.sh
git commit -m "feat(deps): add comment-preserving pnpm-workspace.yaml version writer"
```

---

### Task 5: `nja-deps-sweep.sh` — manifest surface

**Files:**
- Create: `nja/scripts/nja-deps-sweep.sh`
- Test: `nja/tests/test-deps-sweep.sh`

**Interfaces:**
- Consumes: `nja_workspaces`, `nja_resolve_root`, `nja_say/ok/warn/fail` (Tasks 1–2); `nja_is_project` (existing)
- Produces: the executable `nja-deps-sweep.sh [--dry-run|--apply] [--root <path>] [--reject <pkg,pkg,…>]`; internal function `sweep_manifests <root> <reject> <apply>` printing `SURFACE<TAB>LOCATION<TAB>PKG<TAB>FROM<TAB>TO` rows

The `ncu` invocation is `ncu --packageFile <manifest> --jsonUpgraded` (plus `-u` to write, plus `-x <reject>` when the reject list is non-empty). `--jsonUpgraded` emits a JSON object of upgrades only, parsed with `node -e` (no `jq` — see Global Constraints).

**Do not run `pnpm install` per directory.** Each app's `scripts/update.sh` does, and that is the sole source of the `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY` noise the old guide told readers to ignore. One root install happens in phase 2 of the skill.

- [ ] **Step 1: Write the failing test**

Create `nja/tests/test-deps-sweep.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-sweep`
Expected: FAIL — `nja-deps-sweep.sh: No such file or directory`

- [ ] **Step 3: Implement the sweep's manifest surface**

Create `nja/scripts/nja-deps-sweep.sh`:

```bash
#!/usr/bin/env bash
# nja-deps-sweep — update every dependency surface of an nja monorepo.
#
# Three surfaces, not one. `ncu` reads package.json manifests only: it cannot
# see pnpm `catalog:` entries (they are not semver ranges, so it skips them
# silently) and it never opens pnpm-workspace.yaml. In dreamer that leaves ~35
# packages — react, next, all six @nestjs/*, typescript, class-validator —
# outside every sweep. Surfaces 2 and 3 (Task 6) close that hole.
#
# Usage:
#   nja-deps-sweep.sh [--dry-run | --apply] [--root <path>] [--reject a,b,c]
#
# Exit codes:
#   0  success
#   1  usage or environment error
#   3  refused to write an override that would lower a declared floor
set -uo pipefail

NJA_SWEEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-deps-lib.sh
. "$NJA_SWEEP_DIR/nja-deps-lib.sh"

APPLY=0
ROOT=""
REJECT=""

usage() {
  cat <<'USAGE'
nja-deps-sweep.sh [--dry-run | --apply] [--root <path>] [--reject <pkg,pkg,...>]

  --dry-run   report only, write nothing (default)
  --apply     write package.json files and pnpm-workspace.yaml
  --root      repo root (default: the enclosing git toplevel)
  --reject    comma-separated hold-backs; never bumped on any surface
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) APPLY=0; shift ;;
    --apply)   APPLY=1; shift ;;
    --root)    ROOT="${2:-}"; shift 2 ;;
    --reject)  REJECT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

ROOT="$(nja_resolve_root "${ROOT:-$PWD}")"

if ! nja_is_project "$ROOT"; then
  nja_say "nja-deps-sweep: $ROOT is not an nja project — nothing to do."
  exit 0
fi

if [ ! -f "$ROOT/pnpm-workspace.yaml" ]; then
  nja_fail "no pnpm-workspace.yaml at $ROOT"
  exit 1
fi

command -v ncu >/dev/null 2>&1 || { nja_fail "ncu (npm-check-updates) is not on PATH"; exit 1; }

# ── surface 1: workspace manifests ───────────────────────────────────────────
sweep_manifests() {
  local root="$1" reject="$2" apply="$3"
  local ws manifest json args
  while IFS= read -r ws; do
    manifest="$root/$ws/package.json"
    [ "$ws" = "." ] && manifest="$root/package.json"
    [ -f "$manifest" ] || continue

    args=(--packageFile "$manifest" --jsonUpgraded)
    [ -n "$reject" ] && args+=(-x "$reject")
    [ "$apply" -eq 1 ] && args+=(-u)

    json="$(ncu "${args[@]}" 2>/dev/null)"
    [ -n "$json" ] || continue

    MANIFEST="$manifest" node -e '
      const fs = require("fs");
      let up = {};
      try { up = JSON.parse(process.argv[1] || "{}"); } catch { process.exit(0); }
      const cur = JSON.parse(fs.readFileSync(process.env.MANIFEST, "utf8"));
      const at = (p) => (cur.dependencies||{})[p] ?? (cur.devDependencies||{})[p] ?? "?";
      for (const [p, v] of Object.entries(up))
        console.log(["manifest", process.argv[2], p, at(p), v].join("\t"));
    ' "$json" "$ws"
  done <<EOF
$(nja_workspaces "$root")
EOF
}

# ── report ───────────────────────────────────────────────────────────────────
rows="$(sweep_manifests "$ROOT" "$REJECT" "$APPLY")"

if [ -z "$rows" ]; then
  nja_ok "no manifest updates available"
else
  nja_say ""
  nja_say "SURFACE    LOCATION                        PACKAGE                         FROM            TO"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "%-10s %-31s %-31s %-15s %s\n", $1, $2, $3, $4, $5 }'
fi

exit 0
```

Note on the `node -e` call: when `--apply` is set, `ncu -u` has already rewritten the manifest, so `at(p)` reads the *new* range and the FROM column would be wrong. Task 6 Step 5 fixes this by capturing the dry-run rows before applying; for this task the dry-run path is the tested one.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
chmod +x nja/scripts/nja-deps-sweep.sh
bash nja/tests/run.sh deps-sweep
```

Expected: PASS — 5 assertions

- [ ] **Step 5: Dry-run against two real repos**

```bash
bash nja/scripts/nja-deps-sweep.sh --root ~/Development/dreamer --dry-run
git -C ~/Development/dreamer status --short          # MUST be empty
bash nja/scripts/nja-deps-sweep.sh --root ~/Development/a360ai --dry-run
git -C ~/Development/a360ai status --short           # MUST be empty
```

Expected: rows for `.`, `apps/api`, `apps/web` (and `apps/corpus` for a360ai), `packages/*`. Both `git status` outputs empty — a non-empty one is a bug, stop and fix before continuing.

- [ ] **Step 6: Commit**

```bash
git add nja/scripts/nja-deps-sweep.sh nja/tests/test-deps-sweep.sh
git commit -m "feat(deps): sweep workspace manifests via ncu with reject support"
```

---

### Task 6: `nja-deps-sweep.sh` — catalog and overrides surfaces

**Files:**
- Modify: `nja/scripts/nja-deps-sweep.sh`
- Test: `nja/tests/test-deps-sweep.sh` (append)

**Interfaces:**
- Consumes: `nja_yaml_entries`, `nja_yaml_set_version` (Tasks 3–4)
- Produces: `sweep_catalog <root> <reject> <apply>` and `sweep_overrides <root> <reject> <apply>`, emitting the same `SURFACE<TAB>LOCATION<TAB>PKG<TAB>FROM<TAB>TO` rows; plus `NJA_LATEST_STUB` support so tests need no network

**The floor rule (spec §5.4):** a pnpm override **replaces** a declared range rather than intersecting with it, so an override below a manifest's floor silently resolves *under* that floor with no peer warning — this is how dreamer's `@nestjs/*` sat at 11.1.24 while every manifest declared `^11.1.28`. Before writing any override, confirm the new value is `>=` every range declared for that package across all manifests. Refuse with exit 3 otherwise.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-deps-sweep.sh`:

```bash
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
t_assert_eq "" "$(git -C "$repo" status --short)" "catalog dry-run writes nothing"

# reject is honoured on every surface
out="$(NJA_LATEST_STUB="$stub" bash "$SWEEP" --root "$repo" --dry-run --reject eslint,bullmq 2>&1)"
t_assert_not_contains "$out" "eslint" "reject suppresses a catalog entry"
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
cat > "$repo2/.latest" <<'STUB'
class-validator	0.15.1
STUB
t_assert_exit 3 "sweep refuses to lower a declared floor" -- \
  env NJA_LATEST_STUB="$repo2/.latest" bash "$SWEEP" --root "$repo2" --apply
t_assert_contains "$(NJA_LATEST_STUB="$repo2/.latest" bash "$SWEEP" --root "$repo2" --apply 2>&1)" \
  "class-validator" "the refusal names the package"
rm -rf "$repo2"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-sweep`
Expected: FAIL — no `catalog` surface in the report

- [ ] **Step 3: Implement version resolution and both surfaces**

Insert into `nja/scripts/nja-deps-sweep.sh`, after `sweep_manifests`:

```bash
# ── version resolution ───────────────────────────────────────────────────────
# Latest published version of a package. NJA_LATEST_STUB makes this hermetic
# for tests: a "pkg<TAB>version" file consulted instead of the registry.
latest_version() {
  local pkg="$1"
  if [ -n "${NJA_LATEST_STUB:-}" ] && [ -f "$NJA_LATEST_STUB" ]; then
    awk -F'\t' -v p="$pkg" '$1 == p { print $2; found = 1; exit } END { exit(found ? 0 : 1) }' \
      "$NJA_LATEST_STUB"
    return $?
  fi
  pnpm view "$pkg" version 2>/dev/null | tail -1
}

is_rejected() {
  local pkg="$1" list="$2" item
  [ -n "$list" ] || return 1
  local IFS=','
  for item in $list; do [ "$item" = "$pkg" ] && return 0; done
  return 1
}

# Re-apply the range operator the entry already used: ^9.39.5 -> ^9.44.0,
# a pinned 19.2.8 -> 19.4.0, >=13.15.20 -> >=13.16.0.
reranged() {
  local current="$1" latest="$2" op
  case "$current" in
    \^*) op="^" ;; \~*) op="~" ;; ">="*) op=">=" ;; *) op="" ;;
  esac
  printf '%s%s\n' "$op" "$latest"
}

# numeric-only major.minor.patch comparison; prints -1, 0 or 1
semver_cmp() {
  node -e '
    const norm = (s) => (String(s).match(/(\d+)\.(\d+)\.(\d+)/) || []).slice(1).map(Number);
    const a = norm(process.argv[1]), b = norm(process.argv[2]);
    if (!a.length || !b.length) { console.log(0); process.exit(0); }
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) { console.log(a[i] > b[i] ? 1 : -1); process.exit(0); }
    console.log(0);
  ' "$1" "$2"
}

# ── surface 2: catalog ───────────────────────────────────────────────────────
sweep_catalog() {
  local root="$1" reject="$2" apply="$3"
  local yaml="$root/pnpm-workspace.yaml" pkg cur lat new
  while IFS=$'\t' read -r pkg cur; do
    [ -n "$pkg" ] || continue
    is_rejected "$pkg" "$reject" && continue
    case "$cur" in catalog:*) continue ;; esac
    lat="$(latest_version "$pkg")" || continue
    [ -n "$lat" ] || continue
    new="$(reranged "$cur" "$lat")"
    [ "$new" = "$cur" ] && continue
    printf 'catalog\tpnpm-workspace.yaml\t%s\t%s\t%s\n' "$pkg" "$cur" "$new"
    [ "$apply" -eq 1 ] && nja_yaml_set_version "$yaml" catalog "$pkg" "$new"
  done <<EOF
$(nja_yaml_entries "$yaml" catalog)
EOF
}

# ── surface 3: overrides ─────────────────────────────────────────────────────
# Highest declared range for a package across every workspace manifest.
declared_floor() {
  local root="$1" pkg="$2" ws manifest best="" r
  while IFS= read -r ws; do
    manifest="$root/$ws/package.json"
    [ "$ws" = "." ] && manifest="$root/package.json"
    [ -f "$manifest" ] || continue
    r="$(PKG="$pkg" node -e '
      const p = require(process.argv[1]);
      const v = (p.dependencies||{})[process.env.PKG] ?? (p.devDependencies||{})[process.env.PKG];
      if (v && !/^(workspace|catalog|npm):/.test(v)) console.log(v);
    ' "$manifest" 2>/dev/null)"
    [ -n "$r" ] || continue
    if [ -z "$best" ] || [ "$(semver_cmp "$r" "$best")" = "1" ]; then best="$r"; fi
  done <<EOF
$(nja_workspaces "$root")
EOF
  printf '%s\n' "$best"
}

sweep_overrides() {
  local root="$1" reject="$2" apply="$3"
  local yaml="$root/pnpm-workspace.yaml" pkg cur lat new floor
  while IFS=$'\t' read -r pkg cur; do
    [ -n "$pkg" ] || continue
    is_rejected "$pkg" "$reject" && continue
    case "$cur" in catalog:*) continue ;; esac
    lat="$(latest_version "$pkg")" || continue
    [ -n "$lat" ] || continue
    new="$(reranged "$cur" "$lat")"
    [ "$new" = "$cur" ] && continue

    floor="$(declared_floor "$root" "$pkg")"
    if [ -n "$floor" ] && [ "$(semver_cmp "$new" "$floor")" = "-1" ]; then
      nja_fail "override $pkg: $new would sit below the declared floor $floor — refusing"
      nja_say "        an override REPLACES declared ranges; a low one resolves under the floor silently."
      return 3
    fi

    printf 'overrides\tpnpm-workspace.yaml\t%s\t%s\t%s\n' "$pkg" "$cur" "$new"
    [ "$apply" -eq 1 ] && nja_yaml_set_version "$yaml" overrides "$pkg" "$new"
  done <<EOF
$(nja_yaml_entries "$yaml" overrides)
EOF
}
```

- [ ] **Step 4: Wire the new surfaces into the report**

Replace the report section at the bottom of `nja/scripts/nja-deps-sweep.sh` with:

```bash
# ── report ───────────────────────────────────────────────────────────────────
# Rows are always collected from a DRY pass first: with --apply, ncu -u and the
# yaml writer have already rewritten the source, so a post-write read would
# report the new value in the FROM column.
rows="$(sweep_manifests "$ROOT" "$REJECT" 0)"
rows="$rows
$(sweep_catalog "$ROOT" "$REJECT" 0)"

ovr="$(sweep_overrides "$ROOT" "$REJECT" 0)"
ovr_code=$?
if [ "$ovr_code" -eq 3 ]; then exit 3; fi
rows="$rows
$ovr"

rows="$(printf '%s\n' "$rows" | grep -v '^[[:space:]]*$')"

if [ -z "$rows" ]; then
  nja_ok "everything is already up to date on all three surfaces"
else
  nja_say ""
  nja_say "SURFACE    LOCATION                        PACKAGE                         FROM            TO"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "%-10s %-31s %-31s %-15s %s\n", $1, $2, $3, $4, $5 }'
  nja_say ""
  nja_say "$(printf '%s\n' "$rows" | wc -l | tr -d ' ') update(s) available"
fi

if [ "$APPLY" -eq 1 ]; then
  sweep_manifests "$ROOT" "$REJECT" 1 >/dev/null
  sweep_catalog   "$ROOT" "$REJECT" 1 >/dev/null
  sweep_overrides "$ROOT" "$REJECT" 1 >/dev/null || exit 3
  nja_say ""
  nja_ok "applied — now run ONE root install:"
  nja_say "      CI=true pnpm install --no-frozen-lockfile"
fi

exit 0
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-sweep`
Expected: PASS — 19 assertions

- [ ] **Step 6: Dry-run against dreamer and confirm the hole is closed**

```bash
bash nja/scripts/nja-deps-sweep.sh --root ~/Development/dreamer --dry-run | tee /tmp/sweep.txt
grep -c '^catalog' /tmp/sweep.txt
git -C ~/Development/dreamer status --short   # MUST be empty
```

Expected: at least one `catalog` row — these are packages (`react`, `next`, `@nestjs/*`, `eslint`, …) that no previous sweep in this repo has ever been able to see. Tree still clean.

- [ ] **Step 7: Commit**

```bash
git add nja/scripts/nja-deps-sweep.sh nja/tests/test-deps-sweep.sh
git commit -m "feat(deps): sweep catalog and overrides surfaces with floor protection"
```

---

### Task 7: `nja-deps-doctor.sh` — duplicate resolutions and readlink pairs

**Files:**
- Create: `nja/scripts/nja-deps-doctor.sh`
- Test: `nja/tests/test-deps-doctor.sh`

**Interfaces:**
- Consumes: `nja_workspaces`, `nja_resolve_root`, output helpers, `nja_is_project`
- Produces: the executable `nja-deps-doctor.sh [--root <path>]`; internal `check_single_resolution <root>` and `check_readlink_pairs <root>`

Critical peers (spec §6.2): `@nestjs/common`, `@nestjs/core`, `react`, `react-dom`, `next`, `next-intl`, `class-validator`, `class-transformer`, `zod`.

Two versions of any of these is the signature of the dual-instance peer-fingerprint failure: backend `UnknownDependenciesException` at startup with all unit tests green, or a frontend `UseFormReturn` type mismatch that only production type-checking catches.

- [ ] **Step 1: Write the failing test**

Create `nja/tests/test-deps-doctor.sh`:

```bash
DOCTOR="$NJA_SCRIPTS_DIR/nja-deps-doctor.sh"

t_assert_exit 0 "doctor --help exits 0" -- bash "$DOCTOR" --help

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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-doctor`
Expected: FAIL — `nja-deps-doctor.sh: No such file or directory`

- [ ] **Step 3: Implement the doctor's mechanical checks**

Create `nja/scripts/nja-deps-doctor.sh`:

```bash
#!/usr/bin/env bash
# nja-deps-doctor — mechanical post-install checks for an nja monorepo.
#
# Run after every install. Two resolutions of a critical peer, or two
# workspaces linking to different copies of one, is the signature of the
# dual-instance peer-fingerprint failure: NestJS DI blows up at runtime with
# UnknownDependenciesException while every unit test stays green (they mock
# DI), or a frontend build fails on a UseFormReturn type mismatch.
#
# Usage: nja-deps-doctor.sh [--root <path>]
#
# Exit codes:
#   0  pass (WARNs allowed)
#   1  a delegated script failed, or environment error
#   2  duplicate resolution or readlink mismatch
set -uo pipefail

NJA_DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-deps-lib.sh
. "$NJA_DOCTOR_DIR/nja-deps-lib.sh"

CRITICAL_PEERS="@nestjs/common @nestjs/core react react-dom next next-intl class-validator class-transformer zod"

ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --help|-h) printf 'nja-deps-doctor.sh [--root <path>]\n'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

ROOT="$(nja_resolve_root "${ROOT:-$PWD}")"

if ! nja_is_project "$ROOT"; then
  nja_say "nja-deps-doctor: $ROOT is not an nja project — nothing to do."
  exit 0
fi

FAILED=0
WARNED=0

# pnpm encodes scoped names in .pnpm as "@scope+name@version"
pnpm_dirname() { printf '%s\n' "$1" | sed 's|/|+|'; }

# ── check 1: one resolution per critical peer ────────────────────────────────
check_single_resolution() {
  local root="$1" store="$1/node_modules/.pnpm" peer enc versions count
  if [ ! -d "$store" ]; then
    nja_warn "no node_modules/.pnpm — run an install before the doctor"
    WARNED=$((WARNED + 1))
    return 0
  fi
  for peer in $CRITICAL_PEERS; do
    enc="$(pnpm_dirname "$peer")"
    versions="$(ls "$store" 2>/dev/null \
      | grep -E "^$(printf '%s' "$enc" | sed 's/[+@]/\\&/g')@[0-9]" \
      | sed "s|^${enc}@||" | sed 's|_.*$||' | sort -u)"
    count="$(printf '%s\n' "$versions" | grep -c .)"
    [ "$count" -le 1 ] && continue
    nja_fail "$peer resolves to $count versions: $(printf '%s' "$versions" | tr '\n' ' ')"
    FAILED=$((FAILED + 1))
  done
}

# ── check 2: every workspace links to the same copy ──────────────────────────
check_readlink_pairs() {
  local root="$1" peer ws link target first_target="" first_ws="" mismatch
  for peer in $CRITICAL_PEERS; do
    first_target=""; first_ws=""; mismatch=0
    while IFS= read -r ws; do
      link="$root/$ws/node_modules/$peer"
      [ "$ws" = "." ] && link="$root/node_modules/$peer"
      [ -L "$link" ] || continue
      target="$(cd "$(dirname "$link")" && readlink "$(basename "$link")")"
      if [ -z "$first_target" ]; then
        first_target="$target"; first_ws="$ws"
      elif [ "$target" != "$first_target" ]; then
        nja_fail "$peer: $first_ws and $ws link to different copies"
        nja_say "        $first_ws -> $first_target"
        nja_say "        $ws -> $target"
        mismatch=1
      fi
    done <<EOF
$(nja_workspaces "$root")
EOF
    [ "$mismatch" -eq 1 ] && FAILED=$((FAILED + 1))
  done
}

nja_say "── resolution checks ─────────────────────────────"
check_single_resolution "$ROOT"
check_readlink_pairs "$ROOT"

if [ "$FAILED" -gt 0 ]; then
  nja_say ""
  nja_fail "$FAILED duplicate-resolution problem(s)"
  nja_say "  Fix: add an exact-version override for the package in pnpm-workspace.yaml,"
  nja_say "       then CI=true pnpm install --no-frozen-lockfile, then re-run this doctor."
  nja_say "  Background: skills/nja-update-dependencies/references/hazards.md §1"
  exit 2
fi

nja_ok "one resolution per critical peer; all workspace links agree"
[ "$WARNED" -gt 0 ] && nja_warn "$WARNED warning(s)"
exit 0
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
chmod +x nja/scripts/nja-deps-doctor.sh
bash nja/tests/run.sh deps-doctor
```

Expected: PASS — 9 assertions

- [ ] **Step 5: Run against dreamer's real installed tree**

```bash
bash nja/scripts/nja-deps-doctor.sh --root ~/Development/dreamer; echo "exit=$?"
```

Expected: exit 0. dreamer's `pnpm-workspace.yaml` overrides exist precisely to keep these single — a non-zero exit here means either a real duplicate (report it) or a bug in the checks (fix it).

- [ ] **Step 6: Commit**

```bash
git add nja/scripts/nja-deps-doctor.sh nja/tests/test-deps-doctor.sh
git commit -m "feat(deps): detect duplicate peer resolutions and link mismatches"
```

---

### Task 8: `nja-deps-doctor.sh` — delegated checks and published-version drift

**Files:**
- Modify: `nja/scripts/nja-deps-doctor.sh`
- Test: `nja/tests/test-deps-doctor.sh` (append)

**Interfaces:**
- Consumes: `FAILED`/`WARNED` counters and `nja_say/ok/warn/fail` from Task 7
- Produces: `check_delegated <root>` and `check_published_drift <root>`

`check_published_drift` is **report-only** (spec §6.4). It never fails the run, because resolving it means publishing a library — out of scope for this skill. It exists because nothing today can see this: dreamer's `packages/nestjs-neo4jsonapi` is 26 commits past its last tag while its `package.json` and `versions.production.json` both say `3.2.2`, so the production Docker build (`scripts/apply-production-versions.js` substitutes `workspace:*` → npm `3.2.2`) ships code that is not what the workspace builds. Rule 5 of `check-dep-drift.js` compares those two equal values and passes.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-deps-doctor.sh`:

```bash
repo="$(t_mkrepo)"
mkdir -p "$repo/node_modules/.pnpm" "$repo/scripts"

# a failing delegated script propagates as exit 1
cat > "$repo/scripts/check-dep-drift.js" <<'JS'
console.error("✖ dependency drift check failed (1):\n  - synthetic");
process.exit(1);
JS
t_assert_exit 1 "doctor exits 1 when a delegated script fails" -- bash "$DOCTOR" --root "$repo"
t_assert_contains "$(bash "$DOCTOR" --root "$repo" 2>&1)" "synthetic" \
  "doctor surfaces the delegated script's output"

# a passing delegated script does not fail the run
cat > "$repo/scripts/check-dep-drift.js" <<'JS'
console.log("✓ dependency drift check passed");
JS
t_assert_exit 0 "doctor exits 0 when the delegated script passes" -- bash "$DOCTOR" --root "$repo"

# published drift: submodule HEAD is past the tag for its declared version
sub="$repo/packages/nestjs-neo4jsonapi"
git -C "$sub" init -q 2>/dev/null || true
printf 'x\n' > "$sub/file.txt"
git -C "$sub" add -A >/dev/null 2>&1
git -C "$sub" -c user.email=t@t -c user.name=t commit -qm v322 >/dev/null 2>&1
git -C "$sub" tag v3.2.2 >/dev/null 2>&1
printf 'y\n' >> "$sub/file.txt"
git -C "$sub" add -A >/dev/null 2>&1
git -C "$sub" -c user.email=t@t -c user.name=t commit -qm ahead >/dev/null 2>&1

out="$(bash "$DOCTOR" --root "$repo" 2>&1)"
t_assert_contains "$out" "ahead of its published version" "doctor warns on published drift"
t_assert_contains "$out" "3.2.2" "the drift warning names the declared version"
t_assert_exit 0 "published drift is report-only and does not fail" -- bash "$DOCTOR" --root "$repo"

rm -rf "$repo"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh deps-doctor`
Expected: FAIL — the doctor exits 0 with the failing delegated script, and never prints "ahead of its published version"

- [ ] **Step 3: Implement both checks**

Insert into `nja/scripts/nja-deps-doctor.sh`, after `check_readlink_pairs`:

```bash
# ── check 3: delegated repo scripts ──────────────────────────────────────────
check_delegated() {
  local root="$1" out code
  if [ -f "$root/scripts/check-dep-drift.js" ]; then
    out="$(cd "$root" && node scripts/check-dep-drift.js 2>&1)"; code=$?
    printf '%s\n' "$out"
    [ "$code" -ne 0 ] && FAILED=$((FAILED + 1))
  fi
  if [ -f "$root/scripts/sync-production-versions.js" ]; then
    out="$(cd "$root" && node scripts/sync-production-versions.js --check 2>&1)"; code=$?
    printf '%s\n' "$out"
    [ "$code" -ne 0 ] && FAILED=$((FAILED + 1))
  fi
}

# ── check 4: published-version drift (REPORT ONLY) ───────────────────────────
# The workspace builds and tests submodule SOURCE; the production image
# installs the npm version pinned in versions.production.json. When the
# submodule sits past the tag for its declared version, those are different
# code. check-dep-drift.js rule 5 cannot see this: it compares
# versions.production.json against the submodule's package.json version, and
# both say the same stale number.
check_published_drift() {
  local root="$1" sub name version described
  for sub in "$root"/packages/*; do
    [ -d "$sub/.git" ] || [ -f "$sub/.git" ] || continue
    [ -f "$sub/package.json" ] || continue
    name="$(node -e 'console.log(require(process.argv[1]).name || "")' "$sub/package.json" 2>/dev/null)"
    version="$(node -e 'console.log(require(process.argv[1]).version || "")' "$sub/package.json" 2>/dev/null)"
    [ -n "$version" ] || continue
    described="$(git -C "$sub" describe --tags 2>/dev/null)"
    [ -n "$described" ] || continue
    case "$described" in
      "v$version"|"$version") continue ;;
    esac
    nja_warn "$name workspace source is ahead of its published version $version ($described)"
    nja_say "        the production image installs $version from npm — not this code."
    WARNED=$((WARNED + 1))
  done
}
```

- [ ] **Step 4: Wire them into the run**

In `nja/scripts/nja-deps-doctor.sh`, replace the block between `check_readlink_pairs "$ROOT"` and the `if [ "$FAILED" -gt 0 ]` test with:

```bash
nja_say ""
nja_say "── delegated checks ──────────────────────────────"
check_delegated "$ROOT"

nja_say ""
nja_say "── published-version drift (report only) ─────────"
check_published_drift "$ROOT"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh deps-doctor`
Expected: PASS — 16 assertions

- [ ] **Step 6: Confirm the known-true positive on dreamer**

```bash
bash nja/scripts/nja-deps-doctor.sh --root ~/Development/dreamer; echo "exit=$?"
```

Expected: exit 0, with a WARN naming `@carlonicora/nestjs-neo4jsonapi` as ahead of `3.2.2`. This is a real finding available today — if it does not appear, the check is wrong.

- [ ] **Step 7: Commit**

```bash
git add nja/scripts/nja-deps-doctor.sh nja/tests/test-deps-doctor.sh
git commit -m "feat(deps): delegate repo drift checks and report published-version drift"
```

---

### Task 9: `nja-dev-boot.sh` — process group launch and teardown

**Files:**
- Create: `nja/scripts/nja-dev-boot.sh`
- Create: `nja/tests/fixtures/fake-dev/dev-ok.sh`, `dev-hang.sh`, `dev-fatal.sh`, `stubborn.sh`
- Test: `nja/tests/test-dev-boot.sh`

**Interfaces:**
- Consumes: `nja_is_project`, `nja_resolve_root`, output helpers
- Produces: the executable `nja-dev-boot.sh [--root <path>] [--timeout <seconds>]`; env seams `NJA_DEV_CMD`, `NJA_READY_API`, `NJA_READY_WEB`, `NJA_READY_WORKER`

**Why a process group.** `pnpm dev` runs `scripts/dev.sh` → `turbo run dev dev:worker`, starting three persistent processes: api (`nodemon` → `ts-node`, port `API_PORT`), web (`next dev`, port `PORT`), and a **worker with no port at all**. Ports cannot reach the worker. Killing by name is forbidden — the owner runs several of these repos at once with byte-identical command lines, so a pattern cannot tell them apart, and this has already destroyed unrelated work once.

`setsid` does not exist on macOS. Verified alternative: `set -m` (job control) makes a backgrounded subshell its own process group leader with `PGID == PID`, and `kill -TERM -- -$PGID` reaps the whole tree. Confirmed by direct test on Darwin 25.5.0.

**SIGTERM before SIGKILL is load-bearing.** `scripts/dev.sh` sets `trap cleanup EXIT INT TERM` to remove `apps/web/.next-dev.lock`. SIGKILL skips the trap, the lock survives, and the *next* `pnpm dev` reads it as an unclean exit and wipes `apps/web/.next` — a slow cold rebuild caused by our own teardown.

- [ ] **Step 1: Write the fixtures**

Create `nja/tests/fixtures/fake-dev/dev-ok.sh`:

```bash
#!/usr/bin/env bash
# Stands in for `pnpm dev`: prints turbo-style ready lines, binds the two
# ports, and stays up until signalled.
set -uo pipefail
API_PORT="${API_PORT:-13950}"
WEB_PORT="${WEB_PORT:-13951}"

nc -l "$API_PORT" >/dev/null 2>&1 &
nc -l "$WEB_PORT" >/dev/null 2>&1 &

sleep 1
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 1.2s"
while :; do sleep 1; done
```

Create `nja/tests/fixtures/fake-dev/dev-hang.sh`:

```bash
#!/usr/bin/env bash
# Never becomes ready. Used to test the timeout path.
set -uo pipefail
echo "fixture-api:dev: starting..."
while :; do sleep 1; done
```

Create `nja/tests/fixtures/fake-dev/dev-fatal.sh`:

```bash
#!/usr/bin/env bash
# Emits a fatal pattern, then keeps running — the boot check must not wait for
# the process to exit before calling it a failure.
set -uo pipefail
sleep 1
echo "fixture-api:dev: [Nest] UnknownDependenciesException: Nest can't resolve dependencies of the FooService"
while :; do sleep 1; done
```

Create `nja/tests/fixtures/fake-dev/stubborn.sh`:

```bash
#!/usr/bin/env bash
# A child that ignores SIGINT (but not SIGTERM), plus a plain child.
# Proves teardown reaches every group member, not just the leader.
set -uo pipefail
trap '' INT
( trap '' INT; while :; do sleep 1; done ) &
( while :; do sleep 1; done ) &
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 0.9s"
wait
```

- [ ] **Step 2: Write the failing test — teardown first**

Create `nja/tests/test-dev-boot.sh`:

```bash
BOOT="$NJA_SCRIPTS_DIR/nja-dev-boot.sh"
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/fake-dev"

t_assert_exit 0 "dev-boot --help exits 0" -- bash "$BOOT" --help

outside="$(mktemp -d -t nja-outside)"
t_assert_contains "$(bash "$BOOT" --root "$outside" 2>&1)" "not an nja project" \
  "dev-boot is inert outside nja repos"
rm -rf "$outside"

repo="$(t_mkrepo)"
export API_PORT=13950 PORT=13951

# ── the collateral-damage regression test ────────────────────────────────────
# An unrelated long-lived process, of exactly the kind a name-pattern kill
# would destroy. It MUST survive.
bystander_out="$(mktemp -t nja-bystander)"
bash -c 'while :; do sleep 1; done' >"$bystander_out" 2>&1 &
BYSTANDER=$!

NJA_DEV_CMD="bash $FIX/stubborn.sh" \
  NJA_READY_WEB="Ready in" \
  bash "$BOOT" --root "$repo" --timeout 30 >/tmp/nja-boot-out.txt 2>&1
boot_code=$?

t_assert_eq "0" "$boot_code" "dev-boot exits 0 on a clean boot and teardown"
kill -0 "$BYSTANDER" 2>/dev/null && t_pass "unrelated process survived teardown" \
  || t_fail "unrelated process survived teardown" "the bystander was killed — a pattern kill leaked"
kill "$BYSTANDER" 2>/dev/null

t_assert_contains "$(cat /tmp/nja-boot-out.txt)" "ports free" "dev-boot verifies ports are released"

# the script must contain no pattern-kill, ever
src="$(cat "$BOOT")"
t_assert_not_contains "$src" "pkill" "dev-boot never calls pkill"
t_assert_not_contains "$src" "killall" "dev-boot never calls killall"

rm -rf "$repo"
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash nja/tests/run.sh dev-boot`
Expected: FAIL — `nja-dev-boot.sh: No such file or directory`

- [ ] **Step 4: Implement launch and teardown**

Create `nja/scripts/nja-dev-boot.sh`:

```bash
#!/usr/bin/env bash
# nja-dev-boot — start the dev stack, confirm it boots, tear it down cleanly.
#
# `pnpm dev` starts THREE persistent processes: api (port), web (port), and a
# worker with NO port. Ports alone cannot tear that down, and killing by name
# is forbidden — several nja repos run at once on this machine with identical
# command lines, so a pattern cannot tell them apart. The handle is the
# process group we create and own.
#
# macOS has no setsid; `set -m` makes a backgrounded subshell its own group
# leader (PGID == PID), which `kill -- -PGID` then addresses.
#
# Usage: nja-dev-boot.sh [--root <path>] [--timeout <seconds>]
#
# Env seams:
#   NJA_DEV_CMD     command to launch (default: pnpm dev). Word-split.
#   NJA_READY_API / NJA_READY_WEB / NJA_READY_WORKER   readiness regexes
#
# Exit codes:
#   0  booted and tore down cleanly
#   1  precondition failure (port busy, infra down, usage)
#   2  boot failed (timeout or fatal log pattern)
#   4  teardown unverified — SOMETHING MAY STILL BE RUNNING
set -uo pipefail

NJA_BOOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-detect.sh
. "$NJA_BOOT_DIR/nja-detect.sh"

nja_say()  { printf '%s\n' "$*"; }
nja_ok()   { printf '  ✓ %s\n' "$*"; }
nja_warn() { printf '  ⚠ %s\n' "$*"; }
nja_fail() { printf '  ✖ %s\n' "$*" >&2; }

ROOT=""
TIMEOUT=180
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-180}"; shift 2 ;;
    --help|-h) printf 'nja-dev-boot.sh [--root <path>] [--timeout <seconds>]\n'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

if git -C "${ROOT:-$PWD}" rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git -C "${ROOT:-$PWD}" rev-parse --show-toplevel)"
else
  ROOT="$(cd "${ROOT:-$PWD}" && pwd)"
fi

if ! nja_is_project "$ROOT"; then
  nja_say "nja-dev-boot: $ROOT is not an nja project — nothing to do."
  exit 0
fi

# ── ports ────────────────────────────────────────────────────────────────────
env_value() {
  local key="$1" f
  for f in "$ROOT/.env" "$ROOT/.env.example"; do
    [ -f "$f" ] || continue
    awk -F= -v k="$key" '$1 == k { print $2; exit }' "$f" | tr -d '"'"'"' \r'
  done | grep -m1 . || true
}

API_PORT="${API_PORT:-$(env_value API_PORT)}"; API_PORT="${API_PORT:-3950}"
WEB_PORT="${PORT:-$(env_value PORT)}";          WEB_PORT="${WEB_PORT:-3951}"

port_busy() { lsof -ti :"$1" -sTCP:LISTEN >/dev/null 2>&1; }
group_alive() { [ -n "$(ps -o pid= -g "$1" 2>/dev/null)" ]; }

# ── teardown — the only kill path in this script ─────────────────────────────
PGID=""
teardown() {
  [ -n "$PGID" ] || return 0
  kill -TERM -- "-$PGID" 2>/dev/null
  local waited=0
  while [ "$waited" -lt 20 ]; do
    group_alive "$PGID" || { PGID=""; return 0; }
    sleep 1; waited=$((waited + 1))
  done
  nja_warn "group $PGID ignored SIGTERM after 20s — escalating to SIGKILL"
  kill -KILL -- "-$PGID" 2>/dev/null
  sleep 1
  if group_alive "$PGID"; then return 1; fi
  PGID=""
  return 0
}
trap 'teardown >/dev/null 2>&1' EXIT INT TERM
```

- [ ] **Step 5: Add the launch and verification tail**

Append to `nja/scripts/nja-dev-boot.sh`:

```bash
# ── preconditions ────────────────────────────────────────────────────────────
for p in "$API_PORT" "$WEB_PORT"; do
  if port_busy "$p"; then
    nja_fail "port $p is already in use — refusing to start"
    nja_say "      That process is not ours. Stop it yourself, then re-run."
    nja_say "      Inspect it with: lsof -i :$p"
    exit 1
  fi
done

# ── launch ───────────────────────────────────────────────────────────────────
LOG="$(mktemp -t nja-dev-boot)"
nja_say "── booting ───────────────────────────────────────"
nja_say "  root:    $ROOT"
nja_say "  ports:   api=$API_PORT web=$WEB_PORT"
nja_say "  log:     $LOG"

cd "$ROOT" || exit 1
set -m
( ${NJA_DEV_CMD:-pnpm dev} ) >"$LOG" 2>&1 &
PGID=$!
set +m
nja_say "  group:   $PGID"

# ── teardown and verify ──────────────────────────────────────────────────────
finish() {
  local code="$1"
  if ! teardown; then
    nja_fail "TEARDOWN UNVERIFIED — group $PGID may still be running"
    nja_say "      Inspect: ps -o pid,pgid,args -g $PGID"
    exit 4
  fi
  local p
  for p in "$API_PORT" "$WEB_PORT"; do
    if port_busy "$p"; then
      nja_fail "TEARDOWN UNVERIFIED — port $p is still bound"
      exit 4
    fi
  done
  nja_ok "group terminated; ports free"
  if [ -f "$ROOT/apps/web/.next-dev.lock" ]; then
    nja_warn "apps/web/.next-dev.lock survived — dev.sh's trap did not run;"
    nja_say "        the next pnpm dev will clear apps/web/.next"
  fi
  nja_say "  log kept at: $LOG"
  exit "$code"
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
chmod +x nja/scripts/nja-dev-boot.sh nja/tests/fixtures/fake-dev/*.sh
bash nja/tests/run.sh dev-boot
```

Expected: the bystander and pattern-kill assertions PASS. The clean-boot assertion still fails — readiness detection arrives in Task 10. If the bystander assertion fails, **stop**: a kill is leaking outside the group.

- [ ] **Step 7: Commit**

```bash
git add nja/scripts/nja-dev-boot.sh nja/tests/test-dev-boot.sh nja/tests/fixtures
git commit -m "feat(deps): add process-group dev boot launcher with verified teardown"
```

---

### Task 10: `nja-dev-boot.sh` — readiness, fatal patterns, exit codes

**Files:**
- Modify: `nja/scripts/nja-dev-boot.sh`
- Test: `nja/tests/test-dev-boot.sh` (append)

**Interfaces:**
- Consumes: `LOG`, `PGID`, `finish`, `port_busy` (Task 9)
- Produces: the readiness poll loop and final exit-code selection

**Readiness discrimination.** `turbo run` prefixes every output line with `<package>:<task>:`. `apps/api` defines both `dev` and `dev:worker`, so the worker's lines carry `:dev:worker:` and the api's carry `:dev:` without it. That prefix is the discriminator and it is package-name-agnostic, so it works across all six repos (`dreamer-api`, `a360ai-api`, …).

**Unmatched worker signal is a WARN, not a failure** (spec §7.3): a log regex that does not match must never masquerade as a boot error.

- [ ] **Step 1: Write the failing test**

Append to `nja/tests/test-dev-boot.sh`:

```bash
repo="$(t_mkrepo)"
export API_PORT=13952 PORT=13953

# clean boot
out="$(NJA_DEV_CMD="bash $FIX/dev-ok.sh" bash "$BOOT" --root "$repo" --timeout 30 2>&1)"
code=$?
t_assert_eq "0" "$code" "clean boot exits 0"
t_assert_contains "$out" "api ready" "clean boot reports api ready"
t_assert_contains "$out" "web ready" "clean boot reports web ready"
t_assert_contains "$out" "worker ready" "clean boot reports worker ready"

# timeout
out="$(NJA_DEV_CMD="bash $FIX/dev-hang.sh" bash "$BOOT" --root "$repo" --timeout 6 2>&1)"
code=$?
t_assert_eq "2" "$code" "a boot that never becomes ready exits 2"
t_assert_contains "$out" "ports free" "teardown still runs after a timeout"

# fatal pattern short-circuits
start=$(date +%s)
out="$(NJA_DEV_CMD="bash $FIX/dev-fatal.sh" bash "$BOOT" --root "$repo" --timeout 60 2>&1)"
code=$?
elapsed=$(( $(date +%s) - start ))
t_assert_eq "2" "$code" "a fatal log pattern exits 2"
t_assert_contains "$out" "UnknownDependenciesException" "the fatal pattern is quoted in the report"
[ "$elapsed" -lt 30 ] && t_pass "fatal pattern short-circuits the wait" \
  || t_fail "fatal pattern short-circuits the wait" "took ${elapsed}s of a 60s timeout"

# occupied port
nc -l 13952 >/dev/null 2>&1 &
squatter=$!
sleep 1
t_assert_exit 1 "an occupied port aborts with exit 1" -- \
  env NJA_DEV_CMD="bash $FIX/dev-ok.sh" bash "$BOOT" --root "$repo" --timeout 10
kill -0 "$squatter" 2>/dev/null && t_pass "the squatting process was left alone" \
  || t_fail "the squatting process was left alone" "we killed a process we did not start"
kill "$squatter" 2>/dev/null

rm -rf "$repo"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash nja/tests/run.sh dev-boot`
Expected: FAIL — no "api ready" in the output; the clean boot never terminates on its own

- [ ] **Step 3: Implement the readiness poll**

Append to `nja/scripts/nja-dev-boot.sh` (after `finish`):

```bash
# ── readiness ────────────────────────────────────────────────────────────────
# turbo prefixes output with "<package>:<task>:". apps/api defines both `dev`
# and `dev:worker`, so the worker's lines carry ":dev:worker:" and the api's do
# not — a package-name-agnostic discriminator that holds across all six repos.
NEST_READY='Nest application successfully started|Application is running on'
NJA_READY_API="${NJA_READY_API:-$NEST_READY}"
NJA_READY_WORKER="${NJA_READY_WORKER:-$NEST_READY}"
NJA_READY_WEB="${NJA_READY_WEB:-Ready in|started server on|Local:}"

FATAL='UnknownDependenciesException|Cannot find module|ERR_MODULE_NOT_FOUND|ERR_PNPM_|UnhandledPromiseRejection'

saw_api()    { grep -E ':dev:' "$LOG" 2>/dev/null | grep -v ':dev:worker:' | grep -qE "$NJA_READY_API"; }
saw_worker() { grep -E ':dev:worker:' "$LOG" 2>/dev/null | grep -qE "$NJA_READY_WORKER"; }
saw_web()    { grep -qE "$NJA_READY_WEB" "$LOG" 2>/dev/null; }
saw_fatal()  { grep -qE "$FATAL" "$LOG" 2>/dev/null; }

api_ok=0; web_ok=0; worker_ok=0; waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if saw_fatal; then
    nja_fail "fatal pattern in the dev log:"
    grep -E "$FATAL" "$LOG" | head -5 | sed 's/^/        /'
    nja_say ""
    nja_say "  If this is UnknownDependenciesException, it is almost certainly a duplicate"
    nja_say "  peer resolution — run nja-deps-doctor.sh and read hazards.md §1."
    finish 2
  fi

  [ "$api_ok" -eq 0 ] && saw_api && port_busy "$API_PORT" && { api_ok=1; nja_ok "api ready (port $API_PORT)"; }
  [ "$web_ok" -eq 0 ] && saw_web && port_busy "$WEB_PORT" && { web_ok=1; nja_ok "web ready (port $WEB_PORT)"; }
  [ "$worker_ok" -eq 0 ] && saw_worker && { worker_ok=1; nja_ok "worker ready"; }

  [ "$api_ok" -eq 1 ] && [ "$web_ok" -eq 1 ] && [ "$worker_ok" -eq 1 ] && break

  if ! group_alive "$PGID"; then
    nja_fail "the dev stack exited before becoming ready"
    tail -60 "$LOG" | sed 's/^/        /'
    finish 2
  fi

  sleep 2; waited=$((waited + 2))
done

if [ "$api_ok" -eq 0 ] || [ "$web_ok" -eq 0 ]; then
  nja_fail "not ready after ${TIMEOUT}s (api=$api_ok web=$web_ok worker=$worker_ok)"
  tail -60 "$LOG" | sed 's/^/        /'
  finish 2
fi

# An unmatched log regex must never masquerade as a boot failure.
if [ "$worker_ok" -eq 0 ]; then
  nja_warn "worker readiness signal never matched — api and web booted and no fatal"
  nja_say "        pattern appeared, so this is reported as a PASS. Override the pattern"
  nja_say "        with NJA_READY_WORKER if this repo logs differently."
fi

nja_ok "dev stack booted"
finish 0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash nja/tests/run.sh dev-boot`
Expected: PASS — 17 assertions

- [ ] **Step 5: One real boot against dreamer**

Confirm Neo4j and Redis are up first, then:

```bash
bash nja/scripts/nja-dev-boot.sh --root ~/Development/dreamer --timeout 240; echo "exit=$?"
ls ~/Development/dreamer/apps/web/.next-dev.lock 2>/dev/null && echo "LOCK SURVIVED — bug" || echo "lock cleaned ✓"
lsof -i :3950 -i :3951 | grep LISTEN || echo "ports free ✓"
```

Expected: exit 0, all three ready lines, lock cleaned, ports free. Any leftover process is an exit-4 condition and a bug — fix before continuing.

- [ ] **Step 6: Run the whole suite**

Run: `bash nja/tests/run.sh`
Expected: PASS — every suite

- [ ] **Step 7: Commit**

```bash
git add nja/scripts/nja-dev-boot.sh nja/tests/test-dev-boot.sh
git commit -m "feat(deps): detect dev-stack readiness and fatal boot patterns"
```

---

### Task 11: `references/hazards.md`

**Files:**
- Create: `nja/skills/nja-update-dependencies/references/hazards.md`

**Interfaces:**
- Consumes: nothing executable
- Produces: the document the doctor's failure text and `SKILL.md` both cite by section number. **Section numbering is an interface** — `nja-deps-doctor.sh` prints "hazards.md §1" and `nja-dev-boot.sh` prints "hazards.md §1". Keep the dual-instance failure at §1.

Source material: `~/Development/dreamer/DEPENDENCY_UPGRADE_GUIDE.md` (896 lines; byte-identical in `neural-erp`, `only35`, `phlow`). Distil to roughly 200–250 lines. Drop §§2, 4, 9 (tagging, the ncu procedure, commit/push) — the phase table and the scripts replace them, and committing is out of scope. **Keep every failure story**: the guide's value is that each rule is paired with the incident that produced it, and a rule list without those stories invites rationalisation.

- [ ] **Step 1: Read the source**

```bash
sed -n '131,300p' ~/Development/dreamer/DEPENDENCY_UPGRADE_GUIDE.md   # §3 hold-backs
sed -n '536,600p' ~/Development/dreamer/DEPENDENCY_UPGRADE_GUIDE.md   # §7 dual-instance
sed -n '438,535p' ~/Development/dreamer/DEPENDENCY_UPGRADE_GUIDE.md   # §6 pnpm 11
sed -n '820,850p' ~/Development/dreamer/DEPENDENCY_UPGRADE_GUIDE.md   # §12 gotchas
cat ~/Development/dreamer/.pnpmfile.cjs
sed -n '1,60p' ~/Development/dreamer/scripts/update.sh                # the DEFERRED block
```

- [ ] **Step 2: Write the document**

Create `nja/skills/nja-update-dependencies/references/hazards.md` with exactly these sections, in this order:

1. **`## 1. The dual-instance peer-fingerprint failure`** — symptoms (backend: `UnknownDependenciesException` at startup for a service whose module is `@Global()`, with every unit test passing because they mock DI; frontend: `UseFormReturn` / `UseFormSetValue` type mismatches that lint and `next dev` miss and only the production type-check catches; `pnpm peers check` shows nothing either way). Mechanism: pnpm keys a package's instance by its resolved peers, so when an app and its library see different versions of one peer, the *same* package materialises twice. Detection: `nja-deps-doctor.sh`. Fix: exact-version override in `pnpm-workspace.yaml` → `CI=true pnpm install --no-frozen-lockfile` → re-run the doctor. Include the real `.pnpmfile.cjs` case: `supports-color` is an optional peer of `debug` and propagates into the peer fingerprint of `@nestjs/common`, `bullmq`, `@nestjs/bullmq` and `@nestjs/core`; the engine submodule's devDeps supply it while the apps do not, so stripping the optional peer at the root is what keeps `@nestjs+core*` a single directory. State plainly that removing that hook requires re-running `ls -d node_modules/.pnpm/@nestjs+core*` and seeing exactly one line.

2. **`## 2. Stack-invariant hold-backs`** — a table with columns *Package · Kept at · What breaks · What unblocks it*, one row each for `eslint` (`@typescript-eslint` v8's transitive `utils@8.49.0` crashes on ESLint 10 — `FlatESLint` removed), `typescript` (tsup's dts build errors on TS 6 because the shared tsconfigs use deprecated `baseUrl` + `moduleResolution: node10`; the backend needs `module: commonjs` for ts-node/NestJS and so cannot move to `bundler`), `class-validator` / `class-transformer` / `rxjs` / `reflect-metadata` (peer-fingerprint pins for `@nestjs/common` — §1), `react` / `react-dom` (the same hazard on the frontend, in lockstep with `nextjs-jsonapi`). Note that per-app holds live in that repo's `scripts/update.sh` `DEFERRED MAJOR BUMPS` block, not here.

3. **`## 3. The three dependency surfaces`** — why `ncu` sees only manifests, verified: a manifest with `"eslint": "catalog:"` and `"zod": "^4.0.0"` produces output listing only `zod`, silently. Name what that hides in dreamer (21 catalog entries, ~14 concrete overrides — react, next, all six `@nestjs/*`, typescript, class-validator, bullmq, yjs, jotai, openai, five `@floating-ui/*`). Then the floor rule: an override **replaces** a declared range rather than intersecting with it, so an override below a manifest's floor resolves under it with no warning — this is how `@nestjs/*` sat at 11.1.24 while every manifest declared `^11.1.28`.

4. **`## 4. pnpm 11`** — `pnpm.*` fields in `package.json` are no longer read; everything moves to `pnpm-workspace.yaml`. `onlyBuiltDependencies` (list) became `allowBuilds` (map), and the first install writes placeholder strings that must be replaced with booleans. `verifyDepsBeforeRun` now defaults to `install`, which shells out to `pnpm install` before every `pnpm run` — wrong in a production container, and the cause of the a360ai web crash-loop on 2026-08-05 (`prepare$ husky` → husky is a devDependency → `sh: husky: not found` → exit 1); `warn` keeps the signal without the implicit install. Record that `phlow` is still on pnpm 10.28.2 while the other five are on 11.18.0.

5. **`## 5. Gotchas`** — the symptom → cause → section table from guide §12, minus the rows about commits and pushes.

- [ ] **Step 3: Verify the cited section numbers match the scripts**

```bash
grep -n "hazards.md" nja/scripts/*.sh
grep -n "^## " nja/skills/nja-update-dependencies/references/hazards.md
```

Expected: every `hazards.md §N` printed by a script points at a section that exists with that number.

- [ ] **Step 4: Commit**

```bash
git add nja/skills/nja-update-dependencies/references/hazards.md
git commit -m "docs(deps): distil the dependency upgrade hazards into a skill reference"
```

---

### Task 12: `SKILL.md` and evals

**Files:**
- Create: `nja/skills/nja-update-dependencies/SKILL.md`
- Create: `nja/skills/nja-update-dependencies/evals/README.md`, `01-dirty-tree.md`, `02-held-major.md`, `03-doctor-duplicate.md`, `04-boot-failure.md`

**Interfaces:**
- Consumes: all three scripts and `references/hazards.md`
- Produces: the skill entry point. Follow the structure of `nja/skills/nja-verify/SKILL.md` — frontmatter, a core-principle statement, the procedure, and a failure-mode table.

- [ ] **Step 1: Read the two models to match**

```bash
cat nja/skills/nja-verify/SKILL.md
cat nja/skills/nja-architecture/evals/README.md
cat nja/skills/nja-architecture/evals/01-add-backend-entity-field.md
```

- [ ] **Step 2: Write `SKILL.md`**

Frontmatter, verbatim:

```yaml
---
name: nja-update-dependencies
description: Use when updating, upgrading, or sweeping npm dependencies in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo — the root, the apps (api/web/…), and the packages (nestjs-neo4jsonapi, nextjs-jsonapi, shared). Triggers include "update the packages", "upgrade dependencies", "dependency sweep", "bump the deps", or a request to check what is outdated. Runs the sweep, verifies with lint/build/dev-boot/test, and leaves everything uncommitted.
---
```

Body sections, in order:

**`# Dependency sweep`** — one paragraph: three surfaces, verified with lint/build/dev-boot/test, ends uncommitted.

**`## Core principle`** — the scripts own everything mechanical; the model owns only judgment calls (which majors to take, how to reconcile peers, how to read a failure). Never re-derive a check a script performs.

**`## Phases`** — this table verbatim:

| Phase | Action | Gate |
|---|---|---|
| 0 | Preflight: clean tree (root + both submodules); baseline `pnpm lint`, `pnpm build`, `pnpm test`; record submodule branches/SHAs; confirm Neo4j and Redis are up | **STOP** if the tree is dirty or the baseline is red |
| 1 | `nja-deps-sweep.sh --dry-run`; load holds; re-test each hold's unblock condition | **ASK** on every major |
| 2 | `nja-deps-sweep.sh --apply --reject <holds>`, then ONE `CI=true pnpm install --no-frozen-lockfile` at the root | — |
| 3 | Reconcile submodule `peerDependencies` and catalog floors against what the apps now resolve | — |
| 4 | `nja-deps-doctor.sh` | **STOP** on any non-zero exit |
| 5 | `pnpm lint` → `pnpm build` → `pnpm test` | **STOP** on error |
| 6 | `nja-dev-boot.sh` | **STOP** on any non-zero exit; exit 4 means something is still running — report that first |
| 7 | Report; rewrite the `DEFERRED MAJOR BUMPS` block in `scripts/update.sh` | — |

**`## Phase 0 — why a clean tree, not a tag`** — with a clean start, `HEAD` *is* the rollback point (`git checkout -- . && git clean -fd` in each repo), the final diff is exactly the sweep and therefore reviewable, and there are no tags to clean up. If the tree is dirty, stop and ask the user to commit or stash. **Never stash on the user's behalf here.**

**`## Phase 1 — hold-backs`** — two sources: stack-invariant holds from `references/hazards.md` §2, and per-app holds parsed from the `DEFERRED MAJOR BUMPS` comment at the top of `scripts/update.sh`. Where that file is absent (a360ai, and any freshly bootstrapped app), create a minimal one containing only the block and a pointer to this skill. Before proposing to keep a hold, re-test its stated unblock condition (`pnpm view <pkg> version`, `pnpm view <pkg> peerDependencies`) so stale holds surface instead of calcifying. Present every still-held major and every newly-proposed major through `AskUserQuestion`. Minors and patches proceed without asking.

**`## Phase 3 — submodule peers`** — if an app crossed a major on a package that is a `peerDependency` of its library, raise the library's peer range to match and raise the corresponding catalog floor. Both edits stay uncommitted inside the submodule worktree. `check-dep-drift.js` rules 1, 2 and 4 verify the result in phases 4–5.

**`## Phase 6 — the lazy baseline`** — the phase-0 baseline deliberately excludes a dev boot; it is slow and most runs never need it. If phase 6 fails, attribute it *then*: say so, `git stash -u` in each repo, reinstall, re-run `nja-dev-boot.sh` on the pre-sweep state, restore the stash. If the baseline also fails, the breakage is pre-existing and the sweep is not at fault. **This is the only place the skill may stash, it must announce it first, and it must restore.**

**`## Phase 7 — the report`** — seven required items: (1) what was bumped, grouped by surface and workspace; (2) what was held and why, one line each; (3) doctor findings including report-only WARNs; (4) lint / build / dev-boot / test results; (5) the exact rollback command per repo; (6) the exact submodules-first `git add` / `git commit` sequence, **not run**; (7) the manual test list.

**`## Hands-off`** — **This skill never commits, tags, or pushes.** The user commits after manual testing. Print the commands; run none of them.

**`## Failure modes — STOP if you catch yourself doing any of these`** — this table verbatim:

| Failure mode | Why it's wrong |
|---|---|
| "I'll `pkill -f 'next dev'` to clean up." | Forbidden. Several nja repos run at once with byte-identical command lines; a name pattern cannot tell them apart and has already destroyed unrelated work. Only the captured PGID — which is what `nja-dev-boot.sh` uses. |
| "The port is busy, I'll free it first." | That process is not ours. Abort and tell the user. |
| "`ncu` reported nothing for react, so react is current." | `ncu` cannot see `catalog:` — verified. The catalog is a separate surface; the sweep script handles it. |
| "Tests pass, so the upgrade is safe." | Unit tests mock NestJS DI and cannot catch the dual-instance failure. The dev boot is the real gate. |
| "I'll bump it and revert afterwards, like the old script did." | Holds go to `ncu --reject` so they are never bumped. Revert-after is how holds get missed. |
| "The tree was already dirty, I'll work around it." | Stop and ask. A dirty start makes the final diff unreviewable and rollback destructive. |
| "Build and test passed, I'll commit." | This skill never commits. That is the user's call after manual testing. |
| "SIGKILL is more reliable for teardown." | It skips `dev.sh`'s trap, orphans `.next-dev.lock`, and forces a `.next` wipe on the user's next dev run. TERM first; KILL only as escalation. |
| "The doctor passed, so I can skip the readlink output." | The doctor already did that comparison. Do not re-derive it — read its exit code. |

- [ ] **Step 3: Write the evals**

`evals/README.md` mirrors `nja-architecture/evals/README.md` (purpose, how to run, pass criteria). Then four scenarios, each stating *setup*, *the prompt*, and *pass criteria*:

- `01-dirty-tree.md` — repo has uncommitted changes. **Pass:** stops at phase 0, asks the user to commit or stash, does not stash on its own, runs no sweep.
- `02-held-major.md` — the dry run proposes `eslint 9 → 10`, which `scripts/update.sh` holds. **Pass:** re-tests the unblock condition (`pnpm view @typescript-eslint/parser peerDependencies`), presents it via `AskUserQuestion`, does not bump unilaterally.
- `03-doctor-duplicate.md` — `nja-deps-doctor.sh` exits 2 naming two `react` versions. **Pass:** stops, does not proceed to lint/build, proposes an exact-version override in `pnpm-workspace.yaml` and cites `hazards.md` §1.
- `04-boot-failure.md` — `nja-dev-boot.sh` exits 2 with `UnknownDependenciesException`. **Pass:** runs the lazy baseline before blaming the sweep, and routes to `hazards.md` §1 rather than guessing.

- [ ] **Step 4: Verify the frontmatter parses and paths resolve**

```bash
head -5 nja/skills/nja-update-dependencies/SKILL.md
grep -o 'nja-deps-[a-z]*\.sh\|nja-dev-boot\.sh\|references/[a-z]*\.md' \
  nja/skills/nja-update-dependencies/SKILL.md | sort -u | while read -r f; do
  ls nja/scripts/"$f" nja/skills/nja-update-dependencies/"$f" 2>/dev/null | head -1 || echo "MISSING: $f"
done
```

Expected: no `MISSING:` lines.

- [ ] **Step 5: Commit**

```bash
git add nja/skills/nja-update-dependencies
git commit -m "feat(deps): add the nja-update-dependencies skill and evals"
```

---

### Task 13: Registration and full verification

**Files:**
- Modify: `nja/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: every prior task
- Produces: an installable plugin at version `1.12.0`

- [ ] **Step 1: Bump the versions**

`nja/.claude-plugin/plugin.json` — set `"version": "1.12.0"` and extend the description's skill list with dependency sweeps.

`.claude-plugin/marketplace.json` — set `"version": "1.12.0"` in **both** the top-level object and `plugins[0]`. Both currently read `1.11.0`; a mismatch is the failure mode here.

- [ ] **Step 2: Verify both files are valid JSON and agree**

```bash
node -e 'const m=require("./.claude-plugin/marketplace.json"),p=require("./nja/.claude-plugin/plugin.json");
console.log("marketplace:",m.version,"plugins[0]:",m.plugins[0].version,"plugin:",p.version);
if(new Set([m.version,m.plugins[0].version,p.version]).size!==1) throw new Error("version mismatch");
console.log("✓ versions agree");'
```

Expected: `✓ versions agree`

- [ ] **Step 3: Add the README row**

In `README.md`, add to the Skills table, after the `nja-verify` row:

```markdown
| **`nja-update-dependencies`** | Updating or upgrading npm dependencies across the monorepo — root, apps, and `packages/*`. Sweeps all three surfaces (workspace manifests, pnpm `catalog:`, and concrete `overrides:` — `ncu` sees only the first), holds back the majors that break this stack, then verifies with lint, build, a real `pnpm dev` boot check, and tests. Leaves everything uncommitted for you to test and commit. |
```

Then add a short paragraph after the table noting that this skill ships three deterministic scripts (`nja-deps-sweep.sh`, `nja-deps-doctor.sh`, `nja-dev-boot.sh`) in the same spirit as `nja-lint.sh`, and that `nja-dev-boot.sh` tears the dev stack down by process group — never by name pattern.

- [ ] **Step 4: Run the full test suite**

```bash
bash nja/tests/run.sh
```

Expected: `all N passed`

- [ ] **Step 5: Full dry-run rehearsal across all six repos**

```bash
for d in a360ai dreamer neural-erp only35 phlow wyrdli; do
  echo "═══ $d ═══"
  bash nja/scripts/nja-deps-sweep.sh --root ~/Development/$d --dry-run 2>&1 | tail -5
  bash nja/scripts/nja-deps-doctor.sh --root ~/Development/$d >/dev/null 2>&1
  echo "doctor exit=$?"
  git -C ~/Development/$d status --short | head -3
done
```

Expected: every repo produces a sweep table; every `git status` is empty. A doctor exit of 2 on any repo is a **real finding** — report it to the user rather than editing that repo, since changing app repos is out of scope for this work.

- [ ] **Step 6: Confirm the process-safety invariant one last time**

```bash
grep -rn "pkill\|killall\|kill -9 \$(ps\|kill \$(pgrep" nja/scripts/ nja/skills/ && echo "VIOLATION" || echo "✓ no pattern kills anywhere"
```

Expected: `✓ no pattern kills anywhere`

- [ ] **Step 7: Commit**

```bash
git add nja/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "chore(release): 1.12.0 — nja-update-dependencies skill"
```

- [ ] **Step 8: Report to the user, do not merge or push**

Summarise: what was added, the full test-suite result, the six-repo rehearsal result, and any real findings from Step 5 (expect at least the `@carlonicora/nestjs-neo4jsonapi` published-version drift in dreamer). State the branch name and that nothing has been pushed or merged.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4 deliverables + registration | 1, 13 (plus `nja-deps-lib.sh`, a documented refinement) |
| §5.1 CLI | 5 |
| §5.2 manifests surface | 5 |
| §5.3 catalog surface | 3, 4, 6 |
| §5.4 overrides + floor rule | 6 |
| §5.5 output | 5, 6 |
| §5.6 exit codes | 5, 6 |
| §6.2 single resolution | 7 |
| §6.3 readlink pairs | 7 |
| §6.4 delegated + published drift | 8 |
| §6.5 exit codes | 7, 8 |
| §7.1 process groups | 9 |
| §7.2 procedure | 9, 10 |
| §7.3 readiness patterns | 10 |
| §7.4 infra precondition | 12 (phase 0 of `SKILL.md`) |
| §7.5 `NJA_DEV_CMD` testability | 9 |
| §7.6 exit codes | 9, 10 |
| §8 `SKILL.md` | 12 |
| §9 `hazards.md` | 11 |
| §10 testing | 1–10, 13 |

**Two spec items deliberately relocated, both noted inline:**

- §7.4's infra precondition lives in `SKILL.md` phase 0 rather than inside `nja-dev-boot.sh`. The script's port-busy check already covers the case where infra squats a port, and a Redis reachability probe inside a boot script would duplicate a check the phase-0 preflight makes anyway.
- §5's `--apply` FROM-column correctness is handled in Task 6 Step 4 (rows are always collected from a dry pass first), flagged as a known gap at the end of Task 5 Step 3.

**Placeholder scan:** no `TBD`/`TODO`; every code step carries runnable code; every test step names the command and the expected result. Task 11 and Task 12 specify document *content* section by section rather than pasting 250 lines of prose — the source material is cited by exact file and line range so the writer is not inventing.

**Type consistency:** `nja_workspaces`, `nja_yaml_entries`, `nja_yaml_list`, `nja_yaml_set_version`, `nja_resolve_root`, `nja_say/ok/warn/fail`, `latest_version`, `is_rejected`, `reranged`, `semver_cmp`, `declared_floor`, `sweep_manifests`, `sweep_catalog`, `sweep_overrides`, `check_single_resolution`, `check_readlink_pairs`, `check_delegated`, `check_published_drift`, `port_busy`, `group_alive`, `teardown`, `finish`, `saw_api/web/worker/fatal` — each defined once and called with the same name and arity everywhere. The row format `SURFACE<TAB>LOCATION<TAB>PKG<TAB>FROM<TAB>TO` is produced by all three sweep functions and consumed by one `awk` formatter. Exit codes match the spec tables and the Global Constraints block.
