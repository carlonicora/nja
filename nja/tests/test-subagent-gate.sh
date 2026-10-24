# Suite for hooks/subagent-architecture-gate.sh (SubagentStop). Sourced by run.sh.
GATE="$NJA_SCRIPTS_DIR/../hooks/subagent-architecture-gate.sh"

sg_repo="$(t_mkrepo)"
sg_tmp="$(cd "$(mktemp -d -t nja-sg-tmp)" && pwd -P)"
sg_exc="$(cd "$(mktemp -d -t nja-sg-exc)" && pwd -P)"
export NJA_LINT_EXCEPTIONS_DIR="$sg_exc"
mkdir -p "$sg_repo/apps/api/src/features/report/repositories"
sg_bad="$sg_repo/apps/api/src/features/report/repositories/report.repository.ts"
sg_good="$sg_repo/apps/api/src/features/report/repositories/clean.repository.ts"
printf 'export class R { a() { return result.records; } }\n' > "$sg_bad"
printf 'export class C {}\n' > "$sg_good"

# sg_transcript <path> <file...>: a jsonl with one Edit tool_use per file,
# plus a Bash tool_use and a user line that must be ignored.
sg_transcript() {
  local out="$1" f; shift
  : > "$out"
  printf '{"type":"user","message":{"content":"go"}}\n' >> "$out"
  for f in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"x"},{"type":"tool_use","name":"Edit","input":{"file_path":"%s","old_string":"a","new_string":"b"}}]}}\n' "$f" >> "$out"
  done
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' >> "$out"
}

# sg_run <agent_id> <transcript>: run the gate with a SubagentStop payload.
sg_run() {
  printf '{"cwd":"%s","agent_id":"%s","agent_type":"","agent_transcript_path":"%s","stop_hook_active":false}' \
    "$sg_repo" "$1" "$2" | TMPDIR="$sg_tmp" bash "$GATE" 2>&1
}

# violation -> block JSON
sg_transcript "$sg_tmp/bad.jsonl" "$sg_bad" "$sg_good" "$sg_bad" "$sg_repo/missing.ts"
sg_out="$(sg_run agent-bad "$sg_tmp/bad.jsonl")"
t_assert_contains "$sg_out" '"decision": "block"' "a violation blocks"
t_assert_contains "$sg_out" "raw-neo4j-records" "the reason carries the lint output"
t_assert_contains "$sg_out" "nja-lint-ignore" "the reason explains the false-positive escape"
t_assert_contains "$sg_out" "2 file(s)" "only unique, existing edited files are linted"

# clean file -> no output, exit 0
sg_transcript "$sg_tmp/good.jsonl" "$sg_good"
sg_out="$(sg_run agent-good "$sg_tmp/good.jsonl")"; sg_code=$?
t_assert_eq "" "$sg_out" "a clean edit prints nothing"
t_assert_eq "0" "$sg_code" "a clean edit exits 0"

# no edits -> exit 0, no output
sg_transcript "$sg_tmp/none.jsonl"
sg_out="$(sg_run agent-none "$sg_tmp/none.jsonl")"; sg_code=$?
t_assert_eq "" "$sg_out" "no edits prints nothing"
t_assert_eq "0" "$sg_code" "no edits exits 0"

# loop guard: at most 3 blocks per agent
sg_n=0
for sg_i in 1 2 3 4; do
  sg_out="$(sg_run agent-loop "$sg_tmp/bad.jsonl")"
  case "$sg_out" in *'"block"'*) sg_n=$((sg_n + 1)) ;; esac
done
t_assert_eq "3" "$sg_n" "blocks at most 3 times per agent"
t_assert_eq "" "$(sg_run agent-loop "$sg_tmp/bad.jsonl")" "after the cap the gate is silent"

# kill switches
sg_out="$(NJA_GATE_DISABLE=1 sg_run agent-kill "$sg_tmp/bad.jsonl")"
t_assert_eq "" "$sg_out" "NJA_GATE_DISABLE=1 silences the gate"
mkdir -p "$sg_repo/.claude" && touch "$sg_repo/.claude/nja-gate-off"
t_assert_eq "" "$(sg_run agent-kill2 "$sg_tmp/bad.jsonl")" ".claude/nja-gate-off silences the gate"
rm -f "$sg_repo/.claude/nja-gate-off"

# unreadable transcript and non-nja project stay inert
t_assert_eq "" "$(sg_run agent-x "$sg_tmp/does-not-exist.jsonl")" "an unreadable transcript is inert"
sg_plain="$(cd "$(mktemp -d -t nja-sg-plain)" && pwd -P)"
sg_out="$(printf '{"cwd":"%s","agent_id":"p","agent_transcript_path":"%s"}' "$sg_plain" "$sg_tmp/bad.jsonl" | TMPDIR="$sg_tmp" bash "$GATE" 2>&1)"
t_assert_eq "" "$sg_out" "a non-nja project is inert"

unset NJA_LINT_EXCEPTIONS_DIR
rm -rf "$sg_repo" "$sg_tmp" "$sg_exc" "$sg_plain"
