# Design: Linear integration for the `nja` plugin

Four skills and one script that make Linear the to-do list of each nja repo:
capture issues while working, ask what to work on next, and start an issue so
that the analysis, spec and plan it needs are produced and stored on the issue
before implementation.

- **Date:** 2026-10-27
- **Status:** design, awaiting approval
- **Plugin version target:** 1.26.0
- **Relationship to existing skills:** additive, plus small edits to
  `nja-writing-plan` and `nja-delegate-implementation` (section 7).

---

## 1. Intent

Carlo finds work while working on something else and loses it. He also runs
several brainstorming sessions ahead of implementation and wants to pick them
up later without hunting for files. Linear holds the list; Claude Code reads
and writes it.

Success looks like:

- "save this as a task" produces a Linear issue a stranger could act on.
- "what's next" shows the open issues by priority and lets him choose.
- "start WYR-12" takes the issue to In Review without him having to
  remember where its spec and plan live, or whether they exist yet.

## 2. Goals, non-goals, anti-goals

**Goals**

- One Linear key per repo. A repo can never write to another repo's workspace.
- Every issue has a real title and a self-contained description.
- Brainstorm issues carry their spec and plan as Linear documents.
- Status moves automatically: Todo on capture, In Progress on start,
  In Review when implementation finishes with its checks green. Failed
  checks leave the issue In Progress with a comment.

**Non-goals**

- No `done` skill. Carlo moves issues to Done by hand after testing and
  committing.
- No two-way sync. Editing a spec file later does not update Linear, and
  editing the Linear document does not update the file. The skills write to
  Linear at the moments listed below and nowhere else.
- No cycles, projects, milestones or assignees. The workspace uses none.
- No Linear MCP server.

**Anti-goals** (failure even if it technically works)

- Writing to the wrong workspace because a key leaked across repos.
- Picking the next issue for him. `next` lists; he chooses.
- Silently upgrading a Small issue to a Brainstorm, or the reverse.
- Any git commit, at any step.

## 3. Constraints (verified 2026-10-27 against the live API)

- Endpoint `https://api.linear.app/graphql`. A personal API key is sent as
  `Authorization: <key>` with **no** `Bearer` prefix. Verified working.
- `DocumentCreateInput` accepts `issueId`, so documents attach directly to an
  issue. `Issue.documents` lists them.
- Wyrdli's workspace: one team, `Wyrdli`, key `WYR`, id
  `3924479f-0c21-488f-9e52-2c732750b3e2`. States: Backlog, Todo,
  In Progress, In Review, Done, Canceled, Duplicate. Labels: Bug, Feature,
  Improvement. No cycles. No open issues.
- `.env` is gitignored in wyrdli (`.gitignore:45`). `neural-erp`, `only35`
  and `phlow` also have a root `.env`.
- The plugin is shell-only: scripts are bash, tested by `nja/tests/run.sh`.
  `jq` is already a hard requirement of the hooks.
- Worktrees: `.env` is gitignored, so a worktree under `.claude/worktrees/`
  has no `.env` of its own.

## 4. Approaches considered

1. **Shell script + skills (chosen).** `nja-linear.sh` calls the GraphQL API
   with curl and jq, reading the key from the repo's `.env`. Per-repo key for
   free, fixed and testable calls, no dependencies. Cost: a small amount of
   GraphQL per action.
2. **Linear's official MCP server, configured per repo in `.mcp.json`.** No
   API code. Rejected: the header's `${VAR}` comes from the shell
   environment, not `.env`, so switching keys per repo needs direnv; every
   repo needs a committed `.mcp.json`; Claude composes calls freely, so
   results vary.
3. **Node tool on `@linear/sdk`.** Typed and easy to extend. Rejected: adds a
   Node dependency and install step to a shell-only plugin.

Carlo picked 1.

## 5. Configuration

Two variables in the repo's root `.env`:

| Variable | Set by | Meaning |
|---|---|---|
| `LINEAR_API_KEY` | Carlo, by hand | personal API key for that repo's workspace |
| `LINEAR_TEAM_ID` | `nja-linear-setup`, after asking | the team issues are created in |

**Resolving `.env`.** The script looks for `.env` in
`git rev-parse --show-toplevel`. If absent (a worktree), it falls back to the
main checkout: `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`.
It never reads the process environment for these two variables, never walks
further up, and never reads another repo's `.env`. A missing key is a hard
error naming the file it looked in.

The key is never printed, logged, or passed on a command line visible in
`ps` (use a curl config on stdin or `-H @file`, builder's choice).

## 6. The script: `nja/scripts/nja-linear.sh`

The only code that talks to Linear. Skills call it; they never write GraphQL
or curl themselves. All output is JSON on stdout; errors go to stderr with a
non-zero exit.

Subcommands (names are the builder's call; the set is not):

| Action | Purpose |
|---|---|
| check | validate key + team, print viewer name and team key |
| teams | list teams (for setup) |
| ensure-labels | create `Brainstorm` and `Small` labels on the team if missing |
| create-issue | title, markdown description, priority, label → returns identifier + url, state Todo |
| list-open | issues in Backlog/Todo/In Progress/In Review, with priority, state, labels, and the titles of attached documents |
| get-issue | one issue by identifier: description, labels, state, documents (with content), comments |
| upsert-doc | create or replace the document with a given title on an issue (titles `Spec` and `Plan`) |
| comment | add a markdown comment to an issue |
| set-state | move an issue to a named state (resolved to the team's state id) |

States are resolved by **name** against the team, so a workspace with
different state ids works unchanged.

## 7. The skills

All four live in `nja/skills/`. All four start by running the script's check
and stop with its error if the repo is not configured.

### 7.1 `nja-linear-setup`

Run once per repo.

1. Run check. If `LINEAR_API_KEY` is missing, tell Carlo which `.env` to add
   it to and stop.
2. List teams. One team: propose it. Several: numbered list, he picks.
3. Ask before writing `LINEAR_TEAM_ID=...` to `.env` (the file is his).
   Append; never rewrite other lines.
4. Ensure five labels exist: `Bug`, `Feature`, `Improvement`, `Brainstorm`,
   `Small`. A label counts as existing if the team or the workspace has it
   (Linear's default kind labels live at workspace level); missing ones are
   created on the team. Lookups everywhere follow the same team-then-workspace
   rule.
5. Report: workspace, team key, labels ready.

### 7.2 `nja-linear-capture`

Triggers: "save this as a task", "add this to Linear", "create an issue for
this", "log this for later".

1. Draft from the conversation and the code:
   - **Title:** imperative, specific, under ~70 characters.
   - **Description** (markdown), sections:
     - *What* — what was found or is wanted.
     - *Where* — file:line, page URL, or record, as relevant.
     - *Why it matters* — the consequence of leaving it.
     - *Reproduce* — steps, bugs only.
     - *Done when* — observable outcome.
     - *Found while* — one line on the task that surfaced it.
   - **Priority:** proposed, with a one-line reason.
   - **Kind:** the existing Bug/Feature/Improvement label, proposed.
2. Ask **one** question showing the drafted title, description, priority and
   kind, and asking Brainstorm or Small. Carlo confirms or edits in the same
   answer.
3. Create the issue in Todo with labels `<kind>` + `Brainstorm|Small`.
4. If the work already has a spec or plan file on disk (written or read in
   this conversation, or named by Carlo), the issue is Brainstorm without
   asking, and each file is attached as a `Spec` / `Plan` document right after
   creation. (Added 2026-10-27 after a capture with a ready spec and plan
   produced an issue with no documents.)
5. Report the identifier, URL and attached documents, one line.

Never interrupts the current task beyond that one question, and never starts
work on the issue.

### 7.3 `nja-linear-next`

Triggers: "what's next", "what should I work on", "show my issues".

1. list-open.
2. Show a numbered list sorted In Progress first, then In Review, then by
   priority (Urgent → High → Medium → Low → none), then oldest first. Each
   row: identifier, title, priority, state, Brainstorm/Small, and for
   Brainstorm issues whether a Spec and Plan document exist.
3. Ask which one. No recommendation.
4. On a pick, invoke `nja-linear-start` with that identifier.

### 7.4 `nja-linear-start`

Triggers: "start WYR-12", "work on WYR-12", a pick from `next`.

1. get-issue. If it has neither `Brainstorm` nor `Small`, ask which and add
   the label.
2. set-state In Progress.
3. Branch on the label.

**Small**

1. Analyse: read the code the description points at, reproduce if a bug
   (following the repo's own debugging rules). Post the findings as a
   comment: cause, files involved, intended fix.
2. If the analysis shows the work is not small (more than one feature area,
   a data-model change, or a decision that is Carlo's), **stop and ask**:
   switch to Brainstorm, or carry on as Small. Never switch silently.
3. Fix in this session, following `nja-architecture` for any file it
   governs. Run the affected spec.
4. If the affected spec passes: set-state In Review and post a comment
   listing the files changed. If it fails: leave the issue In Progress and
   post a comment with the failure. In Review always means "ready for Carlo
   to test" (Carlo's decision, 2026-10-27).
5. Report. No commit.

**Brainstorm**

The issue's documents decide where it resumes:

| Spec doc | Plan doc | Next step |
|---|---|---|
| no | no | brainstorm |
| yes | no | plan |
| yes | yes | delegate |

- **Brainstorm.** Invoke `superpowers:brainstorming`, giving it the issue's
  title and description as the starting request, plus two instructions in
  the hand-off: after the design is approved, the plan step is
  `nja-writing-plan` (not plain `superpowers:writing-plans`), and the spec is
  saved but never committed. Brainstorming does not return control to
  `start`; it chains into the plan step, so the `Spec` upload happens there
  (section 7.5).
- **Plan.** Invoke `nja-writing-plan`. When saved, it uploads `Spec` (if the
  issue has none yet) and `Plan` (section 7.5). Continue to delegate.
- **Delegate.** Invoke `nja-delegate-implementation`, passing the issue
  identifier (section 7.6).

**Files are the source of truth.** Each Linear document begins with a
`Source:` line holding the file's repo-relative path. When resuming, if that
file is missing on disk (a different machine, a deleted worktree), restore it
from the document's content before continuing, and say so.

### 7.5 Edit: `nja-writing-plan`

One new step after the plan is saved and audited:

- If a Linear issue is in context (from `nja-linear-start` or
  `nja-linear-capture`), upsert-doc `Spec` and `Plan` on it. Uploading the
  spec here, not in `start`, is required because brainstorming never hands
  control back. Only when the session ran `nja-linear-start` on that issue
  does it then invoke `nja-delegate-implementation`; a captured issue is
  queued work and stops after the upload.
- If none is in context and the repo is configured, run the same single
  draft-and-confirm question as `nja-linear-capture` (title, description
  from the spec's intent section, proposed priority and kind; the
  Brainstorm label is preset). On confirm, create the issue and upsert both
  documents. On decline, skip.
- If the repo is not configured, skip silently.

### 7.6 Edit: `nja-delegate-implementation`

When given a Linear issue identifier:

- The prompt file's "Context not in either document" names the issue
  identifier and URL.
- The execution protocol gains a step after the audit: post a comment
  listing what landed, the lint/build/test results and any audit finding
  still open. Only if lint, build and test are green and no BLOCKING finding
  remains, run `nja-linear.sh set-state <id> "In Review"`; otherwise the
  issue stays In Progress.

Without an identifier the template is unchanged.

## 8. Docs and version

- README: add the four skills to the table, a short "Linear" section with the
  two `.env` variables, and the script in the layout tree.
- Bump `plugin.json` and `marketplace.json` to 1.26.0.

## 9. Testing

- `nja/tests/test-linear.sh`, run by `nja/tests/run.sh`. Curl is replaced by
  a fake on `PATH` that records requests and returns canned responses. Covers
  at least: `.env` resolution (checkout, worktree fallback, missing key),
  key never appears in argv, state resolved by name, upsert-doc updates
  rather than duplicates, non-2xx and GraphQL `errors` both exit non-zero.
- `test-skills.sh` already validates skill frontmatter; the four new skills
  must pass it.
- One manual run against wyrdli's real workspace: setup, capture a throwaway
  issue, next, start it as Small up to the analysis comment, then Carlo
  deletes it.

## 10. Left to the builder

- Subcommand names and argument shapes.
- How the key reaches curl without appearing in argv.
- Exact wording of skill trigger descriptions.
- Pagination in list-open (the workspace is small; one page of 100 is
  acceptable if the script errors when there are more).
