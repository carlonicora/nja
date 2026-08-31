#!/usr/bin/env bash
# Shared helpers for the nja fleet scripts (survey, waves).
# SOURCED, never executed.
#
# Everything here is deterministic and side-effect free: no directory is
# created, no member is written to. The survey script owns all I/O.

NJA_FLEET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-deps-lib.sh
. "$NJA_FLEET_LIB_DIR/nja-deps-lib.sh"
# shellcheck source=./nja-detect.sh
. "$NJA_FLEET_LIB_DIR/nja-detect.sh"

NJA_FLEET_HOME="${NJA_FLEET_HOME:-$HOME/.claude/nja-fleet}"

# The two libraries every member consumes as submodules, in the order their
# fields appear in a facts line. Not configurable: a repo that vendors a
# different library is not an nja monorepo.
NJA_FLEET_LIBS="nestjs-neo4jsonapi nextjs-jsonapi"

# ── state ────────────────────────────────────────────────────────────────────
# nja_fleet_state_dir [date] — the run's state directory. Prints it; does NOT
# create it, so callers that only want to read a previous run cannot
# accidentally start a new one.
nja_fleet_state_dir() {
  printf '%s/%s\n' "$NJA_FLEET_HOME" "${1:-$(date +%F)}"
}

# ── identity ─────────────────────────────────────────────────────────────────
# nja_fleet_origin <path> — the member's identity: its origin URL, normalised
# so https://host/x and https://host/x.git are ONE member. Path is
# deliberately not the identity — a renamed directory is the same member.
nja_fleet_origin() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  [ -n "$url" ] || return 1
  url="${url%/}"
  url="${url%.git}"
  printf '%s\n' "$url"
}

# ── fleet SHA ────────────────────────────────────────────────────────────────
# nja_fleet_modal_sha <sha>... — the SHA held by a STRICT majority (> n/2).
# Prints it, returns 0. Prints nothing and returns 3 when none exists.
#
# Strict majority, not plurality, and that is the whole point: with three
# members at three different SHAs the fleet has forked, and "the most common
# of three ties" would silently pick a base for the user. Returning 3 makes
# the survey stop and ask instead.
nja_fleet_modal_sha() {
  local total=$# line count sha
  [ "$total" -gt 0 ] || return 3
  line="$(printf '%s\n' "$@" | sort | uniq -c | sort -rn | head -1)"
  count="$(printf '%s' "$line" | awk '{print $1}')"
  sha="$(printf '%s' "$line" | awk '{print $2}')"
  if [ $((count * 2)) -gt "$total" ]; then
    printf '%s\n' "$sha"
    return 0
  fi
  return 3
}

# ── facts ────────────────────────────────────────────────────────────────────
# nja_fleet_facts <path> — ONE tab-separated line, 11 fields:
#   1 name  2 path  3 origin  4 root_dirty  5 root_head
#   6 be_sha  7 be_branch  8 be_dirty
#   9 fe_sha 10 fe_branch 11 fe_dirty
# A missing submodule yields "-" in all three of its fields rather than an
# empty field, so `cut -f` never shifts and the line always has 11 fields.
nja_fleet_facts() {
  local p="$1" name origin rd rh lib s sha branch dirty
  name="$(basename "$p")"
  origin="$(nja_fleet_origin "$p")" || origin="-"
  rd="$(git -C "$p" status --porcelain 2>/dev/null | grep -c . || true)"
  rh="$(git -C "$p" rev-parse --short HEAD 2>/dev/null || printf '%s' '-')"
  printf '%s\t%s\t%s\t%s\t%s' "$name" "$p" "$origin" "$rd" "$rh"
  for lib in $NJA_FLEET_LIBS; do
    s="$p/packages/$lib"
    if git -C "$s" rev-parse HEAD >/dev/null 2>&1; then
      sha="$(git -C "$s" rev-parse HEAD)"
      branch="$(git -C "$s" rev-parse --abbrev-ref HEAD)"
      dirty="$(git -C "$s" status --porcelain | grep -c . || true)"
    else
      sha="-"; branch="-"; dirty="-"
    fi
    printf '\t%s\t%s\t%s' "$sha" "$branch" "$dirty"
  done
  printf '\n'
}

# ── eligibility ──────────────────────────────────────────────────────────────
# nja_fleet_eligibility <facts-line> <modal_be> <modal_fe>
# Exit 0 and no output when the member passes all four criteria. Otherwise one
# reason per line on stdout and exit 1. Reasons are emitted in criterion order
# so the report reads the same way every run.
nja_fleet_eligibility() {
  local line="$1" mbe="$2" mfe="$3" rc=0
  local rd be_sha be_br be_d fe_sha fe_br fe_d
  rd="$(printf '%s' "$line" | cut -f4)"
  be_sha="$(printf '%s' "$line" | cut -f6)"
  be_br="$(printf '%s' "$line" | cut -f7)"
  be_d="$(printf '%s' "$line" | cut -f8)"
  fe_sha="$(printf '%s' "$line" | cut -f9)"
  fe_br="$(printf '%s' "$line" | cut -f10)"
  fe_d="$(printf '%s' "$line" | cut -f11)"

  [ "$rd" = "0" ] || { printf 'root tree dirty (%s file(s))\n' "$rd"; rc=1; }

  if [ "$be_sha" = "-" ]; then
    printf 'nestjs-neo4jsonapi submodule not initialised\n'; rc=1
  else
    [ "$be_d" = "0" ]      || { printf 'nestjs-neo4jsonapi worktree dirty (%s file(s))\n' "$be_d"; rc=1; }
    [ "$be_br" = master ]  || { printf 'nestjs-neo4jsonapi not on master (%s)\n' "$be_br"; rc=1; }
    [ "$be_sha" = "$mbe" ] || { printf 'nestjs-neo4jsonapi not at the fleet SHA (%s)\n' "$(printf '%s' "$be_sha" | cut -c1-7)"; rc=1; }
  fi

  if [ "$fe_sha" = "-" ]; then
    printf 'nextjs-jsonapi submodule not initialised\n'; rc=1
  else
    [ "$fe_d" = "0" ]      || { printf 'nextjs-jsonapi worktree dirty (%s file(s))\n' "$fe_d"; rc=1; }
    [ "$fe_br" = master ]  || { printf 'nextjs-jsonapi not on master (%s)\n' "$fe_br"; rc=1; }
    [ "$fe_sha" = "$mfe" ] || { printf 'nextjs-jsonapi not at the fleet SHA (%s)\n' "$(printf '%s' "$fe_sha" | cut -c1-7)"; rc=1; }
  fi

  return "$rc"
}
