# Linear integration Implementation Plan

> **For agentic workers:** Tasks 1–4 are independent and are dispatched in parallel (one Opus sub-agent each, one message). Task 5 runs after all four land, in the coordinating session. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `nja-linear.sh` and four skills (`nja-linear-setup`, `nja-linear-capture`, `nja-linear-next`, `nja-linear-start`) to the nja plugin, plus Linear hooks in `nja-writing-plan` and `nja-delegate-implementation`.

**Architecture:** One bash script is the only code that talks to Linear's GraphQL API; it reads the key and team from the repo's `.env` and prints JSON. Skills call the script and never build GraphQL or curl themselves. Tests replace `curl` with a fake on `PATH`.

**Tech Stack:** bash, curl, jq, Linear GraphQL API, Claude Code SKILL.md files.

**Spec:** `/Users/carlo/Development/nja/docs/superpowers/specs/2026-10-27-nja-linear-design.md`

## Global Constraints

- Repo: `/Users/carlo/Development/nja`. All paths below are relative to it.
- **No git commits, adds, stashes or branches at any point**, in any task or sub-agent. Carlo commits after testing.
- Endpoint `https://api.linear.app/graphql`; header `Authorization: <key>`, **no** `Bearer`.
- Key and team come only from `.env` at `git rev-parse --show-toplevel`, else the main checkout `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`. Never from the process environment, never another directory.
- The key never appears in curl's argv, stdout, stderr, or any log.
- States and labels are resolved by **name**. Labels: team first, then workspace.
- Label names exactly: `Bug`, `Feature`, `Improvement`, `Brainstorm`, `Small`. Document titles exactly: `Spec`, `Plan`. State names exactly: `Todo`, `In Progress`, `In Review`.
- In Review only when checks are green; otherwise stay In Progress and comment.
- Skills: frontmatter `name` equals directory; description third person, ≤1024 chars, no XML tags; body < 500 lines (enforced by `nja/tests/test-skills.sh`).
- Plugin version 1.26.0.
- Sub-agents run only their own suite (`bash nja/tests/run.sh <suite>`), never the full suite.

## Review Focus

1. A `.env` line written as `export LINEAR_API_KEY=...`, quoted (`"..."` / `'...'`), with trailing spaces or a CRLF ending must parse to the bare key. → Task 1, `env_parsing` tests.
2. Titles, descriptions and documents containing double quotes, backticks, `$`, newlines and non-ASCII (`è`, `—`) must reach Linear byte-for-byte. → Task 1, `json_escaping` test.
3. An identifier typed lowercase (`wyr-12`) must work like `WYR-12`. → Task 1, `identifier_case` test.
4. A state name the team does not have (`set-state WYR-1 "Review"`) must fail with exit 3 and list the team's real state names, not send a null id. → Task 1, `unknown_state` test.
5. Running outside a git repo, or in a repo without `.env`, must exit 2 naming the path it looked at, not fall through to another `.env`. → Task 1, `no_repo` and `missing_env` tests.

---

## Shared Contracts

Every task uses these exactly. Tasks 2–4 never call Linear directly.

**Invocation:** `"${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh" <command> [args]`, run with the target repo as the working directory. In skills, write it as `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh`.

**Exit codes:** `0` ok · `1` usage error · `2` not configured (no git repo, no `.env`, no `LINEAR_API_KEY`, or no `LINEAR_TEAM_ID` for a command that needs it) · `3` API error (HTTP non-2xx, GraphQL `errors`, unknown state or label, more than 100 open issues). Errors: one human sentence on stderr, nothing on stdout.

**Commands and stdout JSON:**

| Command | Needs team | Output |
|---|---|---|
| `check` | no | `{"viewer":"<name>","team":{"id","key","name"}\|null,"env":"<absolute path of the .env read>"}`; when `LINEAR_TEAM_ID` names no team the key can see: exit 0, `"team":null` plus `"teamError":"<message naming LINEAR_TEAM_ID>"` (every command that needs the team exits 3 in that case) |
| `teams` | no | `[{"id","key","name"}]` |
| `ensure-labels` | yes | `[{"name","id","created":bool}]` for the five labels |
| `create-issue --title T --description-file F --priority N --label NAME [--label NAME…]` | yes | `{"id","identifier","url"}`; created in state `Todo`; `N` is Linear's 0 none, 1 urgent, 2 high, 3 medium, 4 low |
| `list-open` | yes | `[{"identifier","title","priority","priorityLabel","state","labels":[names],"documents":[titles],"createdAt","url"}]` for states of type backlog, unstarted, started |
| `get-issue ID` | yes | `{"id","identifier","title","description","url","state","labels":[names],"documents":[{"id","title","content"}],"comments":[{"body","createdAt"}]}` |
| `upsert-doc ID --title T --content-file F` | yes | `{"id","url","created":bool}`; replaces content if the issue already has a document with that title |
| `comment ID --body-file F` | yes | `{"id"}` |
| `set-state ID "State Name"` | yes | `{"identifier","state"}` |
| `add-label ID NAME` | yes | `{"identifier","labels":[names]}`; keeps existing labels; unknown label → exit 3 (added during execution: spec § 7.4 needs it) |
| `remove-label ID NAME` | yes | same output; removes only that label; absent label → no-op exit 0; unknown label → exit 3 (added with `add-label`) |

`ID` is an issue identifier, case-insensitive (`WYR-12`, `wyr-12`).

**GraphQL operation names** (every request is a named operation; the test fake routes on them): `Viewer`, `Teams`, `Team`, `Labels`, `LabelCreate`, `TeamStates`, `IssueCreate`, `OpenIssues`, `Issue`, `DocumentCreate`, `DocumentUpdate`, `CommentCreate`, `IssueUpdate`.

**Linear document format** (written by skills, read by `nja-linear-start`): the first line is `Source: <repo-relative path>`, then a blank line, then the file's content verbatim.

---

### Task 1: `nja-linear.sh` and its test suite

**Files:**
- Create: `nja/scripts/nja-linear.sh` (executable)
- Create: `nja/tests/fixtures/fake-linear/curl` (executable)
- Create: `nja/tests/test-linear.sh`

**Interfaces:**
- Consumes: `nja/tests/lib.sh` helpers (`t_case`, `t_assert_eq`, `t_assert_contains`, `t_assert_not_contains`, `t_assert_exit`); `$NJA_SCRIPTS_DIR` from `run.sh`. Suites are sourced into one shell, so prefix every variable and function in `test-linear.sh` with `_lin_`.
- Produces: the Shared Contracts above.

**Fake curl contract** (so tests and script agree):
- Reads the request body from whichever `--data`/`--data-binary @file` or stdin form the script uses, extracts the operation name (`query <Name>` / `mutation <Name>`), and prints `$FAKE_LINEAR_DIR/<Name>.json`.
- Appends one line per call to `$FAKE_LINEAR_DIR/argv.log` (its full argv), the body to `$FAKE_LINEAR_DIR/bodies.log`, and the `Authorization` header value it received (from a `-K` config or a header file, whichever the script uses) to `$FAKE_LINEAR_DIR/auth.log`.
- If `$FAKE_LINEAR_DIR/<Name>.status` exists, reports that HTTP status in whatever way the script reads it (for example the `-w '%{http_code}'` trailer); default `200`.
- Tests put the fixture directory first on `PATH`.

- [ ] **Step 1: Write the failing tests** in `nja/tests/test-linear.sh`. Each test makes a fresh fixture repo with `git init` in a `mktemp -d` and writes its own `.env`. Cases, by `t_case` name:
  - `env_parsing`: for each of `LINEAR_API_KEY=lin_abc`, `export LINEAR_API_KEY=lin_abc`, `LINEAR_API_KEY="lin_abc"`, `LINEAR_API_KEY='lin_abc'`, `LINEAR_API_KEY=lin_abc  ` and `LINEAR_API_KEY=lin_abc\r`, `check` exits 0 and the last line of `auth.log` is exactly `lin_abc`.
  - `key_not_in_argv`: after `check`, `argv.log` does not contain `lin_abc`; stdout and stderr do not contain it either.
  - `worktree_fallback`: main checkout has `.env`; `git worktree add` a second tree with no `.env`; `check` run inside the worktree exits 0 using the main checkout's key.
  - `missing_env`: repo with no `.env` → exit 2, stderr contains the repo root path.
  - `missing_key`: `.env` without `LINEAR_API_KEY` → exit 2.
  - `env_var_ignored`: `LINEAR_API_KEY=lin_env` exported in the environment, repo has no `.env` → exit 2 (the environment is never read).
  - `no_repo`: run in a non-git temp dir → exit 2.
  - `missing_team`: `.env` has key, no `LINEAR_TEAM_ID` → `check` exits 0 with `"team":null`; `list-open` exits 2.
  - `json_escaping`: `create-issue --title 'Fix "quoted" `tick` $HOME è —' --description-file <file with the same plus newlines>` → the variables in `bodies.log` decode (via `jq`) to exactly those strings.
  - `identifier_case`: `get-issue wyr-12` sends `WYR-12` in the `Issue` request variables.
  - `unknown_state`: `TeamStates.json` holds Todo/In Progress/In Review; `set-state WYR-1 "Review"` → exit 3, stderr lists `Todo`, `In Progress`, `In Review`; no `IssueUpdate` in `bodies.log`.
  - `set_state_by_name`: `set-state WYR-1 "In Review"` sends the id that `TeamStates.json` maps to `In Review`.
  - `labels_team_then_workspace`: `Labels.json` has `Bug` on the team and `Feature` only at workspace level → `ensure-labels` creates exactly `Improvement`, `Brainstorm`, `Small` (three `LabelCreate` calls, each with the team id) and reports `Bug`/`Feature` with `"created":false`.
  - `upsert_updates`: `Issue.json` already has a document titled `Plan` → `upsert-doc WYR-1 --title Plan --content-file f` calls `DocumentUpdate`, not `DocumentCreate`, and prints `"created":false`. Without it → `DocumentCreate` with `issueId` set, `"created":true`.
  - `http_error`: `Viewer.status` = `401` → `check` exit 3, stdout empty.
  - `graphql_error`: `Viewer.json` = `{"errors":[{"message":"boom"}]}` → exit 3, stderr contains `boom`.
  - `too_many_open`: `OpenIssues.json` with `pageInfo.hasNextPage: true` → `list-open` exit 3.
  - `usage`: no command → exit 1; unknown command → exit 1; `create-issue` without `--title` → exit 1, and the parser must not hang (mirror the bounded-exit guard in `test-dev-boot.sh`).

- [ ] **Step 2: Run the suite and confirm it fails**

Run: `bash nja/tests/run.sh linear`
Expected: failures (script missing).

- [ ] **Step 3: Implement `nja/scripts/nja-linear.sh`**, header comment in the style of `nja-fleet-survey.sh` (purpose, usage, exit codes). Build request bodies with `jq -n --arg/--rawfile` so escaping is jq's. Pass the key to curl through a config on stdin (`curl -K -`) or a mode-600 temp header file removed on exit; never `-H "Authorization: $key"`. Parse `.env` with a line match on `^(export )?LINEAR_API_KEY=`, stripping one layer of matching quotes, trailing whitespace and `\r`. Upper-case identifiers before sending.

- [ ] **Step 4: Run the suite and confirm it passes**

Run: `bash nja/tests/run.sh linear`
Expected: `all N passed`.

- [ ] **Step 5: Smoke against the real API (read-only)**

Run from `/Users/carlo/Development/wyrdli`: `/Users/carlo/Development/nja/nja/scripts/nja-linear.sh check` then `teams`.
Expected: viewer `Carlo Nicora`; teams contains key `WYR`. No other command against the real API in this task.

---

### Task 2: The four skills

**Files:**
- Create: `nja/skills/nja-linear-setup/SKILL.md`
- Create: `nja/skills/nja-linear-capture/SKILL.md`
- Create: `nja/skills/nja-linear-next/SKILL.md`
- Create: `nja/skills/nja-linear-start/SKILL.md`

**Interfaces:**
- Consumes: Shared Contracts (commands, exit codes, document format).
- Produces: skill names exactly as above; `nja-linear-next` hands off to `nja-linear-start` with an identifier; `nja-linear-start` hands off to `superpowers:brainstorming`, `nja-writing-plan` and `nja-delegate-implementation` with the identifier in context (Tasks 3 reads it from there).

Each skill implements its spec section word for word in behaviour: setup § 7.1, capture § 7.2, next § 7.3, start § 7.4. Every skill opens by running `check` and stops on exit 2 with the script's message. Every write to files on disk the user owns (`.env`) is asked first. None commits.

Specific requirements a reader might miss:
- **setup:** writes `LINEAR_TEAM_ID=<id>` by appending one line to `.env` only after a yes; never rewrites existing lines; never prints the key.
- **capture:** exactly one question to the user, showing title, the full description (sections *What*, *Where*, *Why it matters*, *Reproduce* (bugs only), *Done when*, *Found while*), proposed priority with a one-line reason, proposed kind, and asking Brainstorm or Small. Description is written to a temp file and passed with `--description-file`.
- **next:** sort order In Progress → In Review → priority Urgent, High, Medium, Low, none → oldest `createdAt`. Numbered rows: identifier, title, priority, state, Brainstorm/Small, and Spec/Plan presence for Brainstorm issues. Asks which; never recommends.
- **start, Small path:** stop-and-ask triggers are exactly: more than one feature area, a data-model change, or a decision that is Carlo's. The analysis comment has *Cause*, *Files*, *Intended fix*. In Review only if the affected spec passed; otherwise comment the failure and leave In Progress.
- **start, Brainstorm path:** the resume table from spec § 7.4. The brainstorming hand-off text must tell it: the plan step is `nja-writing-plan`, the spec is never committed, and the Linear issue identifier is `<ID>`. Before resuming, for each existing document read its `Source:` line; if that file is missing on disk, write the document body (everything after the first blank line) to that path and tell Carlo.
- Descriptions: third person, triggers quoted, e.g. `"save this as a task"`, `"what's next"`, `"start WYR-12"`.

- [ ] **Step 1: Write the four SKILL.md files.**
- [ ] **Step 2: Run the skill checks**

Run: `bash nja/tests/run.sh skills`
Expected: `all N passed` (the new skills included).

---

### Task 3: Linear steps in `nja-writing-plan` and `nja-delegate-implementation`

**Files:**
- Modify: `nja/skills/nja-writing-plan/SKILL.md` (new section after "Independent plan audit (after the plan is saved)")
- Modify: `nja/skills/nja-delegate-implementation/SKILL.md` (Step 1 Collect, the template, the section table at line 39, the common-mistakes row at line 138)

**Interfaces:**
- Consumes: Shared Contracts; the issue identifier that `nja-linear-start` puts in context.
- Produces: nothing new for other tasks.

**`nja-writing-plan`**, new section "Linear (when configured)", implementing spec § 7.5:
- Run `check`. Exit 2 → skip silently.
- Identifier in context → `upsert-doc <ID> --title Spec` with the spec file, then `--title Plan` with the plan file, both in the Shared Contracts document format.
- No identifier → the same single draft-and-confirm question as `nja-linear-capture` (description from the spec's intent section; Brainstorm label preset). Yes → `create-issue`, then both `upsert-doc`. No → skip.

**`nja-delegate-implementation`**, implementing spec § 7.6:
- Step 1 Collect gains item 4: the Linear issue identifier and URL, if one is in context.
- Template "Context not in either document" gains a **Linear issue** block (identifier + URL), present only when an identifier exists.
- Template execution protocol gains step 7, present only when an identifier exists: post a `comment` listing tasks landed, lint/build/test results and open audit findings; then, only if lint, build and test are green and no BLOCKING finding remains, `set-state <ID> "In Review"`; otherwise leave it In Progress. Use the script's absolute path resolved at delegation time (the fresh session may not have `CLAUDE_PLUGIN_ROOT` pointing at the same checkout).
- Line 39 and line 138: "six steps" → "six steps (seven with a Linear issue)".

- [ ] **Step 1: Make both edits.**
- [ ] **Step 2: Run the skill checks**

Run: `bash nja/tests/run.sh skills`
Expected: `all N passed`.

---

### Task 4: README and version

**Files:**
- Modify: `README.md` (skills table, a new "Linear" section, layout tree)
- Modify: `nja/.claude-plugin/plugin.json:3`, `.claude-plugin/marketplace.json:3` and `:13` → `1.26.0`
- Modify: both manifests' `description` strings: add "Linear issue tracking" to the list.

**Interfaces:**
- Consumes: skill names and the script name from Shared Contracts.

README "Linear" section contents: the two `.env` variables and who sets each; that the key is per repo and never read from the environment; the flow capture → next → start → In Review → Done by hand; that `nja-writing-plan` and `nja-delegate-implementation` update the issue when one is in context. Skills table rows follow the existing one-sentence style. Layout tree gains `nja-linear.sh`, the four skill directories, and `fixtures/fake-linear`.

- [ ] **Step 1: Make the edits.**
- [ ] **Step 2: Verify**

Run: `grep -rn '1\.25\.0' nja/.claude-plugin .claude-plugin; jq . nja/.claude-plugin/plugin.json .claude-plugin/marketplace.json >/dev/null && echo ok`
Expected: no `1.25.0` hits; `ok`.

---

### Task 5: Verification (coordinator, after Tasks 1–4)

- [ ] **Step 1: Full suite**

Run: `bash nja/tests/run.sh`
Expected: `all N passed`. Fix any failure, including pre-existing ones, and re-run.

- [ ] **Step 2: Review** — one fresh Opus sub-agent reads the spec, this plan and `git -C /Users/carlo/Development/nja diff` plus untracked files, and reports deviations. Fix them; re-run the affected suite.

- [ ] **Step 3: Manual run on wyrdli's real workspace** (spec § 9), from `/Users/carlo/Development/wyrdli`:
  1. `nja-linear-setup`: confirm team `WYR`, approve the `.env` append, labels report five present.
  2. `nja-linear-capture` on a throwaway finding titled `TEST — delete me`: Small, priority Low. Confirm in Linear the description has every section.
  3. `nja-linear-next`: the issue is listed; pick it.
  4. `nja-linear-start`: it moves to In Progress and posts the analysis comment. Stop there.
  Expected: each step's state visible at the issue URL. Tell Carlo the identifier so he deletes it.

- [ ] **Step 4: Report** — files created/changed, suite result, review findings, manual run result, the throwaway issue URL. No commit.
