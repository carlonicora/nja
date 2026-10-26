---
name: nja-linear-start
description: Use when Carlo names a Linear issue to work on, or picks one from nja-linear-next. Moves it to In Progress, then either analyses and fixes it in this session (Small) or resumes the brainstorm, plan or delegate step from the documents already on the issue (Brainstorm). Triggers include "start WYR-12", "work on WYR-12", or a pick from nja-linear-next.
---

# Linear start

Take one issue from Todo to In Progress and drive it along its path.

All Linear calls go through `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh`
(below: "the script"), run from the repo. Never write GraphQL or curl yourself.
Exit codes: `0` ok, `1` usage, `2` not configured, `3` API error. Comment
bodies go to a temp file (`mktemp`) and are passed with `--body-file`.

Never commit, on either path.

## Steps

1. **Check.** Run `the script check`. Exit 2 or 3: show the script's message
   and stop. `"team": null`: tell Carlo to run `nja-linear-setup` and stop.
2. **Read the issue.** Run `the script get-issue <ID>` (any case works).
   Then state it in the conversation, exactly in this form, so the later
   skills can find it:

   `Linear issue: <IDENTIFIER> <url>`

3. **Label.** If `labels` has neither `Brainstorm` nor `Small`, ask Carlo
   which, then run `the script add-label <ID> <Brainstorm|Small>`.
4. **Move.** Run `the script set-state <ID> "In Progress"`.
5. **Branch** on the label: Small or Brainstorm, below.

## Small

1. **Analyse.** Read the code the description points at. If it is a bug,
   reproduce it, following the repo's own debugging rules (logs before
   theories). Then post a comment, `the script comment <ID> --body-file <f>`,
   with three sections:
   - `## Cause`
   - `## Files` — the files involved.
   - `## Intended fix`
2. **Is it still small?** If the analysis shows any of these:
   - more than one feature area,
   - a data-model change,
   - a decision that is Carlo's,

   **stop and ask**: switch to Brainstorm, or carry on as Small. Never switch
   silently. On Brainstorm, run `the script add-label <ID> Brainstorm`, then
   `the script remove-label <ID> Small`, and continue with the Brainstorm
   path below.
3. **Fix** in this session. Invoke `nja-architecture` before editing any file
   it governs. Run the spec that covers the change. If no spec covers it,
   write one that does, or, when the change cannot be tested by a spec, say
   so in the close-out comment and treat it as a failed check.
4. **Close out.**
   - Spec passes: `the script set-state <ID> "In Review"`, then comment the
     list of files changed. In Review means ready for Carlo to test.
   - Spec fails: leave the issue In Progress and comment the failure (the
     command and the failing output).
5. **Report**: what changed, the spec result, the issue state. No commit.

## Brainstorm

### Restore missing files first

Files on disk are the source of truth; the Linear documents are copies. Each
document's first line is `Source: <repo-relative path>`, then a blank line,
then the file's content. For each document on the issue:

- Read its `Source:` path.
- If that file is missing under the repo root, write the document body
  (everything after the first blank line) to that path, and tell Carlo which
  file was restored and from which document.
- If the file exists, leave it alone; the file wins.

### Resume

The documents decide the next step:

| `Spec` doc | `Plan` doc | Next step |
|---|---|---|
| no | no | brainstorm |
| yes | no | plan |
| yes | yes | delegate |

A `Plan` without a `Spec`: ask Carlo how to proceed.

- **Brainstorm.** Invoke `superpowers:brainstorming`. Give it the issue's
  title and description as the starting request, and this hand-off text:

  > After the design is approved, the plan step is `nja-writing-plan`, not
  > plain `superpowers:writing-plans`. Save the spec, but never commit it.
  > The Linear issue identifier is `<ID>`.

  Brainstorming does not return here; it chains into `nja-writing-plan`,
  which uploads the `Spec` and `Plan` documents.
- **Plan.** Invoke `nja-writing-plan` with the restored spec, telling it the
  Linear issue identifier is `<ID>`. It uploads `Spec` and `Plan` when the
  plan is saved. Then continue to delegate.
- **Delegate.** Invoke `nja-delegate-implementation` with the spec and plan
  paths and the Linear issue identifier and URL.
