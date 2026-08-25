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

usage() {
  printf 'nja-deps-doctor.sh [--root <path>]\n'
}

# require_optarg <option> <remaining-count> <candidate-value>
# Guards --root. `shift 2` in bash is all-or-nothing: with only one argument
# left it shifts nothing, so a bare trailing `--root` would leave $1
# unchanged and spin the while-loop forever. A value that itself looks like
# another flag (e.g. `--root --help`) is never legitimate here either — the
# only real value is a path, which never starts with "-". Mirrors the guard
# in nja-deps-sweep.sh; kept local to this script rather than shared via
# nja-deps-lib.sh.
require_optarg() {
  local opt="$1" remaining="$2" val="${3:-}"
  if [ "$remaining" -lt 2 ]; then
    printf '%s requires a value\n' "$opt" >&2
    usage >&2
    exit 1
  fi
  case "$val" in
    -*)
      printf '%s requires a value, got option-like argument: %s\n' "$opt" "$val" >&2
      usage >&2
      exit 1
      ;;
  esac
}

ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)    require_optarg --root "$#" "${2:-}"; ROOT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
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

# resolve_link_target <link> — canonical absolute directory a symlink
# resolves to. pnpm symlinks are relative to the symlink's OWN directory and
# their depth varies with the workspace's nesting (root: "node_modules/pkg ->
# .pnpm/pkg@v/node_modules/pkg"; a nested workspace: "apps/api/node_modules/
# pkg -> ../../../node_modules/.pnpm/pkg@v/node_modules/pkg") — two links can
# point at the exact same real directory while their raw `readlink` text
# differs purely because of that depth. Comparing raw readlink output (as an
# earlier version of this check did) produced false positives on every real
# pnpm-installed tree tested against; resolving to a canonical path first is
# what makes the comparison mean anything.
resolve_link_target() {
  local link="$1" linkdir target
  linkdir="$(dirname "$link")"
  target="$(cd "$linkdir" 2>/dev/null && readlink "$(basename "$link")")" || return 1
  [ -n "$target" ] || return 1
  (cd "$linkdir" && cd "$(dirname "$target")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$target")")
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
      target="$(resolve_link_target "$link")"
      [ -n "$target" ] || continue
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

# FAILED counts only duplicate-resolution / readlink-mismatch problems (exit
# 2). A future delegated-check surface (Task 8: exit 1 on a delegated script
# failure) needs its own counter — a single shared counter cannot produce two
# different exit codes, and FAILED must not become that counter's dumping
# ground. Check that counter first/separately below when it exists.
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
