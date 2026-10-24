#!/usr/bin/env bash
# SubagentStop hook: deterministic architecture gate for delegated work.
#
# Runs when a sub-agent finishes, and only on the files THAT sub-agent edited.
# When scripts/nja-lint.sh reports BLOCKING violations, it returns
# {"decision":"block","reason":...}; the reason reaches the sub-agent as its next
# instruction and it keeps working. The main-session Stop gate
# (hooks/architecture-gate.sh) is intentionally NOT registered.
#
# Files are taken from the Edit / Write / MultiEdit tool_use blocks in the
# sub-agent's own transcript (agent_transcript_path). Edits made through Bash
# (sed, heredocs, scripts) are NOT seen by this gate.
#
# Safety: inert outside nja projects; exits 0 when jq is missing, the
# transcript is unreadable, or anything else goes wrong. Kill switches:
# NJA_GATE_DISABLE=1, or `touch .claude/nja-gate-off` in the checkout.
# Loop guard: blocks at most 3 times per agent_id.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../scripts/nja-lint.sh"
MAX_BLOCKS=3

command -v jq >/dev/null 2>&1 || exit 0
# shellcheck source=../scripts/nja-detect.sh
. "$SCRIPT_DIR/../scripts/nja-detect.sh" 2>/dev/null || exit 0

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null)

[ -n "${NJA_GATE_DISABLE:-}" ] && exit 0
[ -f "$CWD/.claude/nja-gate-off" ] && exit 0
[ -f "$LINT" ] || exit 0
nja_is_project "$CWD" || exit 0
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# Loop guard: one counter per sub-agent.
SAFE_ID=$(printf '%s' "${AGENT_ID:-unknown}" | tr -c 'A-Za-z0-9_.-' '_')
COUNTER="${TMPDIR:-/tmp}"
COUNTER="${COUNTER%/}/nja-subagent-gate-$SAFE_ID"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
case "$COUNT" in '' | *[!0-9]*) COUNT=0 ;; esac
[ "$COUNT" -ge "$MAX_BLOCKS" ] && exit 0

# Unique edited file paths that still exist (bash 3.2: no mapfile).
files=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in /*) ;; *) p="$CWD/$p" ;; esac
  [ -f "$p" ] || continue
  files+=("${p#"$CWD"/}")   # relative to CWD for readable lint output
done < <(jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(type == "object" and .type == "tool_use"
             and (.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
    | .input.file_path // empty
  ' "$TRANSCRIPT" 2>/dev/null | awk '!seen[$0]++')

[ "${#files[@]}" -gt 0 ] || exit 0

OUT=$(cd "$CWD" && bash "$LINT" "${files[@]}" 2>/dev/null)
STATUS=$?
[ "$STATUS" -eq 2 ] || exit 0

COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$COUNTER" 2>/dev/null

REASON="ARCHITECTURE GATE: blocking violations in the files you edited (check $COUNT of $MAX_BLOCKS).

These are deterministic checks against the nja-architecture rules. Fix them before finishing:

$OUT

Next steps:
  - Invoke the nja-architecture skill and open the cited reference doc for each violation, then fix the code as that doc says.
  - Only for a genuine false positive, add a comment containing nja-lint-ignore on that line.
  - Then finish again; the gate re-runs on the files you edited."
jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
