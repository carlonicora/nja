#!/usr/bin/env bash
# Tests for nja/scripts/nja-linear.sh — sourced by nja/tests/run.sh.
#
# curl is replaced by fixtures/fake-linear/curl (first on PATH), which routes
# on the GraphQL operation name, replies with $FAKE_LINEAR_DIR/<Name>.json and
# records argv, bodies and the Authorization value it received. Nothing here
# reaches the real Linear API.
#
# Every variable and function carries the _lin_ prefix: suites are sourced
# into one shell.

_lin_script="$NJA_SCRIPTS_DIR/nja-linear.sh"
_lin_fakebin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/fake-linear"

# _lin_fixtures <dir> — the default canned responses.
_lin_fixtures() {
  local d="$1"
  printf '%s' '{"data":{"viewer":{"name":"Test User"}}}' > "$d/Viewer.json"
  printf '%s' '{"data":{"team":{"id":"team-1","key":"WYR","name":"Wyrdli"}}}' > "$d/Team.json"
  printf '%s' '{"data":{"teams":{"nodes":[{"id":"team-1","key":"WYR","name":"Wyrdli"},{"id":"team-2","key":"OPS","name":"Ops"}]}}}' > "$d/Teams.json"
  printf '%s' '{"data":{"team":{"states":{"nodes":[{"id":"s-todo","name":"Todo","type":"unstarted"},{"id":"s-prog","name":"In Progress","type":"started"},{"id":"s-review","name":"In Review","type":"started"}]}}}}' > "$d/TeamStates.json"
  printf '%s' '{"data":{"team":{"labels":{"nodes":[{"id":"l-bug","name":"Bug"},{"id":"l-small","name":"Small"}]}},"issueLabels":{"nodes":[{"id":"l-feat","name":"Feature"}]}}}' > "$d/Labels.json"
  printf '%s' '{"data":{"issueLabelCreate":{"success":true,"issueLabel":{"id":"l-new","name":"New"}}}}' > "$d/LabelCreate.json"
  printf '%s' '{"data":{"issueCreate":{"success":true,"issue":{"id":"i-1","identifier":"WYR-1","url":"https://linear.app/x/issue/WYR-1"}}}}' > "$d/IssueCreate.json"
  printf '%s' '{"data":{"issues":{"pageInfo":{"hasNextPage":false},"nodes":[{"identifier":"WYR-1","title":"One","priority":2,"priorityLabel":"High","createdAt":"2026-10-01T00:00:00.000Z","url":"https://linear.app/x/issue/WYR-1","state":{"name":"Todo"},"labels":{"nodes":[{"name":"Bug"},{"name":"Small"}]},"documents":{"nodes":[]}}]}}}' > "$d/OpenIssues.json"
  printf '%s' '{"data":{"issue":{"id":"i-1","identifier":"WYR-1","title":"One","description":"d","url":"https://linear.app/x/issue/WYR-1","state":{"name":"Todo"},"labels":{"nodes":[{"id":"l-bug","name":"Bug"}]},"documents":{"nodes":[{"id":"doc-spec","title":"Spec","content":"Source: a.md\n\nx"}]},"comments":{"nodes":[{"body":"hi","createdAt":"2026-10-02T00:00:00.000Z"}]}}}}' > "$d/Issue.json"
  printf '%s' '{"data":{"documentCreate":{"success":true,"document":{"id":"doc-new","url":"https://linear.app/x/document/new"}}}}' > "$d/DocumentCreate.json"
  printf '%s' '{"data":{"documentUpdate":{"success":true,"document":{"id":"doc-plan","url":"https://linear.app/x/document/plan"}}}}' > "$d/DocumentUpdate.json"
  printf '%s' '{"data":{"commentCreate":{"success":true,"comment":{"id":"c-1"}}}}' > "$d/CommentCreate.json"
  printf '%s' '{"data":{"fileUpload":{"success":true,"uploadFile":{"uploadUrl":"https://storage.example/put?sig=s1","assetUrl":"https://uploads.linear.app/a/b","headers":[{"key":"x-goog-meta-k","value":"v1"}]}}}}' > "$d/FileUpload.json"
  printf '%s' '{"data":{"issueUpdate":{"success":true,"issue":{"identifier":"WYR-1","state":{"name":"In Review"},"labels":{"nodes":[{"name":"Bug"},{"name":"Small"}]}}}}}' > "$d/IssueUpdate.json"
}

# _lin_setup [env-content] — fresh repo (with one commit) + fresh fake dir.
# Sets _lin_repo and _lin_fake. Pass "-" to create no .env at all.
_lin_setup() {
  local envc="${1:-LINEAR_API_KEY=lin_abc
LINEAR_TEAM_ID=team-1}"
  _lin_repo="$(cd "$(mktemp -d -t nja-linear-repo)" && pwd -P)"
  _lin_fake="$(cd "$(mktemp -d -t nja-linear-fake)" && pwd -P)"
  git -C "$_lin_repo" init -q
  printf '.env\n' > "$_lin_repo/.gitignore"
  git -C "$_lin_repo" add .gitignore >/dev/null 2>&1
  git -C "$_lin_repo" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
  [ "$envc" = "-" ] || printf '%s\n' "$envc" > "$_lin_repo/.env"
  _lin_fixtures "$_lin_fake"
}

# _lin_run <dir> <args...> — run the script in <dir>; sets _lin_out,
# _lin_err, _lin_code. LINEAR_* are scrubbed from the environment so a
# developer's shell cannot leak into a test.
_lin_run() {
  local dir="$1"; shift
  local o e; o="$(mktemp -t nja-linear-o)"; e="$(mktemp -t nja-linear-e)"
  ( cd "$dir" && env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
      PATH="$_lin_fakebin:$PATH" FAKE_LINEAR_DIR="$_lin_fake" \
      bash "$_lin_script" "$@" ) >"$o" 2>"$e"
  _lin_code=$?
  _lin_out="$(cat "$o")"; _lin_err="$(cat "$e")"
  rm -f "$o" "$e"
}

_lin_body() { grep -F "$1" "$_lin_fake/bodies.log" 2>/dev/null | tail -n 1; }
_lin_count() { local n; n="$(grep -cF "$1" "$_lin_fake/bodies.log" 2>/dev/null)"; printf '%s' "${n:-0}"; }

# _lin_bounded_exit <expected-exit> <label> <max-ticks-of-0.1s> -- <cmd...>
# Same guard as _ndb_bounded_exit in test-dev-boot.sh: a value-taking option
# with no value must exit, not spin the parser. Kills only the PID it started.
_lin_bounded_exit() {
  local expected="$1" label="$2" ticks="$3"; shift 4
  local out; out="$(mktemp -t nja-lin-out)"
  "$@" >"$out" 2>&1 &
  local pid=$!
  local n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt "$ticks" ]; do
    sleep 0.1
    n=$((n + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    t_fail "$label" "process pid $pid did not exit within $((ticks))00ms — killed it"
  else
    wait "$pid"
    local code=$?
    if [ "$code" -eq "$expected" ]; then t_pass "$label"
    else t_fail "$label" "expected exit $expected got $code: $(head -c 200 "$out")"; fi
  fi
  rm -f "$out"
}

# ── env_parsing ──────────────────────────────────────────────────────────────
t_case env_parsing
_lin_cr="$(printf '\r')"
for _lin_line in 'LINEAR_API_KEY=lin_abc' 'export LINEAR_API_KEY=lin_abc' \
    'LINEAR_API_KEY="lin_abc"' "LINEAR_API_KEY='lin_abc'" 'LINEAR_API_KEY=lin_abc  ' \
    "LINEAR_API_KEY=lin_abc$_lin_cr" 'LINEAR_API_KEY="lin_abc" # personal' \
    'LINEAR_API_KEY=lin_abc # personal' "LINEAR_API_KEY='lin_abc'  #c"; do
  _lin_setup "OTHER=1
$_lin_line"
  _lin_run "$_lin_repo" check
  t_assert_eq 0 "$_lin_code" "env_parsing: check exits 0 for [$(printf '%s' "$_lin_line" | tr '\r' '~')]"
  t_assert_eq "lin_abc" "$(tail -n 1 "$_lin_fake/auth.log" 2>/dev/null)" \
    "env_parsing: bare key sent for [$(printf '%s' "$_lin_line" | tr '\r' '~')]"
done

# A `#` inside quotes is part of the value.
_lin_setup 'LINEAR_API_KEY="lin#abc" # personal'
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "env_parsing: check exits 0 for a quoted key containing #"
t_assert_eq "lin#abc" "$(tail -n 1 "$_lin_fake/auth.log" 2>/dev/null)" "env_parsing: # inside quotes is kept"
# The same rules apply to LINEAR_TEAM_ID.
for _lin_line in 'LINEAR_TEAM_ID="team-1" # main' 'LINEAR_TEAM_ID=team-1 # main' "LINEAR_TEAM_ID='team-1'  #c"; do
  _lin_setup "LINEAR_API_KEY=lin_abc
$_lin_line"
  _lin_run "$_lin_repo" check
  t_assert_eq 0 "$_lin_code" "env_parsing: check exits 0 for [$_lin_line]"
  t_assert_eq "team-1" "$(_lin_body 'query Team(' | jq -r '.variables.id')" "env_parsing: team id parsed for [$_lin_line]"
done

# ── curlrc_ignored ───────────────────────────────────────────────────────────
t_case curlrc_ignored
_lin_setup
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "curlrc_ignored: check exits 0"
t_assert_eq "2" "$(wc -l < "$_lin_fake/argv.log" | tr -d ' ')" "curlrc_ignored: two curl calls recorded"
t_assert_eq "" "$(grep -v '^-q ' "$_lin_fake/argv.log")" "curlrc_ignored: every curl argv starts with -q"

# ── key_not_in_argv ──────────────────────────────────────────────────────────
t_case key_not_in_argv
_lin_setup
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "key_not_in_argv: check exits 0"
t_assert_not_contains "$(cat "$_lin_fake/argv.log" 2>/dev/null)" "lin_abc" "key_not_in_argv: key absent from curl argv"
t_assert_not_contains "$_lin_out" "lin_abc" "key_not_in_argv: key absent from stdout"
t_assert_not_contains "$_lin_err" "lin_abc" "key_not_in_argv: key absent from stderr"
t_assert_eq "{\"viewer\":\"Test User\",\"team\":{\"id\":\"team-1\",\"key\":\"WYR\",\"name\":\"Wyrdli\"},\"env\":\"$_lin_repo/.env\"}" "$_lin_out" \
  "check: prints viewer, team and the checkout's .env"

# ── worktree_fallback ────────────────────────────────────────────────────────
t_case worktree_fallback
_lin_setup "LINEAR_API_KEY=lin_main
LINEAR_TEAM_ID=team-1"
_lin_wt="$(cd "$(mktemp -d -t nja-linear-wt)" && pwd -P)/tree"
git -C "$_lin_repo" worktree add -q "$_lin_wt" >/dev/null 2>&1
t_assert_eq "no" "$([ -f "$_lin_wt/.env" ] && echo yes || echo no)" "worktree_fallback: worktree has no .env"
_lin_run "$_lin_wt" check
t_assert_eq 0 "$_lin_code" "worktree_fallback: check exits 0 inside the worktree"
t_assert_eq "lin_main" "$(tail -n 1 "$_lin_fake/auth.log" 2>/dev/null)" "worktree_fallback: main checkout's key used"
t_assert_eq "$_lin_repo/.env" "$(printf '%s' "$_lin_out" | jq -r '.env')" "worktree_fallback: check reports the main checkout's .env"

# ── missing_env ──────────────────────────────────────────────────────────────
t_case missing_env
_lin_setup -
_lin_run "$_lin_repo" check
t_assert_eq 2 "$_lin_code" "missing_env: exit 2"
t_assert_contains "$_lin_err" "$_lin_repo" "missing_env: stderr names the repo root"
t_assert_eq "" "$_lin_out" "missing_env: stdout empty"

# ── missing_key ──────────────────────────────────────────────────────────────
t_case missing_key
_lin_setup "LINEAR_TEAM_ID=team-1"
_lin_run "$_lin_repo" check
t_assert_eq 2 "$_lin_code" "missing_key: exit 2"
t_assert_contains "$_lin_err" "$_lin_repo/.env" "missing_key: stderr names the .env file"

# ── env_var_ignored ──────────────────────────────────────────────────────────
t_case env_var_ignored
_lin_setup -
_lin_o="$(mktemp -t nja-linear-o)"
( cd "$_lin_repo" && LINEAR_API_KEY=lin_env LINEAR_TEAM_ID=team-1 \
    PATH="$_lin_fakebin:$PATH" FAKE_LINEAR_DIR="$_lin_fake" bash "$_lin_script" check ) >"$_lin_o" 2>&1
_lin_code=$?
t_assert_eq 2 "$_lin_code" "env_var_ignored: exported LINEAR_API_KEY is not read (exit 2)"
t_assert_eq "no" "$([ -s "$_lin_fake/argv.log" ] && echo yes || echo no)" "env_var_ignored: no request sent"
rm -f "$_lin_o"

# ── no_repo ──────────────────────────────────────────────────────────────────
t_case no_repo
_lin_setup
_lin_norepo="$(cd "$(mktemp -d -t nja-linear-norepo)" && pwd -P)"
printf 'LINEAR_API_KEY=lin_abc\n' > "$_lin_norepo/.env"
_lin_run "$_lin_norepo" check
t_assert_eq 2 "$_lin_code" "no_repo: exit 2 outside a git repo"
t_assert_contains "$_lin_err" "$_lin_norepo" "no_repo: stderr names the directory"

# ── missing_team ─────────────────────────────────────────────────────────────
t_case missing_team
_lin_setup "LINEAR_API_KEY=lin_abc"
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "missing_team: check exits 0"
t_assert_eq "{\"viewer\":\"Test User\",\"team\":null,\"env\":\"$_lin_repo/.env\"}" "$_lin_out" "missing_team: team is null"
_lin_run "$_lin_repo" list-open
t_assert_eq 2 "$_lin_code" "missing_team: list-open exits 2"

# ── wrong_team ───────────────────────────────────────────────────────────────
t_case wrong_team
# Linear answers an unknown team id with a GraphQL error.
_lin_setup "LINEAR_API_KEY=lin_abc
LINEAR_TEAM_ID=team-gone"
printf '%s' '{"errors":[{"message":"Entity not found: Team"}],"data":null}' > "$_lin_fake/Team.json"
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "wrong_team: check exits 0"
t_assert_eq "Test User" "$(printf '%s' "$_lin_out" | jq -r '.viewer')" "wrong_team: viewer reported"
t_assert_eq "null" "$(printf '%s' "$_lin_out" | jq -c '.team')" "wrong_team: team is null"
t_assert_eq "$_lin_repo/.env" "$(printf '%s' "$_lin_out" | jq -r '.env')" "wrong_team: env reported"
t_assert_contains "$(printf '%s' "$_lin_out" | jq -r '.teamError')" "LINEAR_TEAM_ID" "wrong_team: teamError names LINEAR_TEAM_ID"
for _lin_cmd in list-open ensure-labels "get-issue WYR-1" "set-state WYR-1 Todo" "add-label WYR-1 Bug"; do
  # shellcheck disable=SC2086
  _lin_run "$_lin_repo" $_lin_cmd
  t_assert_eq 3 "$_lin_code" "wrong_team: $_lin_cmd exits 3"
  t_assert_eq "" "$_lin_out" "wrong_team: $_lin_cmd prints nothing on stdout"
  t_assert_contains "$_lin_err" "LINEAR_TEAM_ID" "wrong_team: $_lin_cmd stderr names LINEAR_TEAM_ID"
done
# Linear answers with a null team.
printf '%s' '{"data":{"team":null}}' > "$_lin_fake/Team.json"
_lin_run "$_lin_repo" check
t_assert_eq 0 "$_lin_code" "wrong_team: check exits 0 on a null team"
t_assert_contains "$(printf '%s' "$_lin_out" | jq -r '.teamError')" "LINEAR_TEAM_ID" "wrong_team: null team gives teamError"
_lin_run "$_lin_repo" list-open
t_assert_eq 3 "$_lin_code" "wrong_team: list-open exits 3 on a null team"
t_assert_eq "0" "$(_lin_count 'query OpenIssues')" "wrong_team: no OpenIssues request sent"

# ── teams ────────────────────────────────────────────────────────────────────
t_case teams
_lin_setup "LINEAR_API_KEY=lin_abc"
_lin_run "$_lin_repo" teams
t_assert_eq 0 "$_lin_code" "teams: exits 0 without a team id"
t_assert_eq '[{"id":"team-1","key":"WYR","name":"Wyrdli"},{"id":"team-2","key":"OPS","name":"Ops"}]' "$_lin_out" "teams: lists id/key/name"

# ── json_escaping ────────────────────────────────────────────────────────────
t_case json_escaping
_lin_setup
_lin_title='Fix "quoted" `tick` $HOME è —'
_lin_desc="$_lin_repo/desc.md"
printf '%s\n\nline two with "quotes" `ticks` $PATH\nè — end\n' "$_lin_title" > "$_lin_desc"
_lin_run "$_lin_repo" create-issue --title "$_lin_title" --description-file "$_lin_desc" --priority 3 --label Bug
t_assert_eq 0 "$_lin_code" "json_escaping: create-issue exits 0"
t_assert_eq '{"id":"i-1","identifier":"WYR-1","url":"https://linear.app/x/issue/WYR-1"}' "$_lin_out" "create-issue: prints id/identifier/url"
_lin_b="$(_lin_body 'mutation IssueCreate')"
t_assert_eq "$_lin_title" "$(printf '%s' "$_lin_b" | jq -j '.variables.input.title')" "json_escaping: title arrives byte-for-byte"
printf '%s' "$_lin_b" | jq -j '.variables.input.description' > "$_lin_repo/desc.out"
if cmp -s "$_lin_desc" "$_lin_repo/desc.out"; then t_pass "json_escaping: description arrives byte-for-byte"
else t_fail "json_escaping: description arrives byte-for-byte" "got: $(head -c 200 "$_lin_repo/desc.out")"; fi
t_assert_eq "s-todo" "$(printf '%s' "$_lin_b" | jq -r '.variables.input.stateId')" "create-issue: created in Todo"
t_assert_eq "3" "$(printf '%s' "$_lin_b" | jq -r '.variables.input.priority')" "create-issue: priority is a number"
t_assert_eq "team-1" "$(printf '%s' "$_lin_b" | jq -r '.variables.input.teamId')" "create-issue: team id sent"
t_assert_eq '["l-bug"]' "$(printf '%s' "$_lin_b" | jq -c '.variables.input.labelIds')" "create-issue: label resolved to id"
_lin_run "$_lin_repo" create-issue --title T --description-file "$_lin_desc" --priority 3 --label Nope
t_assert_eq 3 "$_lin_code" "create-issue: unknown label exits 3"

# ── identifier_case ──────────────────────────────────────────────────────────
t_case identifier_case
_lin_setup
_lin_run "$_lin_repo" get-issue wyr-12
t_assert_eq 0 "$_lin_code" "identifier_case: get-issue exits 0"
t_assert_eq "WYR-12" "$(_lin_body 'query Issue' | jq -r '.variables.id')" "identifier_case: WYR-12 sent"
t_assert_eq "Spec" "$(printf '%s' "$_lin_out" | jq -r '.documents[0].title')" "get-issue: documents flattened"
t_assert_eq "Bug" "$(printf '%s' "$_lin_out" | jq -r '.labels[0]')" "get-issue: labels are names"
t_assert_eq "Todo" "$(printf '%s' "$_lin_out" | jq -r '.state')" "get-issue: state is a name"
t_assert_eq "hi" "$(printf '%s' "$_lin_out" | jq -r '.comments[0].body')" "get-issue: comments flattened"

# ── unknown_state ────────────────────────────────────────────────────────────
t_case unknown_state
_lin_setup
_lin_run "$_lin_repo" set-state WYR-1 "Review"
t_assert_eq 3 "$_lin_code" "unknown_state: exit 3"
t_assert_contains "$_lin_err" "Todo" "unknown_state: lists Todo"
t_assert_contains "$_lin_err" "In Progress" "unknown_state: lists In Progress"
t_assert_contains "$_lin_err" "In Review" "unknown_state: lists In Review"
t_assert_eq "0" "$(_lin_count 'IssueUpdate')" "unknown_state: no IssueUpdate sent"
t_assert_eq "" "$_lin_out" "unknown_state: stdout empty"

# ── set_state_by_name ────────────────────────────────────────────────────────
t_case set_state_by_name
_lin_setup
_lin_run "$_lin_repo" set-state wyr-1 "In Review"
t_assert_eq 0 "$_lin_code" "set_state_by_name: exit 0"
t_assert_eq "s-review" "$(_lin_body 'mutation IssueUpdate' | jq -r '.variables.input.stateId')" "set_state_by_name: In Review's id sent"
t_assert_eq "WYR-1" "$(_lin_body 'mutation IssueUpdate' | jq -r '.variables.id')" "set_state_by_name: identifier upper-cased"
t_assert_eq '{"identifier":"WYR-1","state":"In Review"}' "$_lin_out" "set_state_by_name: prints identifier and state"

# ── labels_team_then_workspace ───────────────────────────────────────────────
t_case labels_team_then_workspace
_lin_setup
printf '%s' '{"data":{"team":{"labels":{"nodes":[{"id":"l-bug","name":"Bug"}]}},"issueLabels":{"nodes":[{"id":"l-feat","name":"Feature"}]}}}' > "$_lin_fake/Labels.json"
_lin_run "$_lin_repo" ensure-labels
t_assert_eq 0 "$_lin_code" "labels: ensure-labels exits 0"
t_assert_eq "3" "$(_lin_count 'mutation LabelCreate')" "labels: three LabelCreate calls"
t_assert_eq "Improvement Brainstorm Small" \
  "$(grep -F 'mutation LabelCreate' "$_lin_fake/bodies.log" | jq -r '.variables.input.name' | tr '\n' ' ' | sed 's/ $//')" \
  "labels: creates exactly Improvement, Brainstorm, Small"
t_assert_eq "team-1 team-1 team-1" \
  "$(grep -F 'mutation LabelCreate' "$_lin_fake/bodies.log" | jq -r '.variables.input.teamId' | tr '\n' ' ' | sed 's/ $//')" \
  "labels: each created on the team"
t_assert_eq "false" "$(printf '%s' "$_lin_out" | jq -r '.[] | select(.name=="Bug") | .created')" "labels: Bug reported existing"
t_assert_eq "l-feat" "$(printf '%s' "$_lin_out" | jq -r '.[] | select(.name=="Feature") | .id')" "labels: Feature found at workspace level"
t_assert_eq "false" "$(printf '%s' "$_lin_out" | jq -r '.[] | select(.name=="Feature") | .created')" "labels: Feature reported existing"
t_assert_eq "true" "$(printf '%s' "$_lin_out" | jq -r '.[] | select(.name=="Small") | .created')" "labels: Small reported created"
t_assert_eq "5" "$(printf '%s' "$_lin_out" | jq 'length')" "labels: five entries"

# ── upsert_updates ───────────────────────────────────────────────────────────
t_case upsert_updates
_lin_setup
printf 'Source: docs/plan.md\n\nbody "x" è\n' > "$_lin_repo/f"
printf '%s' '{"data":{"issue":{"id":"i-1","identifier":"WYR-1","title":"One","description":"d","url":"u","state":{"name":"Todo"},"labels":{"nodes":[]},"documents":{"nodes":[{"id":"doc-plan","title":"Plan","content":"old"}]},"comments":{"nodes":[]}}}}' > "$_lin_fake/Issue.json"
_lin_run "$_lin_repo" upsert-doc WYR-1 --title Plan --content-file f
t_assert_eq 0 "$_lin_code" "upsert_updates: exit 0 (update)"
t_assert_eq "1" "$(_lin_count 'mutation DocumentUpdate')" "upsert_updates: DocumentUpdate called"
t_assert_eq "0" "$(_lin_count 'mutation DocumentCreate')" "upsert_updates: DocumentCreate not called"
t_assert_eq "doc-plan" "$(_lin_body 'mutation DocumentUpdate' | jq -r '.variables.id')" "upsert_updates: the existing document is updated"
t_assert_eq "false" "$(printf '%s' "$_lin_out" | jq -r '.created')" "upsert_updates: created false"
_lin_setup
printf 'Source: docs/plan.md\n\nbody "x" è\n' > "$_lin_repo/f"
_lin_run "$_lin_repo" upsert-doc wyr-1 --title Plan --content-file f
t_assert_eq 0 "$_lin_code" "upsert_updates: exit 0 (create)"
t_assert_eq "1" "$(_lin_count 'mutation DocumentCreate')" "upsert_updates: DocumentCreate called when absent"
t_assert_eq "i-1" "$(_lin_body 'mutation DocumentCreate' | jq -r '.variables.input.issueId')" "upsert_updates: issueId set"
printf '%s' "$(_lin_body 'mutation DocumentCreate')" | jq -j '.variables.input.content' > "$_lin_repo/f.out"
if cmp -s "$_lin_repo/f" "$_lin_repo/f.out"; then t_pass "upsert_updates: content sent verbatim"
else t_fail "upsert_updates: content sent verbatim" "got: $(head -c 200 "$_lin_repo/f.out")"; fi
t_assert_eq "true" "$(printf '%s' "$_lin_out" | jq -r '.created')" "upsert_updates: created true"

# ── comment ──────────────────────────────────────────────────────────────────
t_case comment
_lin_setup
printf 'Cause: x\n' > "$_lin_repo/c.md"
_lin_run "$_lin_repo" comment wyr-1 --body-file c.md
t_assert_eq 0 "$_lin_code" "comment: exit 0"
t_assert_eq '{"id":"c-1"}' "$_lin_out" "comment: prints id"
t_assert_eq "Cause: x
x" "$(_lin_body 'mutation CommentCreate' | jq -j '.variables.input.body'; printf x)" "comment: body sent verbatim"
t_assert_eq "i-1" "$(_lin_body 'mutation CommentCreate' | jq -r '.variables.input.issueId')" "comment: issue id resolved"

# ── add_label_keeps_existing ─────────────────────────────────────────────────
t_case add_label_keeps_existing
_lin_setup
_lin_run "$_lin_repo" add-label wyr-1 Small
t_assert_eq 0 "$_lin_code" "add_label: exit 0"
t_assert_eq '["l-bug","l-small"]' "$(_lin_body 'mutation IssueUpdate' | jq -c '.variables.input.labelIds | sort')" \
  "add_label: IssueUpdate carries existing Bug plus Small"
t_assert_eq "WYR-1" "$(_lin_body 'mutation IssueUpdate' | jq -r '.variables.id')" "add_label: identifier upper-cased"
t_assert_eq '{"identifier":"WYR-1","labels":["Bug","Small"]}' "$_lin_out" "add_label: prints identifier and label names"
_lin_setup
_lin_run "$_lin_repo" add-label WYR-1 Feature
t_assert_eq '["l-bug","l-feat"]' "$(_lin_body 'mutation IssueUpdate' | jq -c '.variables.input.labelIds | sort')" \
  "add_label: workspace label resolved"

# ── add_label_unknown ────────────────────────────────────────────────────────
t_case add_label_unknown
_lin_setup
_lin_run "$_lin_repo" add-label WYR-1 Nope
t_assert_eq 3 "$_lin_code" "add_label_unknown: exit 3"
t_assert_contains "$_lin_err" "Small" "add_label_unknown: lists available names"
t_assert_eq "0" "$(_lin_count 'IssueUpdate')" "add_label_unknown: no IssueUpdate sent"
t_assert_eq "" "$_lin_out" "add_label_unknown: stdout empty"

# ── remove_label_keeps_others ────────────────────────────────────────────────
t_case remove_label_keeps_others
_lin_setup
printf '%s' '{"data":{"issue":{"id":"i-1","identifier":"WYR-1","title":"One","description":"d","url":"u","state":{"name":"Todo"},"labels":{"nodes":[{"id":"l-bug","name":"Bug"},{"id":"l-small","name":"Small"}]},"documents":{"nodes":[]},"comments":{"nodes":[]}}}}' > "$_lin_fake/Issue.json"
printf '%s' '{"data":{"issueUpdate":{"success":true,"issue":{"identifier":"WYR-1","state":{"name":"Todo"},"labels":{"nodes":[{"name":"Bug"}]}}}}}' > "$_lin_fake/IssueUpdate.json"
_lin_run "$_lin_repo" remove-label wyr-1 Small
t_assert_eq 0 "$_lin_code" "remove_label: exit 0"
t_assert_eq '["l-bug"]' "$(_lin_body 'mutation IssueUpdate' | jq -c '.variables.input.labelIds')" "remove_label: keeps Bug, drops Small"
t_assert_eq '{"identifier":"WYR-1","labels":["Bug"]}' "$_lin_out" "remove_label: prints identifier and remaining labels"
_lin_setup
_lin_run "$_lin_repo" remove-label WYR-1 Small
t_assert_eq 0 "$_lin_code" "remove_label: label not on issue is a no-op (exit 0)"
t_assert_eq "0" "$(_lin_count 'IssueUpdate')" "remove_label: no-op sends no IssueUpdate"
t_assert_eq '{"identifier":"WYR-1","labels":["Bug"]}' "$_lin_out" "remove_label: no-op prints current labels"
_lin_run "$_lin_repo" remove-label WYR-1 Nope
t_assert_eq 3 "$_lin_code" "remove_label: unknown label name exits 3"
t_assert_eq "0" "$(_lin_count 'IssueUpdate')" "remove_label: unknown label sends no IssueUpdate"

# ── attach_image ─────────────────────────────────────────────────────────────
t_case attach_image
_lin_setup
printf '\211PNG fake bytes' > "$_lin_repo/shot.png"
_lin_run "$_lin_repo" attach-image wyr-1 --file shot.png --alt "Reply [no links]"
t_assert_eq 0 "$_lin_code" "attach_image: exit 0"
t_assert_eq '{"identifier":"WYR-1","assetUrl":"https://uploads.linear.app/a/b"}' "$_lin_out" "attach_image: prints identifier and asset url"
_lin_b="$(_lin_body 'mutation FileUpload')"
t_assert_eq "image/png" "$(printf '%s' "$_lin_b" | jq -r '.variables.contentType')" "attach_image: content type from extension"
t_assert_eq "shot.png" "$(printf '%s' "$_lin_b" | jq -r '.variables.filename')" "attach_image: filename sent"
t_assert_eq "$(wc -c < "$_lin_repo/shot.png" | tr -d ' ')" "$(printf '%s' "$_lin_b" | jq -r '.variables.size')" "attach_image: size sent as bytes"
if cmp -s "$_lin_repo/shot.png" "$_lin_fake/uploaded.bin"; then t_pass "attach_image: file uploaded byte-for-byte"
else t_fail "attach_image: file uploaded byte-for-byte" "uploaded.bin differs"; fi
_lin_up="$(cat "$_lin_fake/uploads.log" 2>/dev/null)"
t_assert_contains "$_lin_up" "https://storage.example/put?sig=s1" "attach_image: PUT to the signed url"
t_assert_contains "$_lin_up" "x-goog-meta-k: v1" "attach_image: signed headers forwarded"
t_assert_contains "$_lin_up" "Content-Type: image/png" "attach_image: content type header on the PUT"
t_assert_not_contains "$_lin_up" "lin_abc" "attach_image: key never sent to storage"
t_assert_not_contains "$(cat "$_lin_fake/argv.log")" "sig=s1" "attach_image: signed url absent from curl argv"
t_assert_eq "d

![Reply  no links ](https://uploads.linear.app/a/b)
x" "$(_lin_body 'mutation IssueUpdate' | jq -j '.variables.input.description'; printf x)" "attach_image: image appended to the description"
_lin_setup
printf 'x' > "$_lin_repo/shot.JPG"
printf '403\n' > "$_lin_fake/upload.status"
_lin_run "$_lin_repo" attach-image WYR-1 --file shot.JPG
t_assert_eq 3 "$_lin_code" "attach_image: storage error exits 3"
t_assert_eq "image/jpeg" "$(_lin_body 'mutation FileUpload' | jq -r '.variables.contentType')" "attach_image: upper-case .JPG is jpeg"
t_assert_eq "0" "$(_lin_count 'IssueUpdate')" "attach_image: failed upload leaves the description alone"
t_assert_eq "" "$_lin_out" "attach_image: stdout empty on failure"
_lin_setup
printf 'x' > "$_lin_repo/notes.txt"
_lin_run "$_lin_repo" attach-image WYR-1 --file notes.txt
t_assert_eq 1 "$_lin_code" "attach_image: non-image extension exits 1"
_lin_run "$_lin_repo" attach-image WYR-1
t_assert_eq 1 "$_lin_code" "attach_image: missing --file exits 1"
t_assert_eq "no" "$([ -s "$_lin_fake/argv.log" ] && echo yes || echo no)" "attach_image: no request sent for usage errors"

# ── list_open ────────────────────────────────────────────────────────────────
t_case list_open
_lin_setup
_lin_run "$_lin_repo" list-open
t_assert_eq 0 "$_lin_code" "list_open: exit 0"
t_assert_eq '[{"identifier":"WYR-1","title":"One","priority":2,"priorityLabel":"High","state":"Todo","labels":["Bug","Small"],"documents":[],"createdAt":"2026-10-01T00:00:00.000Z","url":"https://linear.app/x/issue/WYR-1"}]' \
  "$_lin_out" "list_open: flattened rows"

# ── http_error ───────────────────────────────────────────────────────────────
t_case http_error
_lin_setup
printf '401\n' > "$_lin_fake/Viewer.status"
_lin_run "$_lin_repo" check
t_assert_eq 3 "$_lin_code" "http_error: 401 exits 3"
t_assert_eq "" "$_lin_out" "http_error: stdout empty"
t_assert_contains "$_lin_err" "401" "http_error: stderr names the status"

# ── graphql_error ────────────────────────────────────────────────────────────
t_case graphql_error
_lin_setup
printf '%s' '{"errors":[{"message":"boom"}]}' > "$_lin_fake/Viewer.json"
_lin_run "$_lin_repo" check
t_assert_eq 3 "$_lin_code" "graphql_error: exits 3"
t_assert_contains "$_lin_err" "boom" "graphql_error: stderr carries the message"
t_assert_eq "" "$_lin_out" "graphql_error: stdout empty"

# ── too_many_open ────────────────────────────────────────────────────────────
t_case too_many_open
_lin_setup
printf '%s' '{"data":{"issues":{"pageInfo":{"hasNextPage":true},"nodes":[]}}}' > "$_lin_fake/OpenIssues.json"
_lin_run "$_lin_repo" list-open
t_assert_eq 3 "$_lin_code" "too_many_open: exits 3"
t_assert_eq "" "$_lin_out" "too_many_open: stdout empty"

# ── usage ────────────────────────────────────────────────────────────────────
t_case usage
_lin_setup
_lin_run "$_lin_repo"
t_assert_eq 1 "$_lin_code" "usage: no command exits 1"
_lin_run "$_lin_repo" frobnicate
t_assert_eq 1 "$_lin_code" "usage: unknown command exits 1"
_lin_run "$_lin_repo" create-issue --description-file x --priority 3 --label Bug
t_assert_eq 1 "$_lin_code" "usage: create-issue without --title exits 1"
_lin_bounded_exit 1 "usage: trailing --title with no value exits 1, not a hang" 30 -- \
  bash -c 'cd "$1" && PATH="$2:$PATH" FAKE_LINEAR_DIR="$3" bash "$4" create-issue --title' _ \
  "$_lin_repo" "$_lin_fakebin" "$_lin_fake" "$_lin_script"
_lin_bounded_exit 1 "usage: trailing --label with no value exits 1, not a hang" 30 -- \
  bash -c 'cd "$1" && PATH="$2:$PATH" FAKE_LINEAR_DIR="$3" bash "$4" create-issue --title T --label' _ \
  "$_lin_repo" "$_lin_fakebin" "$_lin_fake" "$_lin_script"
_lin_bounded_exit 1 "usage: trailing --content-file with no value exits 1, not a hang" 30 -- \
  bash -c 'cd "$1" && PATH="$2:$PATH" FAKE_LINEAR_DIR="$3" bash "$4" upsert-doc WYR-1 --title Plan --content-file' _ \
  "$_lin_repo" "$_lin_fakebin" "$_lin_fake" "$_lin_script"
_lin_run "$_lin_repo" create-issue --title T --description-file "$_lin_repo/nope.md" --priority 3 --label Bug
t_assert_eq 1 "$_lin_code" "usage: unreadable --description-file exits 1"
_lin_run "$_lin_repo" create-issue --title T --description-file "$_lin_repo/.gitignore" --priority 9 --label Bug
t_assert_eq 1 "$_lin_code" "usage: priority outside 0-4 exits 1"
_lin_run "$_lin_repo" get-issue
t_assert_eq 1 "$_lin_code" "usage: get-issue without an id exits 1"
_lin_run "$_lin_repo" get-issue "not an id"
t_assert_eq 1 "$_lin_code" "usage: malformed identifier exits 1"
t_assert_eq "no" "$([ -s "$_lin_fake/argv.log" ] && echo yes || echo no)" "usage: no request sent for usage errors"
