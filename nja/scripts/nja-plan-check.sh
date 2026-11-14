#!/usr/bin/env bash
# nja-plan-check.sh — the mechanical half of a plan audit, at zero model cost.
#
#   nja-plan-check.sh <plan.md> [repo-root]
#
# Checks what a script can decide for certain, so the auditors spend their
# reading on what only a reader can judge:
#   - the nja execution header is present; no REQUIRED SUB-SKILL line, no
#     "task-by-task", no execution menu;
#   - no git add / commit / push / stash / branch / worktree step, no Commit
#     step, no "frequent commits";
#   - every file listed under a task's **Files:** carries a Create, Modify or
#     Delete marker; every Modify / Delete path exists under the repo root;
#     every Create path does not exist yet (Create on an existing file would
#     overwrite it);
#   - the plan names a spec review;
#   - when the repo has an e2e suite (scripts/e2e.sh and
#     apps/web/tests/README.md), whether a task heading mentions e2e. Whether
#     the spec needs one is a judgment, so this is reported as CHECK, never
#     BLOCKING.
#
# Paths named only inside step text are not checked here; the task auditors
# check those.
#
# repo-root defaults to the git top level of the plan's directory.
#
# Output: one line per finding, "BLOCKING <plan>:<line> <rule>: <message>" or
# "CHECK <plan>:<line> <rule>: <message>", then a summary line.
# Exit: 0 no BLOCKING finding, 1 at least one, 2 usage error.

set -uo pipefail

plan="${1:-}"
if [ -z "$plan" ] || [ ! -f "$plan" ]; then
  printf 'usage: nja-plan-check.sh <plan.md> [repo-root]\n' >&2
  exit 2
fi
root="${2:-}"
if [ -z "$root" ]; then
  root="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$root" ] || [ ! -d "$root" ]; then
  printf 'nja-plan-check: no repo root (pass it as the second argument)\n' >&2
  exit 2
fi

name="$(basename "$plan")"
blocking=0
checked_modify=0
checked_create=0

block() { blocking=$((blocking + 1)); printf 'BLOCKING %s:%s %s: %s\n' "$name" "$1" "$2" "$3"; }
check() { printf 'CHECK %s:%s %s: %s\n' "$name" "$1" "$2" "$3"; }

# ── execution contract ───────────────────────────────────────────────────

header_re='^> \*\*For agentic workers:\*\* Execute this plan only through the execution protocol'
if ! grep -qE "$header_re" "$plan"; then
  block 1 nja-header "no nja 'For agentic workers' header (nja-writing-plan step 10a)"
fi

while IFS=: read -r ln _; do
  block "$ln" required-sub-skill "names a REQUIRED SUB-SKILL (nja-writing-plan step 10a)"
done < <(grep -n 'REQUIRED SUB-SKILL' "$plan")

while IFS=: read -r ln _; do
  block "$ln" task-by-task "tells the executor to run the plan task-by-task"
done < <(grep -niE 'task[- ]by[- ]task' "$plan" | grep -v 'For agentic workers')

while IFS=: read -r ln _; do
  block "$ln" execution-menu "offers an execution-method choice (nja-writing-plan step 10c)"
done < <(grep -niE 'subagent-driven \(recommended\)|inline execution|two execution options' "$plan")

# git steps. Lines that forbid git ("NO `git commit`", "never commit") are not steps.
while IFS=: read -r ln _; do
  block "$ln" git-step "runs a git write command (nja-writing-plan step 9)"
done < <(grep -nE 'git (add|commit|push|stash|worktree)|git checkout -b|git switch -c|git branch [^-]' "$plan" \
  | grep -v 'For agentic workers' \
  | grep -viE '\bno\b|never|\bnot\b|don.t|forbid')

while IFS=: read -r ln _; do
  block "$ln" commit-step "a Commit step (nja-writing-plan step 10b)"
done < <(grep -nE '^[[:space:]]*(- \[[ xX]\] )?\*\*Step [0-9]+[^*]*\b[Cc]ommit|^#+ .*\b[Cc]ommit\b' "$plan" \
  | grep -viE '\bno\b|never|\bnot\b')

while IFS=: read -r ln _; do
  block "$ln" frequent-commits "says \"frequent commits\" (nja-writing-plan step 10b)"
done < <(grep -niE 'frequent commits' "$plan" | grep -viE '\bno\b|never|\bnot\b')

if ! grep -qiE 'spec review' "$plan"; then
  block 1 spec-review "no spec review in the plan (nja-writing-plan step 7f)"
fi

# ── Files blocks carry markers ───────────────────────────────────────────

while IFS=$'\t' read -r ln msg; do
  [ -n "$ln" ] && block "$ln" file-markers "$msg"
done < <(awk '
  function close_block() {
    if (inb && bullets && !markers && !none) printf "%d\t**Files:** lists files with no Create, Modify or Delete marker\n", start
    inb = 0
  }
  /^\*\*Files:\*\*/ {
    close_block()
    inb = 1; start = NR; bullets = 0; markers = 0
    none = ($0 ~ /[Nn]one/)
    rest = $0; sub(/^\*\*Files:\*\*/, "", rest)
    if (rest ~ /`/ && rest !~ /(Create|Modify|Delete)[[:space:]]*:/ && !none) printf "%d\t**Files:** names files inline with no Create, Modify or Delete marker\n", NR
    next
  }
  inb {
    if ($0 ~ /^#/) { close_block(); next }
    if ($0 ~ /^[[:space:]]*[-*][[:space:]]/) {
      bullets = 1
      if ($0 ~ /^[[:space:]]*[-*][[:space:]]+(Create|Modify|Delete)[[:space:]]*:/) markers = 1
      else if ($0 ~ /^[[:space:]]*[-*][[:space:]]+[A-Za-z ]+:[[:space:]]*`/) printf "%d\tfile listed under \"%s\" instead of Create, Modify or Delete\n", NR, substr($0, index($0, $2), index($0, ":") - index($0, $2))
      next
    }
    if ($0 ~ /^[[:space:]]*$/) { if (bullets) close_block(); next }
    if (bullets) close_block(); else inb = 0
  }
  END { close_block() }
' "$plan")

# ── listed paths match the repo ──────────────────────────────────────────
#
# A bare file name on a marker line (`npc.put.dto.ts` after
# `apps/.../dtos/npc.post.dto.ts`) resolves against the directory of the
# last full path on the same line.

ext='(ts|tsx|js|jsx|mjs|cjs|json|md|mdx|css|scss|yaml|yml|sh|gz|sql|cypher|txt|html|svg|png|jpg|webp)'
while IFS=$'\t' read -r ln marker path; do
  [ -n "$ln" ] || continue
  case "$marker" in
    Modify|Delete)
      checked_modify=$((checked_modify + 1))
      [ -e "$root/$path" ] || block "$ln" missing-path "$marker \`$path\` does not exist under $root"
      ;;
    Create)
      checked_create=$((checked_create + 1))
      [ -e "$root/$path" ] && block "$ln" create-exists "Create \`$path\` already exists; Create would overwrite it (Modify, and keep what is there)"
      ;;
  esac
done < <(awk -v ext="$ext" '
  /^[[:space:]]*[-*][[:space:]]+(Create|Modify|Delete)[[:space:]]*:/ {
    m = $0; sub(/^[[:space:]]*[-*][[:space:]]+/, "", m); sub(/[[:space:]]*:.*/, "", m)
    line = $0; last = ""
    while (match(line, /`[^`]+`/)) {
      tok = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
      sub(/:[0-9][0-9,-]*$/, "", tok)
      if (tok ~ /[ *<>{}$?=:\[\]()]/) continue
      if (tok ~ /^\.\.?\//) continue
      if (tok ~ /\//) {
        # a token with no file extension is a directory
        if (tok !~ ("\\." ext "$")) { last = tok; sub(/\/?$/, "/", last); continue }
        last = tok
        printf "%d\t%s\t%s\n", NR, m, tok
      } else if (tok ~ ("^[A-Za-z0-9_.@-]+\\." ext "$") && last != "") {
        d = last; sub(/\/[^\/]*$/, "", d)
        printf "%d\t%s\t%s/%s\n", NR, m, d, tok
      }
    }
  }
' "$plan")

# ── e2e task (judgment, reported only) ───────────────────────────────────

if [ -f "$root/scripts/e2e.sh" ] && [ -f "$root/apps/web/tests/README.md" ]; then
  if ! grep -qiE '^#+ .*(e2e|end-to-end)' "$plan"; then
    check 1 e2e-task "the repo has an e2e suite and no heading mentions e2e; an auditor judges whether the spec changes a page (nja-writing-plan step 11)"
  fi
fi

printf 'plan-check: %d BLOCKING; %d Modify/Delete and %d Create paths checked under %s\n' \
  "$blocking" "$checked_modify" "$checked_create" "$root"
[ "$blocking" -eq 0 ]
