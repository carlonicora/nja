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
  # Glob-match, mirroring ncu's own -x semantics: `--reject '@nestjs/*'` must
  # hold back the whole scope on every surface, not just the manifest surface
  # (where ncu -x already glob-matches) — @nestjs lives in the catalog block.
  # `read -ra` (not `for item in $list`) splits on IFS=',' WITHOUT subjecting
  # each item to pathname expansion against the CWD, which a bare unquoted
  # `for item in $list` would do for any item containing a glob character.
  local IFS=','
  local -a items
  read -ra items <<< "$list"
  for item in "${items[@]}"; do
    case "$pkg" in
      $item) return 0 ;;
    esac
  done
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

# Write a version into pnpm-workspace.yaml and translate nja_yaml_set_version's
# three-way contract into this function's own return code:
#   0  written, or nothing to write (apply=0)
#   1  the key vanished between read and write — a logic error, since every
#      caller only writes keys it just read out of the same block. Surfaced,
#      never swallowed.
#   2  hard failure (awk/mv/write error) — fatal, reported with package+file.
# Callers must stop the surface immediately on a non-zero return; a silent
# write failure across six repos while the sweep reports success is exactly
# the outcome this project exists to prevent.
write_yaml_version() {
  local yaml="$1" block="$2" pkg="$3" new="$4"
  local wrc
  nja_yaml_set_version "$yaml" "$block" "$pkg" "$new"
  wrc=$?
  case "$wrc" in
    0) return 0 ;;
    1)
      nja_fail "$block: $pkg vanished from $yaml between read and write — logic error, not writing"
      return 1
      ;;
    *)
      nja_fail "$block: failed to write $pkg -> $new in $yaml (nja_yaml_set_version exit $wrc)"
      return 2
      ;;
  esac
}

# ── surface 2: catalog ───────────────────────────────────────────────────────
sweep_catalog() {
  local root="$1" reject="$2" apply="$3"
  local yaml="$root/pnpm-workspace.yaml" pkg cur lat new wrc
  while IFS=$'\t' read -r pkg cur; do
    [ -n "$pkg" ] || continue
    is_rejected "$pkg" "$reject" && continue
    case "$cur" in catalog:*) continue ;; esac
    lat="$(latest_version "$pkg")" || continue
    [ -n "$lat" ] || continue
    new="$(reranged "$cur" "$lat")"
    [ "$new" = "$cur" ] && continue
    if [ "$(semver_cmp "$new" "$cur")" = "-1" ]; then
      # latest_version can legitimately report a version BELOW what is
      # already pinned (a pin ahead of the registry's "latest" dist-tag,
      # e.g. a prerelease/next build) — never let that resolve as a
      # silent downgrade.
      nja_warn "catalog $pkg: latest ($lat) is lower than the current $cur — skipping, not downgrading" >&2
      continue
    fi
    printf 'catalog\tpnpm-workspace.yaml\t%s\t%s\t%s\n' "$pkg" "$cur" "$new"
    if [ "$apply" -eq 1 ]; then
      write_yaml_version "$yaml" catalog "$pkg" "$new"
      wrc=$?
      if [ "$wrc" -ne 0 ]; then return "$wrc"; fi
    fi
  done <<EOF
$(nja_yaml_entries "$yaml" catalog)
EOF
}

# ── surface 3: overrides ─────────────────────────────────────────────────────
# Highest declared range for a package across every workspace manifest.
# A manifest can declare the floor two ways: a concrete range directly, or
# (the common case in these repos) "catalog:" — a reference that must be
# resolved back to the catalog block's own concrete value. This is the
# literal dreamer @nestjs incident: every manifest said "catalog:", the real
# floor (^11.1.28) lived only in pnpm-workspace.yaml's catalog: block, and a
# declared_floor that stopped at "catalog:" found no floor and refused
# nothing. workspace: and npm: are still ignored — neither carries a
# comparable version.
declared_floor() {
  local root="$1" pkg="$2" yaml="$root/pnpm-workspace.yaml" ws manifest best="" r cat_val
  while IFS= read -r ws; do
    manifest="$root/$ws/package.json"
    [ "$ws" = "." ] && manifest="$root/package.json"
    [ -f "$manifest" ] || continue
    r="$(PKG="$pkg" node -e '
      const p = require(process.argv[1]);
      const v = (p.dependencies||{})[process.env.PKG] ?? (p.devDependencies||{})[process.env.PKG];
      if (v && !/^(workspace|npm):/.test(v)) console.log(v);
    ' "$manifest" 2>/dev/null)"
    [ -n "$r" ] || continue
    case "$r" in
      catalog:*)
        cat_val="$(nja_yaml_entries "$yaml" catalog | awk -F'\t' -v p="$pkg" '$1 == p { print $2; exit }')"
        [ -n "$cat_val" ] || continue
        r="$cat_val"
        ;;
    esac
    if [ -z "$best" ] || [ "$(semver_cmp "$r" "$best")" = "1" ]; then best="$r"; fi
  done <<EOF
$(nja_workspaces "$root")
EOF
  printf '%s\n' "$best"
}

sweep_overrides() {
  local root="$1" reject="$2" apply="$3"
  local yaml="$root/pnpm-workspace.yaml" pkg cur lat new floor wrc
  while IFS=$'\t' read -r pkg cur; do
    [ -n "$pkg" ] || continue
    is_rejected "$pkg" "$reject" && continue
    case "$cur" in catalog:*) continue ;; esac
    lat="$(latest_version "$pkg")" || continue
    [ -n "$lat" ] || continue
    new="$(reranged "$cur" "$lat")"
    [ "$new" = "$cur" ] && continue
    if [ "$(semver_cmp "$new" "$cur")" = "-1" ]; then
      nja_warn "override $pkg: latest ($lat) is lower than the current $cur — skipping, not downgrading" >&2
      continue
    fi

    floor="$(declared_floor "$root" "$pkg")"
    if [ -n "$floor" ] && [ "$(semver_cmp "$new" "$floor")" = "-1" ]; then
      nja_fail "override $pkg: $new would sit below the declared floor $floor — refusing"
      nja_say "        an override REPLACES declared ranges; a low one resolves under the floor silently."
      return 3
    fi

    printf 'overrides\tpnpm-workspace.yaml\t%s\t%s\t%s\n' "$pkg" "$cur" "$new"
    if [ "$apply" -eq 1 ]; then
      write_yaml_version "$yaml" overrides "$pkg" "$new"
      wrc=$?
      if [ "$wrc" -ne 0 ]; then return "$wrc"; fi
    fi
  done <<EOF
$(nja_yaml_entries "$yaml" overrides)
EOF
}

# ── report ───────────────────────────────────────────────────────────────────
# Rows are always collected from a DRY pass first: with --apply, ncu -u and the
# yaml writer have already rewritten the source, so a post-write read would
# report the new value in the FROM column.
rows="$(sweep_manifests "$ROOT" "$REJECT" 0)"
rows="$rows
$(sweep_catalog "$ROOT" "$REJECT" 0)"
cat_code=$?
if [ "$cat_code" -ne 0 ]; then exit 1; fi

ovr="$(sweep_overrides "$ROOT" "$REJECT" 0)"
ovr_code=$?
if [ "$ovr_code" -eq 3 ]; then exit 3; fi
if [ "$ovr_code" -ne 0 ]; then exit 1; fi
rows="$rows
$ovr"

rows="$(printf '%s\n' "$rows" | grep -v '^[[:space:]]*$' | awk '!seen[$0]++')"

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

  sweep_catalog "$ROOT" "$REJECT" 1 >/dev/null
  cat_code=$?
  if [ "$cat_code" -ne 0 ]; then exit 1; fi

  sweep_overrides "$ROOT" "$REJECT" 1 >/dev/null
  ovr_code=$?
  if [ "$ovr_code" -eq 3 ]; then exit 3; fi
  if [ "$ovr_code" -ne 0 ]; then exit 1; fi

  nja_say ""
  nja_ok "applied — now run ONE root install:"
  nja_say "      CI=true pnpm install --no-frozen-lockfile"
fi

exit 0
