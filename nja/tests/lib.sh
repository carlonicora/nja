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
  local d; d="$(cd "$(mktemp -d -t nja-fixture)" && pwd -P)"
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

# t_mklib <parent-dir> <name> — a bare library origin with one commit on
# master. Prints the bare repo's path, which is what a member's .gitmodules
# will point at.
#
# Bare, not a plain worktree: `git submodule add` against a non-bare repo
# whose checked-out branch is master is refused by git, and a bare origin is
# also what the real submodules point at. Master is created explicitly —
# git's default branch name is user-configurable, and the eligibility gate
# tests for "master" by name.
t_mklib() {
  local parent="$1" name="$2" work bare
  bare="$parent/origin/$name.git"
  work="$(mktemp -d -t nja-lib)"
  mkdir -p "$parent/origin"
  git -C "$work" init -q -b master
  printf '{ "name": "@carlonicora/%s", "version": "1.0.0" }\n' "$name" > "$work/package.json"
  git -C "$work" add -A >/dev/null 2>&1
  git -C "$work" -c user.email=t@t -c user.name=t commit -qm "init $name" >/dev/null 2>&1
  git clone -q --bare "$work" "$bare" >/dev/null 2>&1
  rm -rf "$work"
  printf '%s\n' "$bare"
}

# t_mkfleet <n> — a directory of <n> nja-detectable member repos, each with
# both libraries as REAL submodules pinned at the same SHA, plus origin/
# holding the bare library repos. Prints the fleet directory.
#
# `-c protocol.file.allow=always` is mandatory: git 2.38+ refuses file://
# submodule clones by default (CVE-2022-39253), and every fixture origin
# here is a local path.
t_mkfleet() {
  local n="${1:-3}" fleet be fe i m
  fleet="$(cd "$(mktemp -d -t nja-fleet)" && pwd -P)"
  be="$(t_mklib "$fleet" nestjs-neo4jsonapi)"
  fe="$(t_mklib "$fleet" nextjs-jsonapi)"
  i=1
  while [ "$i" -le "$n" ]; do
    m="$fleet/member-$i"
    mkdir -p "$m"
    git -C "$m" init -q -b main
    cat > "$m/package.json" <<'JSON'
{ "name": "member", "version": "1.0.0", "private": true,
  "dependencies": { "@carlonicora/nestjs-neo4jsonapi": "workspace:*" } }
JSON
    printf 'packages:\n  - %s\n' "'packages/*'" > "$m/pnpm-workspace.yaml"
    git -C "$m" remote add origin "https://example.test/member-$i.git"
    git -C "$m" -c protocol.file.allow=always submodule add -q -b master "$be" packages/nestjs-neo4jsonapi >/dev/null 2>&1
    git -C "$m" -c protocol.file.allow=always submodule add -q -b master "$fe" packages/nextjs-jsonapi   >/dev/null 2>&1
    git -C "$m" add -A >/dev/null 2>&1
    git -C "$m" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
    # submodule add leaves the worktree on the tracked branch; make that
    # explicit so the fixture starts in the state the eligibility gate expects.
    git -C "$m/packages/nestjs-neo4jsonapi" checkout -q master
    git -C "$m/packages/nextjs-jsonapi"     checkout -q master
    i=$((i + 1))
  done
  printf '%s\n' "$fleet"
}
