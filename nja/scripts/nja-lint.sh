#!/usr/bin/env bash
# nja-lint — deterministic architecture checker for nestjs-neo4jsonapi + nextjs-jsonapi.
#
# Scans TypeScript/TSX files for the greppable anti-patterns catalogued in
# skills/nja-architecture/references/anti-patterns.md. This is the mechanical
# half of architecture enforcement — it catches what regex can catch with high
# confidence, so the skill/audit can focus on judgment calls.
#
# Usage:
#   nja-lint.sh [file ...]   # check the given files
#   nja-lint.sh              # check files reported by `git status --porcelain`
#
# Exit code:
#   2  at least one BLOCKING violation   (used by the Stop gate to block)
#   0  no blocking violations (warnings allowed)
#
# Escape hatch: add a comment containing `nja-lint-ignore` on a line to skip it.
set -uo pipefail

BLOCKING=0
WARNINGS=0

# ── collect files ────────────────────────────────────────────────────────────
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line:3}"                              # strip the XY status prefix
    case "$path" in *" -> "*) path="${path##* -> }";; esac   # rename → new path
    files+=("$path")
  done < <(git status --porcelain | grep -vE '^ ?D ')        # ignore deletions
fi

# ── reporting ────────────────────────────────────────────────────────────────
report() { # file line severity rule message doc
  printf '%s:%s [%s] %s — %s\n        → %s\n' "$1" "$2" "$3" "$4" "$5" "$6"
  if [ "$3" = "BLOCKING" ]; then BLOCKING=$((BLOCKING + 1)); else WARNINGS=$((WARNINGS + 1)); fi
}

# grep helper: "line:content" for matches, minus suppressed lines
scan() { grep -nE "$1" "$2" 2>/dev/null | grep -v 'nja-lint-ignore'; }

flag() { # file pattern severity rule message doc
  local f="$1" pat="$2" sev="$3" rule="$4" msg="$5" doc="$6" ln
  while IFS=: read -r ln _; do
    [ -n "$ln" ] && report "$f" "$ln" "$sev" "$rule" "$msg" "$doc"
  done < <(scan "$pat" "$f")
}

# ── per-file checks ──────────────────────────────────────────────────────────
check_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  case "$f" in
    *.ts | *.tsx) ;;
    *) return 0 ;;
  esac
  case "$f" in
    *node_modules/* | */dist/* | */.next/* | *.test.ts | *.test.tsx | *.spec.ts | *.spec.tsx) return 0 ;;
  esac

  # ── BLOCKING: patterns that are never correct in feature code ──────────────

  case "$f" in
  *apps/web/*)
    flag "$f" '\bfetch\s*\(' BLOCKING fetch-in-frontend \
      "Use callApi(), never fetch() directly" "references/frontend/03-services.md"
    flag "$f" '\basChild\b' BLOCKING radix-aschild \
      "Base UI: use the render prop, never asChild" "references/frontend/04-components.md"
    ;;
  esac

  case "$f" in
  *apps/api/src/features/*)
    flag "$f" '\.records\[|result\.records' BLOCKING raw-neo4j-records \
      "Return typed objects via readOne()/readMany(), never raw result.records" "references/backend/03-repositories.md"
    flag "$f" '\bSKIP\b[[:space:]]+(\$|\{|[0-9])' BLOCKING manual-pagination \
      "Use the {CURSOR} placeholder, never manual SKIP/LIMIT" "references/backend/03-repositories.md"
    ;;
  esac

  flag "$f" '@radix-ui/' BLOCKING radix-import \
    "This project uses Base UI, not Radix" "references/frontend/04-components.md"

  case "$f" in
  *.controller.ts)
    flag "$f" '(^|[[:space:]])import.*Repository|from.*\.repository' BLOCKING controller-imports-repository \
      "Controllers call services, never repositories directly" "references/backend/05-controllers.md"
    ;;
  esac

  # ── WARN: heuristics that are usually wrong but need a human/judgment look ──

  flag "$f" 'overridesJsonApiCreation' WARN overrides-jsonapi \
    "overridesJsonApiCreation is only valid alongside a dedicated model method" "references/anti-patterns.md"

  case "$f" in
  *apps/web/*)
    flag "$f" '\.data\.attributes\b|\.jsonApi\.data\b' WARN direct-jsonapi-access \
      "Use typed getters after rehydrate(), not raw .data.attributes / .jsonApi.data" "references/frontend/01-models.md"
    ;;
  esac

  case "$f" in
  *.dto.ts)
    # @IsString() decorator on the line above a date-ish property
    local ln
    while IFS= read -r ln; do
      [ -n "$ln" ] && report "$f" "$ln" WARN dto-isstring-on-date \
        "Date/datetime DTO attributes must use @IsDateString(), not @IsString()" "references/date-handling.md"
    done < <(awk '
      prev ~ /@IsString\(\)/ && $0 ~ /(_at|_date|[Dd]ate|[Dd]atetime)[[:space:]]*[?:]/ && $0 !~ /nja-lint-ignore/ { print prevno }
      { prev = $0; prevno = NR }
    ' "$f")
    ;;
  esac
}

for f in "${files[@]:-}"; do
  [ -n "$f" ] && check_file "$f"
done

echo ""
echo "nja-lint: ${BLOCKING} blocking, ${WARNINGS} warning(s) across ${#files[@]} file(s)"
[ "$BLOCKING" -gt 0 ] && exit 2
exit 0
