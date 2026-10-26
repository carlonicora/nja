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
3. **Project commands** — read the root `package.json` scripts for the repo's real lint/build/test commands. Resolve `<api-app>`-style placeholders to actual workspace names.
4. **Linear issue** — only if a Linear issue identifier is in context (for example passed by `nja-linear-start`): its identifier and URL, plus the script's absolute path, `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh` expanded now and confirmed to exist. The fresh session may not have `CLAUDE_PLUGIN_ROOT` pointing at the same checkout. No identifier in context → skip this item; the Linear parts of the template are left out.

## Step 2 — Write the file

Save to the OS temp dir, never the workspace: `${TMPDIR:-/tmp}/nja-implement-<feature-slug>-<YYYY-MM-DD>.md`

The file has exactly these five sections, in this order:

| Section | Contains |
|---|---|
| Title | `# Implement: <feature>` |
| Read first | `@`-links to the spec and plan, absolute paths |
| Context not in either document | Session decisions · repo state · project commands · Linear issue (when one is in context) |
| Execution protocol | The six steps (seven with a Linear issue), verbatim from the template below |
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

<Include the Linear issue block only when Step 1 item 4 found an identifier.>
**Linear issue**
- Issue: `<identifier>` — <URL>
- Script: `<absolute path to nja-linear.sh>`
- Before step 1, run `<script> set-state <identifier> "In Progress"` from the
  repo root, so the issue shows as being worked on.

## Execution protocol — follow exactly

1. **Invoke the `nja-architecture` skill.** Read every layer reference doc the
   plan's tasks touch, end to end, before dispatching anything.

2. **Dispatch ALL implementation tasks in parallel** — one Agent call per task,
   all in a single message. The plan's final verification task is NOT one of
   them: steps 4–5 below are that task, and you run them yourself once the
   implementation has landed. Every other task is dispatched.

   Give each sub-agent its task section plus the plan's Shared Contracts
   verbatim, and this clause verbatim:

   > "If the plan contradicts the nja-architecture skill, the skill wins. Flag
   > the contradiction in your hand-off summary; do not silently follow either."

3. **Sub-agents write the specs their task lists and run only those spec
   files** (for example `npx vitest run <file>` inside the package). They never
   run repo-wide lint, build, or test.

4. **After every task has landed, run once, in order:** lint → build → test
   (commands above). Lint must reach 0 errors; pre-existing warnings are fine.
   Fix any failures yourself and re-run — do not re-dispatch a sub-agent for
   them. The sub-agents never ran lint, build, or the full test suite, so a
   failure here is yours to resolve.

5. **Audit with a fresh sub-agent, never in your own context.** Dispatch ONE
   fresh sub-agent (model: opus) to run the `nja-verify` skill on the diff.
   Give it only the repo root and the "Uncommitted at delegation time" list
   above to exclude; never your own reasoning about the code. Fix every
   BLOCKING finding yourself, re-run the affected spec files, then dispatch a
   NEW fresh auditor. Repeat until no BLOCKING finding remains, max 3 rounds;
   after that, report whatever remains. DEFENCE-IN-DEPTH and COSMETIC findings
   are reported, not fixed.

6. **Make no git commits at any point** — no `git add`, no `git commit`, no
   `git push`, not in any sub-agent, not at the end. The user commits after
   verifying manually.

<Include step 7 only when Step 1 item 4 found an identifier.>
7. **Update the Linear issue** after step 5, from the repo root. Write a
   comment to a temp file under `${TMPDIR:-/tmp}` listing the tasks that
   landed, the lint/build/test results, and every audit finding still open,
   then run `<absolute path to nja-linear.sh> comment <identifier> --body-file <file>`.
   Then, only if lint, build and test are green and no BLOCKING finding
   remains, run `<absolute path to nja-linear.sh> set-state <identifier> "In Review"`.
   Otherwise leave the issue In Progress.

## Report back

State: which tasks landed, the lint/build/test results, how many audit rounds
ran in step 5, the final auditor's findings in full (including its severity
summary table and any BLOCKING finding still open after round 3), and
anything you flagged in step 2 as a plan/skill contradiction.
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
| Softening the protocol to "prefer parallel" or "generally avoid commits" | The six steps (seven with a Linear issue) are the contract the plan was written against. Reproduce them verbatim. |
| Letting the coordinator run `nja-verify` in its own context, or only report its findings | The session that wrote the code reads the diff through its own reasoning and misses what it already rationalised. A fresh auditor per round sees only the diff; the coordinator fixes every BLOCKING finding before reporting. |
| Implementing part of the plan "while you're here" | This skill produces a file. A delegated plan runs in the delegated session, on a clean starting diff. |
