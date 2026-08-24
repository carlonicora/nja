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

# require_optarg <option> <remaining-count> <candidate-value>
# Guards every value-taking option below. `shift 2` in bash is all-or-nothing:
# with only one argument left it shifts nothing, so a bare trailing `--root`
# (or `--reject`) would leave $1 unchanged and spin the while-loop forever.
# A value that itself looks like another flag (e.g. `--root --dry-run`) is
# never legitimate here either — every real value is a path, a comma list,
# or (in sibling scripts) an integer, none of which start with "-". Same
# shape is meant to be copied into the sibling scripts' parsers, not shared
# via nja-deps-lib.sh.
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) APPLY=0; shift ;;
    --apply)   APPLY=1; shift ;;
    --root)    require_optarg --root "$#" "${2:-}"; ROOT="$2"; shift 2 ;;
    --reject)  require_optarg --reject "$#" "${2:-}"; REJECT="$2"; shift 2 ;;
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
