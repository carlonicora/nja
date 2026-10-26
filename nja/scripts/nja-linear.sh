#!/usr/bin/env bash
# nja-linear — the only code in the nja plugin that talks to Linear. Skills
# call it; they never write GraphQL or curl themselves. Every command prints
# one JSON value on stdout; errors are one sentence on stderr, nothing on
# stdout.
#
# Configuration comes ONLY from the repo's root .env:
#   LINEAR_API_KEY   personal API key for this repo's workspace (Carlo, by hand)
#   LINEAR_TEAM_ID   team issues live in (written by nja-linear-setup)
# The .env is read from `git rev-parse --show-toplevel`, else — in a worktree,
# which has no .env of its own — from the main checkout. The process
# environment is never read for these two variables and no other directory is
# ever searched: a key leaking across repos would write to the wrong
# workspace. The key never appears in curl's argv, stdout, stderr or a log; it
# reaches curl through a config on stdin (`curl -K -`).
#
# Usage (run with the target repo as the working directory):
#   nja-linear.sh check
#   nja-linear.sh teams
#   nja-linear.sh ensure-labels
#   nja-linear.sh create-issue --title T --description-file F --priority N --label NAME [--label NAME...]
#   nja-linear.sh list-open
#   nja-linear.sh get-issue ID
#   nja-linear.sh upsert-doc ID --title T --content-file F
#   nja-linear.sh comment ID --body-file F
#   nja-linear.sh set-state ID "State Name"
#   nja-linear.sh add-label ID NAME
#   nja-linear.sh remove-label ID NAME
#
#   ID is an issue identifier, case-insensitive (WYR-12, wyr-12).
#   N is Linear's priority: 0 none, 1 urgent, 2 high, 3 medium, 4 low.
#   States and labels are resolved by NAME; labels team first, then workspace.
#
# Exit codes:
#   0  ok
#   1  usage error
#   2  not configured — no git repo, no .env, no LINEAR_API_KEY, or no
#      LINEAR_TEAM_ID for a command that needs one
#   3  API error — HTTP non-2xx, GraphQL errors, unknown state or label, or
#      more than 100 open issues
set -uo pipefail

ENDPOINT="https://api.linear.app/graphql"
LABELS_REQUIRED="Bug Feature Improvement Brainstorm Small"

usage() {
  cat <<'USAGE'
nja-linear.sh <command> [args]

  check                                   viewer name and configured team
  teams                                   list teams
  ensure-labels                           make sure Bug/Feature/Improvement/Brainstorm/Small exist
  create-issue --title T --description-file F --priority N --label NAME [--label NAME...]
  list-open                               open issues (backlog, unstarted, started)
  get-issue ID                            one issue with documents and comments
  upsert-doc ID --title T --content-file F
  comment ID --body-file F
  set-state ID "State Name"
  add-label ID NAME
  remove-label ID NAME
USAGE
}

die() { printf '%s\n' "$2" >&2; exit "$1"; }
usage_die() { printf '%s\n' "$1" >&2; usage >&2; exit 1; }

# Same shape as nja-fleet-survey.sh's guard: a bare trailing value-taking
# option would otherwise leave $1 unshifted and spin the parser forever.
require_optarg() {
  local opt="$1" remaining="$2" val="${3:-}"
  [ "$remaining" -lt 2 ] && usage_die "$opt requires a value"
  case "$val" in
    -*) usage_die "$opt requires a value, got option-like argument: $val" ;;
  esac
  return 0
}

require_file() {
  [ -f "$2" ] && [ -r "$2" ] || usage_die "$1 is not a readable file: $2"
}

# Upper-case and validate an issue identifier.
norm_id() {
  local id; id="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  printf '%s' "$id" | grep -qE '^[A-Z][A-Z0-9]*-[0-9]+$' || usage_die "not an issue identifier: $1"
  printf '%s' "$id"
}

# ── argument parsing (before any configuration or network) ───────────────────
[ $# -gt 0 ] || usage_die "no command given"
CMD="$1"; shift

ID=""; TITLE=""; FILE=""; PRIORITY=""; LABELS=""; NAME=""
case "$CMD" in
  -h|--help) usage; exit 0 ;;
  check|teams|ensure-labels|list-open)
    [ $# -eq 0 ] || usage_die "$CMD takes no arguments" ;;
  create-issue)
    while [ $# -gt 0 ]; do
      case "$1" in
        --title)            require_optarg "$1" "$#" "${2:-}"; TITLE="$2"; shift 2 ;;
        --description-file) require_optarg "$1" "$#" "${2:-}"; FILE="$2"; shift 2 ;;
        --priority)         require_optarg "$1" "$#" "${2:-}"; PRIORITY="$2"; shift 2 ;;
        --label)            require_optarg "$1" "$#" "${2:-}"; LABELS="$LABELS$2"$'\n'; shift 2 ;;
        *) usage_die "unknown option for create-issue: $1" ;;
      esac
    done
    [ -n "$TITLE" ]    || usage_die "create-issue needs --title"
    [ -n "$FILE" ]     || usage_die "create-issue needs --description-file"
    [ -n "$PRIORITY" ] || usage_die "create-issue needs --priority"
    [ -n "$LABELS" ]   || usage_die "create-issue needs at least one --label"
    printf '%s' "$PRIORITY" | grep -qE '^[0-4]$' || usage_die "--priority must be 0-4, got: $PRIORITY"
    require_file --description-file "$FILE" ;;
  get-issue)
    [ $# -eq 1 ] || usage_die "get-issue takes exactly one issue identifier"
    ID="$(norm_id "$1")" || exit 1 ;;
  upsert-doc|comment)
    [ $# -ge 1 ] || usage_die "$CMD needs an issue identifier"
    ID="$(norm_id "$1")" || exit 1; shift
    while [ $# -gt 0 ]; do
      case "$CMD:$1" in
        upsert-doc:--title)        require_optarg "$1" "$#" "${2:-}"; TITLE="$2"; shift 2 ;;
        upsert-doc:--content-file) require_optarg "$1" "$#" "${2:-}"; FILE="$2"; shift 2 ;;
        comment:--body-file)       require_optarg "$1" "$#" "${2:-}"; FILE="$2"; shift 2 ;;
        *) usage_die "unknown option for $CMD: $1" ;;
      esac
    done
    if [ "$CMD" = upsert-doc ]; then
      [ -n "$TITLE" ] || usage_die "upsert-doc needs --title"
      [ -n "$FILE" ]  || usage_die "upsert-doc needs --content-file"
      require_file --content-file "$FILE"
    else
      [ -n "$FILE" ] || usage_die "comment needs --body-file"
      require_file --body-file "$FILE"
    fi ;;
  set-state|add-label|remove-label)
    [ $# -eq 2 ] || usage_die "$CMD takes an issue identifier and a name"
    ID="$(norm_id "$1")" || exit 1
    NAME="$2"
    [ -n "$NAME" ] || usage_die "$CMD needs a non-empty name" ;;
  *) usage_die "unknown command: $CMD" ;;
esac

# ── configuration: the repo's .env, nothing else ─────────────────────────────
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die 2 "Not inside a git repository ($PWD), so there is no .env to read the Linear key from."
ENV_FILE="$ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || COMMON=""
  MAIN=""; [ -n "$COMMON" ] && MAIN="$(dirname "$COMMON")"
  if [ -n "$MAIN" ] && [ "$MAIN" != "$ROOT" ] && [ -f "$MAIN/.env" ]; then
    ENV_FILE="$MAIN/.env"
  elif [ -n "$MAIN" ] && [ "$MAIN" != "$ROOT" ]; then
    die 2 "No .env found at $ROOT/.env or at the main checkout's $MAIN/.env."
  else
    die 2 "No .env found at $ROOT/.env."
  fi
fi

# env_value NAME — last `NAME=` / `export NAME=` line of $ENV_FILE, CR
# removed. A quoted value is what lies between the opening quote and the next
# matching one (a `#` inside is kept; anything after the closing quote, such as
# `# comment`, is dropped). An unquoted value ends at the first `#` that starts
# the value or follows whitespace; trailing whitespace is removed.
env_value() {
  local v rest
  v="$(grep -E "^(export[[:space:]]+)?$1=" "$ENV_FILE" | tail -n 1 \
       | sed -E "s/^(export[[:space:]]+)?$1=//" | tr -d '\r')"
  case "$v" in
    \"*) rest="${v#\"}"
         case "$rest" in *\"*) v="${rest%%\"*}" ;; esac ;;
    \'*) rest="${v#\'}"
         case "$rest" in *\'*) v="${rest%%\'*}" ;; esac ;;
    *)   v="$(printf '%s' "$v" | sed -E -e 's/(^|[[:space:]])#.*$//' -e 's/[[:space:]]+$//')" ;;
  esac
  printf '%s' "$v"
}

KEY="$(env_value LINEAR_API_KEY)"
[ -n "$KEY" ] || die 2 "No LINEAR_API_KEY in $ENV_FILE; add your Linear personal API key there."
TEAM_ID="$(env_value LINEAR_TEAM_ID)"

# need_team — exits 2 when LINEAR_TEAM_ID is absent and 3 when it names no
# team the key can see.
need_team() {
  [ -n "$TEAM_ID" ] || die 2 "No LINEAR_TEAM_ID in $ENV_FILE; run nja-linear-setup first."
  team_lookup
  [ -n "$TEAM_JSON" ] || die 3 "$TEAM_ERR"
}

TMP="$(mktemp -d -t nja-linear)" || die 3 "Could not create a temporary directory."
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Escaped for a double-quoted curl config value.
KEY_ESC="$(printf '%s' "$KEY" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"

# ── transport ────────────────────────────────────────────────────────────────
# api <body-file> — POST it; on success sets RESP to the JSON body. Exits 3 on
# transport failure, non-2xx, unparseable JSON or GraphQL errors.
# With API_SOFT=1, an HTTP or GraphQL error sets API_ERR and returns 3
# instead of exiting; a transport failure always exits.
RESP=""
API_SOFT=0
API_ERR=""
api_fail() {
  if [ "$API_SOFT" = 1 ]; then API_ERR="$1"; return 3; fi
  die 3 "$1"
}
api() {
  local raw status rc
  API_ERR=""
  # -q must be curl's first argument: it stops curl reading ~/.curlrc.
  raw="$(printf 'header = "Authorization: %s"\n' "$KEY_ESC" \
    | curl -q -sS --max-time 30 -X POST -K - \
        -H 'Content-Type: application/json' \
        --data-binary "@$1" -w '\n%{http_code}' "$ENDPOINT" 2>"$TMP/curl.err")"
  rc=$?
  [ "$rc" -eq 0 ] || die 3 "Could not reach Linear (curl exit $rc): $(head -c 200 "$TMP/curl.err" | tr '\n' ' ')"
  status="${raw##*$'\n'}"
  RESP="${raw%$'\n'*}"
  [ "$raw" = "$status" ] && RESP=""
  local msg
  msg="$(printf '%s' "$RESP" | jq -r '[.errors[]?.message] | join("; ")' 2>/dev/null)"
  case "$status" in
    2??) ;;
    *) api_fail "Linear answered HTTP $status${msg:+: $msg}." || return 3 ;;
  esac
  printf '%s' "$RESP" | jq -e . >/dev/null 2>&1 || { api_fail "Linear returned a response that is not JSON." || return 3; }
  [ -z "$msg" ] || { api_fail "Linear returned an error: $msg" || return 3; }
  return 0
}

# ok_mutation <field> — die 3 unless .data.<field>.success is true.
ok_mutation() {
  printf '%s' "$RESP" | jq -e --arg f "$1" '.data[$f].success == true' >/dev/null 2>&1 \
    || die 3 "Linear did not confirm $1."
}

body() { printf '%s' "$TMP/body.json"; }

# ── operations ───────────────────────────────────────────────────────────────
Q_VIEWER='query Viewer { viewer { name } }'
Q_TEAM='query Team($id: String!) { team(id: $id) { id key name } }'
Q_TEAMS='query Teams { teams(first: 100) { nodes { id key name } } }'
Q_LABELS='query Labels($teamId: String!) { team(id: $teamId) { labels(first: 250) { nodes { id name } } } issueLabels(first: 250, filter: { team: { null: true } }) { nodes { id name } } }'
Q_LABELCREATE='mutation LabelCreate($input: IssueLabelCreateInput!) { issueLabelCreate(input: $input) { success issueLabel { id name } } }'
Q_STATES='query TeamStates($id: String!) { team(id: $id) { states(first: 100) { nodes { id name type } } } }'
Q_ISSUECREATE='mutation IssueCreate($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier url } } }'
Q_OPEN='query OpenIssues($teamId: ID!) { issues(first: 100, filter: { team: { id: { eq: $teamId } }, state: { type: { in: ["backlog", "unstarted", "started"] } } }) { pageInfo { hasNextPage } nodes { identifier title priority priorityLabel createdAt url state { name } labels { nodes { name } } documents { nodes { title } } } } }'
Q_ISSUE='query Issue($id: String!) { issue(id: $id) { id identifier title description url state { name } labels { nodes { id name } } documents { nodes { id title content } } comments { nodes { body createdAt } } } }'
Q_DOCCREATE='mutation DocumentCreate($input: DocumentCreateInput!) { documentCreate(input: $input) { success document { id url } } }'
Q_DOCUPDATE='mutation DocumentUpdate($id: String!, $input: DocumentUpdateInput!) { documentUpdate(id: $id, input: $input) { success document { id url } } }'
Q_COMMENT='mutation CommentCreate($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { id } } }'
Q_ISSUEUPDATE='mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success issue { identifier state { name } labels { nodes { name } } } } }'

# team_lookup — TEAM_JSON is {"id","key","name"} for $TEAM_ID, or empty with
# TEAM_ERR naming LINEAR_TEAM_ID when Linear knows no such team for this key.
TEAM_JSON=""
TEAM_ERR=""
team_lookup() {
  TEAM_JSON=""; TEAM_ERR=""
  jq -nc --arg q "$Q_TEAM" --arg t "$TEAM_ID" '{query:$q, variables:{id:$t}}' > "$(body)"
  API_SOFT=1
  if api "$(body)"; then
    TEAM_JSON="$(printf '%s' "$RESP" | jq -c '.data.team // empty | {id, key, name}')"
  fi
  API_SOFT=0
  [ -n "$TEAM_JSON" ] || TEAM_ERR="LINEAR_TEAM_ID $TEAM_ID in $ENV_FILE does not name a team this key can see${API_ERR:+ ($API_ERR)}; run nja-linear-setup to pick one."
}

# fetch_labels — LABELS_JSON holds the Labels response.
LABELS_JSON=""
fetch_labels() {
  jq -nc --arg q "$Q_LABELS" --arg t "$TEAM_ID" '{query:$q, variables:{teamId:$t}}' > "$(body)"
  api "$(body)"
  LABELS_JSON="$RESP"
}

# label_id NAME — team label first, then workspace; empty if neither.
label_id() {
  printf '%s' "$LABELS_JSON" | jq -r --arg n "$1" \
    '[(.data.team.labels.nodes // [])[] | select(.name == $n) | .id]
     + [(.data.issueLabels.nodes // [])[] | select(.name == $n) | .id] | .[0] // empty'
}

label_names() {
  printf '%s' "$LABELS_JSON" | jq -r \
    '[(.data.team.labels.nodes // [])[].name, (.data.issueLabels.nodes // [])[].name] | unique | join(", ")'
}

# state_id NAME — exits 3 listing the team's states when NAME is not one.
state_id() {
  jq -nc --arg q "$Q_STATES" --arg t "$TEAM_ID" '{query:$q, variables:{id:$t}}' > "$(body)"
  api "$(body)"
  local sid
  sid="$(printf '%s' "$RESP" | jq -r --arg n "$1" '[(.data.team.states.nodes // [])[] | select(.name == $n) | .id][0] // empty')"
  if [ -z "$sid" ]; then
    die 3 "The team has no state named \"$1\"; its states are: $(printf '%s' "$RESP" | jq -r '[(.data.team.states.nodes // [])[].name] | join(", ")')."
  fi
  STATE_ID="$sid"
}

# fetch_issue — ISSUE_JSON holds .data.issue for $ID; exits 3 if not found.
ISSUE_JSON=""
fetch_issue() {
  jq -nc --arg q "$Q_ISSUE" --arg id "$ID" '{query:$q, variables:{id:$id}}' > "$(body)"
  api "$(body)"
  ISSUE_JSON="$(printf '%s' "$RESP" | jq -c '.data.issue // empty')"
  [ -n "$ISSUE_JSON" ] || die 3 "Linear has no issue $ID."
}

# set_labels <ids-json-array> — IssueUpdate with the full label set; prints
# {"identifier","labels":[names]}.
set_labels() {
  jq -nc --arg q "$Q_ISSUEUPDATE" --arg id "$ID" --argjson l "$1" \
    '{query:$q, variables:{id:$id, input:{labelIds:$l}}}' > "$(body)"
  api "$(body)"
  ok_mutation issueUpdate
  printf '%s' "$RESP" | jq -c '.data.issueUpdate.issue | {identifier, labels: [(.labels.nodes // [])[].name]}'
}

# ── commands ─────────────────────────────────────────────────────────────────
case "$CMD" in
  check)
    jq -nc --arg q "$Q_VIEWER" '{query:$q}' > "$(body)"
    api "$(body)"
    viewer="$(printf '%s' "$RESP" | jq -r '.data.viewer.name // empty')"
    [ -n "$viewer" ] || die 3 "Linear did not return the API key's user."
    # A wrong LINEAR_TEAM_ID must not block setup: report it, exit 0.
    if [ -z "$TEAM_ID" ]; then
      jq -nc --arg v "$viewer" --arg e "$ENV_FILE" '{viewer:$v, team:null, env:$e}'
    else
      team_lookup
      if [ -n "$TEAM_JSON" ]; then
        jq -nc --arg v "$viewer" --argjson t "$TEAM_JSON" --arg e "$ENV_FILE" '{viewer:$v, team:$t, env:$e}'
      else
        jq -nc --arg v "$viewer" --arg e "$ENV_FILE" --arg te "$TEAM_ERR" '{viewer:$v, team:null, env:$e, teamError:$te}'
      fi
    fi ;;

  teams)
    jq -nc --arg q "$Q_TEAMS" '{query:$q}' > "$(body)"
    api "$(body)"
    printf '%s' "$RESP" | jq -c '[(.data.teams.nodes // [])[] | {id, key, name}]' ;;

  ensure-labels)
    need_team
    fetch_labels
    out="[]"
    for n in $LABELS_REQUIRED; do
      lid="$(label_id "$n")"
      created=false
      if [ -z "$lid" ]; then
        jq -nc --arg q "$Q_LABELCREATE" --arg n "$n" --arg t "$TEAM_ID" \
          '{query:$q, variables:{input:{name:$n, teamId:$t}}}' > "$(body)"
        api "$(body)"
        ok_mutation issueLabelCreate
        lid="$(printf '%s' "$RESP" | jq -r '.data.issueLabelCreate.issueLabel.id // empty')"
        [ -n "$lid" ] || die 3 "Linear did not return an id for the new label $n."
        created=true
      fi
      out="$(jq -nc --argjson o "$out" --arg n "$n" --arg i "$lid" --argjson c "$created" '$o + [{name:$n, id:$i, created:$c}]')"
    done
    printf '%s\n' "$out" ;;

  create-issue)
    need_team
    fetch_labels
    ids="[]"
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      lid="$(label_id "$n")"
      [ -n "$lid" ] || die 3 "No label named \"$n\" on the team or the workspace; available: $(label_names)."
      ids="$(jq -nc --argjson a "$ids" --arg i "$lid" '$a + [$i] | unique')"
    done <<EOF_LABELS
$LABELS
EOF_LABELS
    state_id "Todo"
    jq -nc --arg q "$Q_ISSUECREATE" --arg t "$TEAM_ID" --arg title "$TITLE" --rawfile d "$FILE" \
      --argjson p "$PRIORITY" --argjson l "$ids" --arg s "$STATE_ID" \
      '{query:$q, variables:{input:{teamId:$t, title:$title, description:$d, priority:$p, labelIds:$l, stateId:$s}}}' > "$(body)"
    api "$(body)"
    ok_mutation issueCreate
    printf '%s' "$RESP" | jq -c '.data.issueCreate.issue | {id, identifier, url}' ;;

  list-open)
    need_team
    jq -nc --arg q "$Q_OPEN" --arg t "$TEAM_ID" '{query:$q, variables:{teamId:$t}}' > "$(body)"
    api "$(body)"
    if printf '%s' "$RESP" | jq -e '.data.issues.pageInfo.hasNextPage == true' >/dev/null; then
      die 3 "The team has more than 100 open issues; list-open reads only one page of 100."
    fi
    printf '%s' "$RESP" | jq -c '[(.data.issues.nodes // [])[] | {identifier, title, priority, priorityLabel,
      state: .state.name, labels: [(.labels.nodes // [])[].name], documents: [(.documents.nodes // [])[].title],
      createdAt, url}]' ;;

  get-issue)
    need_team
    fetch_issue
    printf '%s' "$ISSUE_JSON" | jq -c '{id, identifier, title, description, url, state: .state.name,
      labels: [(.labels.nodes // [])[].name],
      documents: [(.documents.nodes // [])[] | {id, title, content}],
      comments: ([(.comments.nodes // [])[] | {body, createdAt}] | sort_by(.createdAt))}' ;;

  upsert-doc)
    need_team
    fetch_issue
    iid="$(printf '%s' "$ISSUE_JSON" | jq -r '.id')"
    did="$(printf '%s' "$ISSUE_JSON" | jq -r --arg t "$TITLE" '[(.documents.nodes // [])[] | select(.title == $t) | .id][0] // empty')"
    if [ -n "$did" ]; then
      jq -nc --arg q "$Q_DOCUPDATE" --arg id "$did" --arg t "$TITLE" --rawfile c "$FILE" \
        '{query:$q, variables:{id:$id, input:{title:$t, content:$c}}}' > "$(body)"
      api "$(body)"
      ok_mutation documentUpdate
      printf '%s' "$RESP" | jq -c '.data.documentUpdate.document | {id, url, created:false}'
    else
      jq -nc --arg q "$Q_DOCCREATE" --arg i "$iid" --arg t "$TITLE" --rawfile c "$FILE" \
        '{query:$q, variables:{input:{title:$t, content:$c, issueId:$i}}}' > "$(body)"
      api "$(body)"
      ok_mutation documentCreate
      printf '%s' "$RESP" | jq -c '.data.documentCreate.document | {id, url, created:true}'
    fi ;;

  comment)
    need_team
    fetch_issue
    iid="$(printf '%s' "$ISSUE_JSON" | jq -r '.id')"
    jq -nc --arg q "$Q_COMMENT" --arg i "$iid" --rawfile b "$FILE" \
      '{query:$q, variables:{input:{issueId:$i, body:$b}}}' > "$(body)"
    api "$(body)"
    ok_mutation commentCreate
    printf '%s' "$RESP" | jq -c '.data.commentCreate.comment | {id}' ;;

  set-state)
    need_team
    state_id "$NAME"
    jq -nc --arg q "$Q_ISSUEUPDATE" --arg id "$ID" --arg s "$STATE_ID" \
      '{query:$q, variables:{id:$id, input:{stateId:$s}}}' > "$(body)"
    api "$(body)"
    ok_mutation issueUpdate
    printf '%s' "$RESP" | jq -c '.data.issueUpdate.issue | {identifier, state: .state.name}' ;;

  add-label|remove-label)
    need_team
    fetch_labels
    lid="$(label_id "$NAME")"
    [ -n "$lid" ] || die 3 "No label named \"$NAME\" on the team or the workspace; available: $(label_names)."
    fetch_issue
    current="$(printf '%s' "$ISSUE_JSON" | jq -c '[(.labels.nodes // [])[].id]')"
    has="$(printf '%s' "$current" | jq -r --arg i "$lid" 'index($i) != null')"
    if [ "$CMD" = add-label ]; then
      if [ "$has" = true ]; then
        printf '%s' "$ISSUE_JSON" | jq -c '{identifier, labels: [(.labels.nodes // [])[].name]}'
      else
        set_labels "$(jq -nc --argjson a "$current" --arg i "$lid" '$a + [$i]')"
      fi
    else
      if [ "$has" = true ]; then
        set_labels "$(jq -nc --argjson a "$current" --arg i "$lid" '$a - [$i]')"
      else
        printf '%s' "$ISSUE_JSON" | jq -c '{identifier, labels: [(.labels.nodes // [])[].name]}'
      fi
    fi ;;
esac
