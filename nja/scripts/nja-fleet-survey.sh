#!/usr/bin/env bash
# nja-fleet-survey — discover every nja monorepo on this machine, compute
# each one's eligibility for a fleet dependency run, and print the roster.
#
# The roster is NEVER stored in the skill: it is rediscovered on every
# invocation and confirmed by the user. This script only reports; it selects
# nothing and writes nothing into a member.
#
# Usage:
#   nja-fleet-survey.sh [--roots <path,path,...>] [--json] [--save]
#
#   --roots   scan these roots INSTEAD of the defaults, comma separated.
#             Omit it to scan the parent of the invoking repo plus every
#             root persisted by a previous --save. Replace, not add: a user
#             who scopes a run to one directory must not silently get the
#             whole machine, and a test fixture must not merge with the
#             real fleet.
#   --json    machine-readable roster on stdout (the skill reads this)
#   --save    persist --roots into $NJA_FLEET_HOME/roots.json for later runs
#
# Exit codes:
#   0  roster produced
#   1  usage or environment error
#   2  no nja members found in any root
#   3  the fleet has FORKED — no strict-majority SHA for one of the two
#      libraries. Deliberately fatal: picking a base for the user is exactly
#      what the eligibility model forbids.
set -uo pipefail

NJA_SURVEY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-fleet-lib.sh
. "$NJA_SURVEY_DIR/nja-fleet-lib.sh"

ROOTS=""
JSON=0
SAVE=0

usage() {
  cat <<'USAGE'
nja-fleet-survey.sh [--roots <path,path,...>] [--json] [--save]

  --roots   scan these roots instead of the defaults, comma separated
  --json    machine-readable roster on stdout
  --save    persist --roots for later runs
USAGE
}

# Same shape as nja-deps-sweep.sh's parser guard — copied per script,
# deliberately not shared, because a bare trailing `--roots` would otherwise
# leave $1 unchanged and spin the while-loop forever.
require_optarg() {
  local opt="$1" remaining="$2" val="${3:-}"
  if [ "$remaining" -lt 2 ]; then
    printf '%s requires a value\n' "$opt" >&2; usage >&2; exit 1
  fi
  case "$val" in
    -*) printf '%s requires a value, got option-like argument: %s\n' "$opt" "$val" >&2
        usage >&2; exit 1 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --roots) require_optarg --roots "$#" "${2:-}"; ROOTS="$2"; shift 2 ;;
    --json)  JSON=1; shift ;;
    --save)  SAVE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

# ── scan roots ───────────────────────────────────────────────────────────────
# With --roots: exactly those. Without: the parent of the invoking repo (the
# common case — ~/Development) plus everything a previous --save persisted.
#
# Replace, not add. An additive --roots silently unions the whole default
# tree into every scoped run, which merges unrelated fleets and makes the
# roster depend on where the command happened to be invoked from.
ROOTS_FILE="$NJA_FLEET_HOME/roots.json"
all_roots() {
  local here
  if [ -n "$ROOTS" ]; then
    printf '%s\n' "$ROOTS" | tr ',' '\n'
    return 0
  fi
  here="$(nja_resolve_root "$PWD")"
  printf '%s\n' "$(dirname "$here")"
  if [ -f "$ROOTS_FILE" ]; then
    node -e 'try{JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).forEach(r=>console.log(r))}catch(e){}' "$ROOTS_FILE"
  fi
}

ROOT_LIST="$(all_roots | grep -v '^$' | sort -u)"

# ── discovery ────────────────────────────────────────────────────────────────
# A candidate is any immediate subdirectory of a root that nja_is_project
# accepts — the SAME predicate the plugin's hooks use, so a repo created
# tomorrow is a fleet candidate with no change here.
FACTS=""
SEEN_ORIGINS=""
DUPES=""
for root in $ROOT_LIST; do
  [ -d "$root" ] || continue
  for cand in "$root"/*; do
    [ -d "$cand" ] || continue
    git -C "$cand" rev-parse --show-toplevel >/dev/null 2>&1 || continue
    nja_is_project "$cand" || continue
    origin="$(nja_fleet_origin "$cand")" || origin="-"
    # Identity is the origin. A second checkout of the same repo is a
    # duplicate to report, not a member to sweep twice.
    case "$SEEN_ORIGINS" in
      *"|$origin|"*) DUPES="$DUPES$origin"$'\n'; continue ;;
    esac
    [ "$origin" = "-" ] || SEEN_ORIGINS="$SEEN_ORIGINS|$origin|"
    FACTS="$FACTS$(nja_fleet_facts "$cand")"$'\n'
  done
done

MEMBER_COUNT="$(printf '%s\n' "$FACTS" | grep -c . || true)"
if [ "$MEMBER_COUNT" -eq 0 ]; then
  nja_fail "no nja monorepos found in: $(printf '%s' "$ROOT_LIST" | tr '\n' ' ')"
  exit 2
fi

# ── fleet SHA ────────────────────────────────────────────────────────────────
BE_SHAS="$(printf '%s\n' "$FACTS" | grep -v '^$' | cut -f6 | grep -v '^-$')"
FE_SHAS="$(printf '%s\n' "$FACTS" | grep -v '^$' | cut -f9 | grep -v '^-$')"

fork_report() {
  local lib="$1" shas="$2"
  nja_fail "the fleet has forked: no strict-majority SHA for $lib"
  printf '%s\n' "$shas" | sort | uniq -c | sort -rn >&2
  nja_say "Pick the intended base and reconcile the outliers before running a fleet sweep." >&2
}

if [ -z "$BE_SHAS" ]; then
  nja_fail "no member has an initialised nestjs-neo4jsonapi submodule"
  exit 3
fi
if [ -z "$FE_SHAS" ]; then
  nja_fail "no member has an initialised nextjs-jsonapi submodule"
  exit 3
fi

# The assignment stands alone so $? is the function's status, not a `local`'s.
# shellcheck disable=SC2086
MODAL_BE="$(nja_fleet_modal_sha $BE_SHAS)"
if [ $? -ne 0 ]; then fork_report nestjs-neo4jsonapi "$BE_SHAS"; exit 3; fi
# shellcheck disable=SC2086
MODAL_FE="$(nja_fleet_modal_sha $FE_SHAS)"
if [ $? -ne 0 ]; then fork_report nextjs-jsonapi "$FE_SHAS"; exit 3; fi

# ── persist roots ────────────────────────────────────────────────────────────
if [ "$SAVE" = "1" ] && [ -n "$ROOTS" ]; then
  mkdir -p "$NJA_FLEET_HOME"
  ROOT_LIST="$ROOT_LIST" node -e '
    const fs = require("fs");
    const roots = process.env.ROOT_LIST.split("\n").filter(Boolean);
    fs.writeFileSync(process.argv[1], JSON.stringify(roots, null, 2) + "\n");
  ' "$ROOTS_FILE"
fi

# ── output ───────────────────────────────────────────────────────────────────
emit() {
  local line name path origin rh be_sha fe_sha reasons
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="$(printf '%s' "$line" | cut -f1)"
    path="$(printf '%s' "$line" | cut -f2)"
    origin="$(printf '%s' "$line" | cut -f3)"
    rh="$(printf '%s' "$line" | cut -f5)"
    be_sha="$(printf '%s' "$line" | cut -f6)"
    fe_sha="$(printf '%s' "$line" | cut -f9)"
    reasons="$(nja_fleet_eligibility "$line" "$MODAL_BE" "$MODAL_FE")"
    if [ -z "$reasons" ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t1\t\n' "$name" "$path" "$origin" "$rh" "$be_sha" "$fe_sha"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t0\t%s\n' "$name" "$path" "$origin" "$rh" "$be_sha" "$fe_sha" \
        "$(printf '%s' "$reasons" | tr '\n' ';')"
    fi
  done
}

ROWS="$(printf '%s\n' "$FACTS" | emit)"

if [ "$JSON" = "1" ]; then
  ROWS="$ROWS" MODAL_BE="$MODAL_BE" MODAL_FE="$MODAL_FE" node -e '
    const rows = (process.env.ROWS || "").split("\n").filter(Boolean).map(l => {
      const f = l.split("\t");
      return {
        name: f[0], path: f[1], origin: f[2], head: f[3],
        nestjs_neo4jsonapi: f[4], nextjs_jsonapi: f[5],
        eligible: f[6] === "1",
        reasons: (f[7] || "").split(";").filter(Boolean),
      };
    });
    console.log(JSON.stringify({
      fleet_sha: {
        "nestjs-neo4jsonapi": process.env.MODAL_BE,
        "nextjs-jsonapi": process.env.MODAL_FE,
      },
      members: rows,
    }, null, 2));
  '
else
  nja_say "fleet SHA  nestjs-neo4jsonapi $(printf '%s' "$MODAL_BE" | cut -c1-7)   nextjs-jsonapi $(printf '%s' "$MODAL_FE" | cut -c1-7)"
  nja_say ""
  printf '%s\n' "$ROWS" | while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ "$(printf '%s' "$r" | cut -f7)" = "1" ]; then
      nja_ok "$(printf '%s' "$r" | cut -f1)  ($(printf '%s' "$r" | cut -f4))"
    else
      nja_warn "$(printf '%s' "$r" | cut -f1)  ($(printf '%s' "$r" | cut -f4))  INELIGIBLE"
      printf '%s' "$r" | cut -f8 | tr ';' '\n' | while IFS= read -r why; do
        [ -n "$why" ] && printf '      · %s\n' "$why"
      done
    fi
  done
fi

if [ -n "$DUPES" ]; then
  printf '%s\n' "$DUPES" | grep -v '^$' | sort -u | while IFS= read -r d; do
    nja_warn "duplicate checkout of $d — only the first was surveyed"
  done
fi

exit 0
