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
#   0  pass — WARNs allowed (includes the report-only published-version
#      drift check, a missing pnpm-workspace.yaml, and unresolvable links)
#   1  a delegated repo script failed (scripts/check-dep-drift.js or
#      scripts/sync-production-versions.js), or an argument/environment error
#   2  duplicate resolution or readlink mismatch. Takes precedence over 1:
#      when both a resolution problem and a delegated-script failure are
#      present, exit 2 — a duplicate resolution is the more actionable
#      finding, and a failing delegated script is often just a downstream
#      symptom of it.
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
DELEGATED_FAILED=0
LINKS_COMPARED=0

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
      | grep -E "^$(printf '%s' "$enc" | sed 's/+/\\&/g')@[0-9]" \
      | sed "s|^${enc}@||" | sed 's|_.*$||' | sort -u)"
    count="$(printf '%s\n' "$versions" | grep -c .)"
    [ "$count" -le 1 ] && continue
    nja_fail "$peer resolves to $count versions: $(printf '%s' "$versions" | tr '\n' ' ')"
    FAILED=$((FAILED + 1))
  done
}

# resolve_link_target <link> — canonical absolute directory a symlink
# resolves to, following the ENTIRE chain (a link pointing at another
# symlink, which in turn points at the real store directory, resolves the
# same as a link pointing directly into the store). pnpm symlinks are
# relative to the symlink's OWN directory and their depth varies with the
# workspace's nesting (root: "node_modules/pkg -> .pnpm/pkg@v/node_modules/
# pkg"; a nested workspace: "apps/api/node_modules/pkg -> ../../../
# node_modules/.pnpm/pkg@v/node_modules/pkg") — two links can point at the
# exact same real directory while their raw `readlink` text differs purely
# because of that depth, or because one hops through an intermediate symlink
# the other doesn't. Comparing raw readlink output (as an earlier version of
# this check did) produced false positives on every real pnpm-installed tree
# tested against. An earlier version of this function canonicalised only the
# target's immediate parent and kept the leaf basename verbatim as text,
# which still compared unequal for a link pointing at another symlink versus
# one pointing directly into the store. `cd`-ing straight into the link and
# reading `pwd -P` instead asks the OS to resolve it: chdir(2) follows every
# hop in the chain, not just one, so this is both simpler and fully correct.
# Returns non-zero for a dangling or unreadable link — the caller treats
# that as "unresolvable", not as a mismatch.
resolve_link_target() {
  local link="$1"
  [ -L "$link" ] || return 1
  (cd "$link" 2>/dev/null && pwd -P)
}

# ── check 2: every workspace links to the same copy ──────────────────────────
# A safety check must never report a false all-clear. When pnpm-workspace.yaml
# is absent, nja_workspaces fails and prints nothing — the loop below would
# then compare zero links for zero peers and finish having "found" no
# mismatch, which is not the same thing as having verified agreement. Treat
# the absence as a skipped check (warn), not a pass. Likewise, a workspace
# whose link is dangling or otherwise unresolvable is excluded from the
# comparison rather than silently dropped — it is surfaced as its own
# warning so the operator learns about it even though a dangling link is not
# itself a duplicate-resolution finding.
check_readlink_pairs() {
  local root="$1" peer ws link target first_target="" first_ws="" mismatch workspaces rc

  workspaces="$(nja_workspaces "$root")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    nja_warn "no pnpm-workspace.yaml at $root — workspace link check skipped"
    WARNED=$((WARNED + 1))
    return 0
  fi

  for peer in $CRITICAL_PEERS; do
    first_target=""; first_ws=""; mismatch=0
    while IFS= read -r ws; do
      [ -n "$ws" ] || continue
      link="$root/$ws/node_modules/$peer"
      [ "$ws" = "." ] && link="$root/node_modules/$peer"
      [ -L "$link" ] || continue
      target="$(resolve_link_target "$link")"
      if [ -z "$target" ]; then
        nja_warn "$peer: $ws's link is unreadable or dangling ($link)"
        WARNED=$((WARNED + 1))
        continue
      fi
      LINKS_COMPARED=$((LINKS_COMPARED + 1))
      if [ -z "$first_target" ]; then
        first_target="$target"; first_ws="$ws"
      elif [ "$target" != "$first_target" ]; then
        nja_fail "$peer: $first_ws and $ws link to different copies"
        nja_say "        $first_ws -> $first_target"
        nja_say "        $ws -> $target"
        mismatch=1
      fi
    done <<EOF
$workspaces
EOF
    [ "$mismatch" -eq 1 ] && FAILED=$((FAILED + 1))
  done
}

# ── check 3: delegated repo scripts ──────────────────────────────────────────
# These are exit-1 problems, not exit-2 problems: a failing delegated script
# is not itself a duplicate-resolution/readlink-mismatch finding, so it must
# feed DELEGATED_FAILED, never FAILED — see the exit-code precedence note
# below the resolution-checks block.
check_delegated() {
  local root="$1" out code
  if [ -f "$root/scripts/check-dep-drift.js" ]; then
    out="$(cd "$root" && node scripts/check-dep-drift.js 2>&1)"; code=$?
    printf '%s\n' "$out"
    [ "$code" -ne 0 ] && DELEGATED_FAILED=$((DELEGATED_FAILED + 1))
  fi
  if [ -f "$root/scripts/sync-production-versions.js" ]; then
    out="$(cd "$root" && node scripts/sync-production-versions.js --check 2>&1)"; code=$?
    printf '%s\n' "$out"
    [ "$code" -ne 0 ] && DELEGATED_FAILED=$((DELEGATED_FAILED + 1))
  fi
}

# ── check 4: published-version drift (REPORT ONLY) ───────────────────────────
# The workspace builds and tests submodule SOURCE; the production image
# installs the npm version pinned in versions.production.json. When the
# submodule sits past the tag for its declared version, those are different
# code. check-dep-drift.js rule 5 cannot see this: it compares
# versions.production.json against the submodule's package.json version, and
# both say the same stale number. Resolving it means publishing a library —
# out of scope for this tool — so this NEVER fails the run, only warns.
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

nja_say "── resolution checks ─────────────────────────────"
check_single_resolution "$ROOT"
check_readlink_pairs "$ROOT"

nja_say ""
nja_say "── delegated checks ──────────────────────────────"
check_delegated "$ROOT"

nja_say ""
nja_say "── published-version drift (report only) ─────────"
check_published_drift "$ROOT"

# FAILED counts only duplicate-resolution / readlink-mismatch problems (exit
# 2). DELEGATED_FAILED counts a failing delegated script (exit 1) — its own
# counter, since one counter cannot produce two different exit codes. FAILED
# is checked first even though check_delegated ran after it: a duplicate
# resolution is the more actionable finding, and a failing delegated script
# is often just a downstream symptom of it, so resolution problems outrank
# delegated failures when both are present.
if [ "$FAILED" -gt 0 ]; then
  nja_say ""
  nja_fail "$FAILED duplicate-resolution problem(s)"
  nja_say "  Fix: add an exact-version override for the package in pnpm-workspace.yaml,"
  nja_say "       then CI=true pnpm install --no-frozen-lockfile, then re-run this doctor."
  nja_say "  Background: skills/nja-update-dependencies/references/hazards.md §1"
  exit 2
fi

if [ "$DELEGATED_FAILED" -gt 0 ]; then
  nja_say ""
  nja_fail "$DELEGATED_FAILED delegated script problem(s)"
  exit 1
fi

nja_ok "one resolution per critical peer"
[ "$LINKS_COMPARED" -gt 0 ] && nja_ok "all workspace links agree"
[ "$WARNED" -gt 0 ] && nja_warn "$WARNED warning(s)"
exit 0
