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
