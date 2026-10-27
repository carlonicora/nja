---
name: nja-delegate-implementation
description: Use when an implementation plan exists and the work should run in a fresh session — the user asks to delegate the implementation, hand the plan to another session or agent, or produce a prompt file to run the plan elsewhere. Typically the step right after nja-writing-plan. Writes one temporary markdown prompt file that @-links the spec and plan and carries the session context a fresh session needs to execute the plan.
---

# Delegate implementation (nja)

Produce ONE temporary markdown file that **is the prompt** a fresh session runs to execute an existing plan. The user links that file into a new session with `@<path>`.

This skill writes a file. It does not implement the plan, touch the feature code, run lint/build/test, or commit.

## Core principle

**The file carries context, not content.** The spec and plan already exist on disk and are `@`-referenced, so their prose is never copied — copies drift the moment either document is edited. Everything the fresh session needs that it *cannot* recover from disk goes in the file.

The test for every line you write: **if this conversation vanished, could the new session still implement correctly?** If a line fails that test, it doesn't belong. If something that passes it is missing, the file is incomplete.

## Step 1 — Collect

Resolve items 1–3 before writing anything, and item 4 when it applies:

1. **Spec and plan absolute paths.** Both must exist on disk. If either is missing, ambiguous, or you'd be guessing — STOP and ask the user. Never invent a path; a broken `@`-reference silently gives the fresh session nothing.
2. **Repo state** — `git rev-parse --show-toplevel` (the repo root — the fresh
   session starts in whatever directory it starts in and cannot infer this),
   `git rev-parse --abbrev-ref HEAD`, and `git status --short`.
3. **Project commands** — read the root `package.json` scripts for the repo's real lint/build/test commands, and the e2e runner (`scripts/e2e.sh`) when it exists. Resolve `<api-app>`-style placeholders to actual workspace names.
4. **Linear issue** — only if a Linear issue identifier is in context (for example passed by `nja-linear-start`): its identifier and URL, plus the script's absolute path, `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh` expanded now and confirmed to exist. The fresh session may not have `CLAUDE_PLUGIN_ROOT` pointing at the same checkout. No identifier in context → skip this item; the Linear parts of the template are left out.

## Step 2 — Write the file

Save to the OS temp dir, never the workspace: `${TMPDIR:-/tmp}/nja-implement-<feature-slug>-<YYYY-MM-DD>.md`

The file has exactly these five sections, in this order:

| Section | Contains |
|---|---|
| Title | `# Implement: <feature>` |
| Read first | `@`-links to the spec and plan, absolute paths |
| Context not in either document | Session decisions · repo state · project commands · Linear issue (when one is in context) |
| Execution protocol | The seven steps, 0–6 (eight with a Linear issue), verbatim from the template below |
| Report back | What the fresh session returns to the user |

### Template

````markdown
# Implement: <feature>

Read these in full before any other action:

- Spec: @<absolute path to spec>
- Plan: @<absolute path to plan>

## Context not in either document

**Session decisions**
<Decisions, rejected alternatives, and clarifications from the conversation
that produced the plan but never landed in the spec or plan. If there are
none, write "None — the spec and plan are complete." Do not pad this.>

**Repo state**
- Repo root: `<absolute path>` — work here. If your working directory is
  somewhere else, `cd` here first; if this path doesn't exist on your machine,
  STOP and ask the user rather than implementing into the wrong repo.
- Branch: `<branch>`
- Uncommitted at delegation time:
  ```
  <git status --short output, or "clean">
  ```
  Anything listed above was already dirty before you started — exclude it
  from your own diff when auditing in step 5.

**Project commands**
- Lint: `<resolved command>`
- Build: `<resolved command>`
- Test: `<resolved command>`
- E2E: `<resolved command>` (omit if the repo has no e2e suite)

<Include the Linear issue block only when Step 1 item 4 found an identifier. Delete this marker line.>

**Linear issue**
- Issue: `<identifier>` — <URL>
- Script: `<absolute path to nja-linear.sh>`
- Before step 1, run `<script> set-state <identifier> "In Progress"` from the
  repo root, so the issue shows as being worked on.

## Execution protocol — follow exactly

0. **This protocol is the execution contract and supersedes the plan.** Invoke
   the user's personal mode skill (a `<handle>-mode` skill written by
   `nja-automate-me`) if one is installed. Ignore the plan's "For agentic
   workers" header if it tells you to use a superpowers execution skill, every
   "Commit" step, any "REQUIRED SUB-SKILL" line and any execution-method menu.
   Do not invoke `superpowers:subagent-driven-development`,
   `superpowers:executing-plans`, `superpowers:using-git-worktrees` or
   `superpowers:finishing-a-development-branch`. Never invoke
   `nja-delegate-implementation` from this session; you are the session it
   delegated to. Stay on the current branch in the repo root.

1. **Invoke the `nja-architecture` skill.** Read every layer reference doc the
   plan's tasks touch, end to end, before dispatching anything.

2. **Dispatch ALL implementation tasks in parallel** — one Agent call per task,
   all in a single message, each with `model: opus`. The plan's final
   verification task is NOT one of them: you run it yourself after everything
   lands, in the plan's order, with steps 4–5 below as its lint/build/test, e2e
   run and review parts. Any other steps it lists (package rebuilds, a
   real-app run) are kept. Every other task is dispatched.

   Give each sub-agent its task section plus the plan's Shared Contracts
   verbatim, and this clause verbatim:

   > "If the plan contradicts the nja-architecture skill, follow the skill.
   > List each contradiction in your hand-off summary: the plan line, the skill
   > section, and what you did instead."

3. **Sub-agents write the specs their task lists and run only those spec
   files** (for example `npx vitest run <file>` inside the package). Each task
   follows this shape: write the failing spec → run only that spec file and
   confirm it fails for the expected reason → implement → run only that spec
   file and confirm it passes. No commit step. Sub-agents never dispatch a
   reviewer, and never run repo-wide lint, build, test, typecheck or the e2e
   runner. If a sub-agent loads `superpowers:test-driven-development`, it
   follows its red/green steps but not its "run the project's suite" rule; the
   suite runs once, in step 4. If the plan has an e2e task, its sub-agent
   writes the specs and runs nothing.

4. **After every task has landed, run once, in order:** lint → build → test
   (commands above). Before build, check whether a dev server is serving this
   checkout: look up the web and api ports in the repo's root `.env` (if they
   can't be found there, ask the user). For each port run
   `lsof -tiTCP:<port> -sTCP:LISTEN`; if it prints a PID, run
   `lsof -a -p <pid> -d cwd`. STOP and ask the user before running build only
   when that cwd is inside this repo root, because a build clobbers a running
   dev server's build output; a dev server from another checkout does not share
   this build output. Lint must reach 0 errors; pre-existing warnings are
   fine. Fix any failures yourself and re-run — do not re-dispatch a sub-agent
   for them. The sub-agents never ran lint, build, or the full test suite, so a
   failure here is yours to resolve.

   Then, if the plan has an e2e task, run the repo's e2e runner once on the e2e
   task's spec files, after the unit test run and before the reviews. Triage
   each failure as code or test with evidence. A pre-existing e2e spec is never
   edited unless it also fails on clean HEAD. A spec written by the e2e task
   may be edited only when evidence (trace, screenshot, DOM) shows a test
   defect (wrong selector, label or seed); the edit never changes a
   Given/When/Then assertion, and a needed assertion change goes to the user.
   Report every test edit separately. Mark passing entries covered following
   `nja-e2e`.

5. **Review with fresh sub-agents, never in your own context.** Two reviewers,
   both model: opus:

   - **Auditor** — runs the `nja-verify` skill on the diff. Give it only the
     repo root and the "Uncommitted at delegation time" list above to exclude;
     never your own reasoning about the code.
   - **Spec reviewer** — checks the code against the spec. Give it only the
     spec path, the plan path, the repo root and the "Uncommitted at
     delegation time" list; never your own reasoning. It lists every spec
     requirement as MET, MISSING or WRONG with `file:line` evidence, and lists
     EXTRA behaviour the spec did not ask for.

   Each round dispatches a fresh nja-verify auditor AND a fresh spec reviewer
   in one message, so every round's fixes are re-checked by both. Fix every
   BLOCKING, MISSING and WRONG, re-run the affected spec files, then start the
   next round. Stop when no BLOCKING and no MISSING or WRONG remain, max 3
   rounds; then report what remains. DEFENCE-IN-DEPTH, COSMETIC and EXTRA
   findings are reported, not fixed.

   If any review round changed code, re-run lint → build → test once (with the same dev-server check before build) after the
   last round, plus the e2e runner on the e2e task's spec files when the plan
   has one. After fixing an e2e failure, re-run only the failing spec files.

6. **Make no git commits at any point** — no `git add`, no `git commit`, no
   `git push`, no `git stash`, no branch, no worktree, not in any sub-agent,
   not at the end. The user commits after verifying manually.

<Include step 7 only when Step 1 item 4 found an identifier. Delete this marker line.>

7. **Update the Linear issue** after step 5, from the repo root. Write a
   comment to a temp file under `${TMPDIR:-/tmp}` listing the tasks that
   landed, the lint/build/test and e2e results, and every audit and
   spec-review finding still open, then run
   `<absolute path to nja-linear.sh> comment <identifier> --body-file <file>`.
   Then, only if lint, build, test and the e2e run (when the plan has one) are
   green, no BLOCKING finding remains and no spec-review MISSING or WRONG
   remains, run `<absolute path to nja-linear.sh> set-state <identifier> "In Review"`.
   Otherwise leave the issue In Progress.

## Report back

State: which tasks landed, the lint/build/test results, the e2e run result
from step 4 (if the plan has an e2e task, including any test edits, listed
separately), how many review rounds ran in step 5 (each round ran both
reviewers), the final auditor's findings in full (including its severity
summary table and any BLOCKING finding still open after round 3), the final
spec reviewer's MET/MISSING/WRONG/EXTRA list, the results of the post-review
lint/build/test and e2e re-run (or that none was needed because no round
changed code), and anything you flagged in step 2 as a plan/skill
contradiction.
Then stop — the work stays uncommitted for the user to review.
````

## Step 3 — Hand back

Report the absolute path, then one line telling the user to paste `@<path>` into a fresh session. Do not summarise the plan back to them — they just wrote it.

## Common mistakes

| Mistake | Why it's wrong |
|---|---|
| Copying the plan's tasks into the file | The plan is `@`-linked and authoritative. A copy drifts the moment the plan changes, and the fresh session then has two disagreeing sources. |
| `@`-linking a path you didn't verify exists | The reference silently expands to nothing. The session implements from context it doesn't have. |
| Writing the file into the workspace | It's a throwaway prompt, not a project artifact. Temp dir only. |
| Omitting the repo root path | The fresh session starts in an arbitrary directory and cannot infer which repo the plan targets. Without the root it will happily implement into the wrong one. |
| Leaving `<api-app>` / `pnpm <filter>` placeholders in the commands | Step 4 has to be copy-pasteable. The fresh session cannot resolve placeholders it has no context for. |
| Padding "Session decisions" with restated spec content | The section exists for what dies with the conversation. "None" is a valid and common answer. |
| Softening the protocol to "prefer parallel" or "generally avoid commits" | The seven steps, 0–6 (eight with a Linear issue), are the contract the plan was written against. Reproduce them verbatim. |
| Omitting step 0, or softening it | The plan's header and commit steps are the most recent instructions the fresh session reads; without an explicit override it loads subagent-driven-development, runs tasks one by one, reviews each and commits. |
| Dropping the extra steps in the plan's final verification task | Steps 4–5 cover only its lint/build/test, e2e run and review parts. Package rebuilds and a real-app run it lists still have to run, in the plan's order, or the work is handed back unverified. |
| Letting the coordinator run `nja-verify` in its own context, or only report its findings | The session that wrote the code reads the diff through its own reasoning and misses what it already rationalised. A fresh auditor per round sees only the diff; the coordinator fixes every BLOCKING finding before reporting. |
| Running the auditor and the spec reviewer as separate loops | A fix made for one reviewer is never re-checked by the other. Each round dispatches both, fresh, in one message. |
| Implementing part of the plan "while you're here" | This skill produces a file. A delegated plan runs in the delegated session, on a clean starting diff. |
