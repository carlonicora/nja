---
name: nja-writing-plan
description: Use when about to write an implementation plan in this project — typically right after brainstorming finishes a spec, or when the brainstorming flow asks if it should write the plan, or when the user asks for a plan. Wraps superpowers:writing-plans with nja-architecture compliance — it enforces inline citations to canonical examples, a structured self-audit before the plan is saved, skill-wins-over-plan in sub-agent dispatch, and an architecture audit step inside the final verification task. Also reshapes the superpowers output into the nja execution contract (parallel tasks, no per-task review, no commits), adds a mandatory e2e task when a page changes in a repo with an e2e suite, and adds a spec review to the final verification task.
---

# Writing plans (nja)

This skill is the plan-writing wrapper for this project. It does NOT replace `superpowers:writing-plans` — it gates it with compliance rules. Follow every step below before producing any plan content. After the rules section, invoke `superpowers:writing-plans` to do the actual plan body.

---

## Before drafting any plan content

1. **Invoke the `nja-architecture` skill via the Skill tool.** Keep the layer reference docs the routing table points to open while drafting. The skill is the authority for every type signature, descriptor declaration, DTO shape, and code snippet that will land in the plan.

2. **Identify the layers the plan will touch** (backend entity / DTO / repository / service / controller / frontend interface / model / service / component) and read the matching reference doc(s) end-to-end. Do not skim. The Decision Matrices and "Common Mistakes" tables in those docs are the source of truth for the plan's contracts.

---

## While drafting the plan

3. **Cite canonical examples inline.** Every type signature, DTO shape, descriptor block, Cypher query template, controller route, or model method body included in the plan MUST carry an inline citation to a skill reference doc and section, in the form `(mirrors references/<layer>/<doc>.md § "<section>" canonical example)`. App or library code may be named only in addition to that citation (`also matches <path>`), never as the authority for a choice.

   - **Existing code is not precedent.** If code the plan wants to mirror breaks a rule in the skill, the plan follows the skill. If the skill documents an exception, cite that exception's section (for example `references/backend/03-repositories.md` § "Exception: cross-tenant administrative read repository"), and meet every requirement it lists.
   - **No canonical example in the skill?** STOP and ask the user. Record the answer in the plan as a decision, with who decided and the date. Never mark it OK yourself, and never invent.

4. **Treat "Shared Contracts" / "Canonical names" sections as skill-derived artifacts, not authored choices.** Every signature in those sections must come from the relevant Decision Matrix in the skill. If a draft signature contradicts the matrix, the matrix wins — rewrite the contract.

5. **Sub-agent dispatch instructions MUST include this clause verbatim:**

   > "If the plan contradicts the nja-architecture skill, follow the skill. List each contradiction in your hand-off summary: the plan line, the skill section, and what you did instead."

   The clause goes in every sub-agent brief, not just one.

---

## Before saving the plan

6. **Run a structured self-audit and include its output as a "Plan compliance check" section at the end of the plan.** The audit covers:

   - `references/anti-patterns.md` — walk it top to bottom. For each anti-pattern row, quote it and state which plan sections were checked. Do not paraphrase.
   - For every layer doc the plan touches: walk its "Common Mistakes" table the same way.
   - For every type signature in "Shared Contracts" / "Canonical names" / equivalents: cross-check against the relevant Decision Matrix. List each signature and the matrix row that authorizes it.
   - `references/date-handling.md` — if any plan field is a date or datetime, walk the lifecycle checklist (descriptor → DTO → repository → frontend interface → rehydrate → createJsonApi → custom Cypher casts) and confirm the plan honors each rule.
   - A row may say OK only by citing a skill section. "Precedent in existing code" or "documented in a code comment" is never a valid justification; a row that has nothing better is a violation or a question for the user (step 3).
   - Reshape (step 10): filled in after step 10 has run (this audit runs before the plan is saved, step 10 after superpowers saves it); one row confirming superpowers' `> **For agentic workers:**` header was replaced with the nja header, and one row confirming no task has a "Commit" step and the plan never says "frequent commits".
   - E2E task (step 11): one row confirming the e2e task is present, or stating why it is not applicable (the spec changes no page, route or rendered component, or the repo has no e2e suite).
   - If the audit surfaces a contradiction, fix the plan and re-run the audit — do not save a plan with known violations.

---

## Verification task in the plan

7. **The plan's final task (Task K or equivalent verification step) MUST run in this order:**

   a. `pnpm lint` (0 errors; pre-existing warnings OK; translation validator must say "All translation keys are valid")

   b. `pnpm build` (all packages green). Check for a running dev server first, as step 4 of the execution protocol written by nja-delegate-implementation describes.

   c. `pnpm test` (no regressions)

   d. **E2E run.** Only when the plan has an e2e task (step 11): run the repo's e2e runner once on that task's spec files, as the e2e task text in step 11 describes, before the reviews below.

   e. **Architecture audit of the diff by a fresh sub-agent.** The review phase is REVIEW ROUNDS, each with TWO fresh sub-agents dispatched in the same message: this architecture auditor and the spec reviewer in f. The auditor (model: opus) runs the `nja-verify` skill on the diff. Give it the repo root and the files that were already dirty before implementation, never the coordinator's reasoning. The review phase precedes hand-off back to the user.

      Each round dispatches a fresh nja-verify auditor AND a fresh spec reviewer in one message, so every round's fixes are re-checked by both. Fix every BLOCKING, MISSING and WRONG, re-run the affected spec files, then start the next round. Stop when no BLOCKING and no MISSING or WRONG remain, max 3 rounds; then report what remains. DEFENCE-IN-DEPTH, COSMETIC and EXTRA findings are reported, not fixed.

   f. **Spec review of the code by a second fresh sub-agent.** Dispatched in the same message as the auditor in e, every round. The spec reviewer (model: opus) checks the code against the spec. Give it only the spec path, the plan path, the repo root and the list of files already dirty before implementation; never the coordinator's reasoning. It lists every spec requirement as MET, MISSING or WRONG with `file:line` evidence, and lists EXTRA behaviour the spec did not ask for. Its findings are fixed in the REVIEW ROUNDS described in e.

   g. **Re-run after review fixes.** If any review round changed code, re-run lint → build → test once after the last round, plus the e2e runner on the e2e task's spec files when the plan has one. After fixing an e2e failure, re-run only the failing spec files.

   Run lint/build/test only ONCE — in this task — after all other implementation tasks are complete, plus the single re-run in g.

---

## Implementation execution model

8. **Run ALL implementation tasks in parallel** as independent sub-agents in a single message with multiple Agent tool calls. The "Shared Contracts" section (already skill-verified by step 4) is what makes parallelism safe; sub-agents must not invent contract variations. Implementers write the specs their task lists and run only those spec files (for example `npx vitest run <file>` inside the package); they never run repo-wide lint, build, or test. The e2e implementer (step 11) runs nothing. Implementer sub-agents run with `model: opus`.

9. **NO git commits at any point.** No `git add`, no `git commit`, no `git push`, no `git stash`, no branch, no worktree — not in any sub-agent, not between tasks, not at the end of Task K. The user commits after manual verification.

---

## Reshape the superpowers output

10. **Reshape the superpowers output.** After `superpowers:writing-plans` saves the plan, edit the saved plan file in three places:

    a. Replace superpowers' `> **For agentic workers:** REQUIRED SUB-SKILL: ...` header block with exactly this header:

       > **For agentic workers:** Execute this plan only through the execution protocol in the prompt file written by `nja-delegate-implementation`; the executing session never invokes that skill. Dispatch ALL implementation tasks in parallel, in one message. Implementers write and run the tests their task lists (the e2e implementer writes its specs and runs nothing), but there is NO review between tasks. ONE review phase runs after every task has landed, in the final verification task: the nja-verify audit and the spec review together. NO `git add`, `git commit`, `git push`, `git stash`, branch or worktree at any point. Do not invoke superpowers:subagent-driven-development, superpowers:executing-plans, superpowers:using-git-worktrees or superpowers:finishing-a-development-branch. Steps use checkbox (`- [ ]`) syntax for tracking.

    b. No task has a "Commit" step and the plan never says "frequent commits". Each task's test steps are: write the failing spec → run only that spec file and confirm it fails for the expected reason → implement → run only that spec file and confirm it passes. No commit step. Two tasks are exceptions to this failing-test-first shape: the e2e task (step 11), which writes its specs and runs nothing, and the final verification task (step 7).

    c. Do not present superpowers' "Execution Handoff" menu (Subagent-driven vs Native). The hand-back ends with: "Next: `nja-delegate-implementation`." When the Linear section ran, that line comes after the Linear line; if the Linear section already invoked `nja-delegate-implementation` (its step 3), report the prompt-file path instead. Do not start implementation in this session, even if an execution method was supplied earlier; the planning session stops at hand-back.

---

## E2E task in the plan

11. **E2E task.** When the spec changes a page, route or rendered component AND the repo has an e2e suite (`scripts/e2e.sh` and `apps/web/tests/README.md` exist; see `nja-e2e` § "Before anything: read the repo's own guide"; if none, skip this rule and say so in the plan), the plan MUST contain an e2e task. A plan that needs it and lacks it is incomplete. The e2e task follows this text:

    The plan fixes, before any code exists: the coverage entries as Given/When/Then with ids (next free ids from the repo's coverage document, following nja-e2e conventions), the seed data each entry needs, the visible labels exactly as the app renders them in its UI language, and the `data-testid` names every assertion needs. The test ids go in Shared Contracts so the task that owns the UI adds them. ONE implementer owns the e2e task: it writes the spec files, the seed additions and the not-yet-covered coverage entries, and runs nothing (no stack is up during the parallel round; an unrun e2e spec is expected, not a defect). The final verification task runs the repo's e2e runner once on those spec files, after the unit test run and before the reviews, plus the re-run after review fixes in the final verification task if a review round changed code. Each failure is triaged as code or test with evidence. A pre-existing e2e spec is never edited unless it also fails on clean HEAD. A spec written by the e2e task may be edited only when evidence (trace, screenshot, DOM) shows a test defect (wrong selector, label or seed); the edit never changes a Given/When/Then assertion, and a needed assertion change goes to the user. Report every test edit separately. Passing entries are marked covered following nja-e2e.

---

## Now invoke the plan writer

After absorbing the rules above, invoke `superpowers:writing-plans` to produce the plan body. Apply every rule above throughout — they are not advisory, they are the success criteria. Its Plan Document Header, per-task Commit steps and Execution Handoff menu are replaced by step 10 (Reshape the superpowers output).

## Independent plan audit (after the plan is saved)

Your own self-audit (step 6) is not enough: you read the plan through the reasoning that wrote it. After step 10 (reshape) has been applied and the self-audit's reshape rows are filled in, and before handing the plan back:

- Dispatch ONE fresh sub-agent (model: opus) that invokes the `nja-verify` skill in plan mode on the saved plan file. Give it only the plan path, the spec path and the repo root (it must judge whether the repo has an e2e suite), never your reasoning.
- Fix every BLOCKING finding in the plan, then dispatch a NEW fresh auditor. Repeat until clean, max 3 rounds.
- If BLOCKING findings remain after round 3, surface them to the user instead of declaring done.

When you hand the plan back to the user, prepend a one-sentence confirmation that the "Plan compliance check" section is present and clean and that the independent plan audit came back with no BLOCKING findings (say in which round), and that the reshape in step 10 was applied (nja header in place, no commit steps, no Execution Handoff menu). If either surfaced anything you could not resolve, surface it explicitly instead of declaring done.

## Linear (when configured)

After the independent plan audit is clean and before handing the plan back, sync the spec and plan to Linear. Run every command from the repo root.

1. **Check the repo.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh check`. Exit 2, or `"team": null` in the output, means the repo is not configured: skip this section silently and say nothing about Linear.
2. **Write the two documents.** For each of the spec and the plan, write a temp file under `${TMPDIR:-/tmp}` whose first line is `Source: <repo-relative path of the file>`, then a blank line, then the file's content verbatim.
3. **Issue identifier in context** (from `nja-linear-start` or `nja-linear-capture`): upload both documents to it.
   - `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh upsert-doc <ID> --title Spec --content-file <spec temp file>`
   - `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh upsert-doc <ID> --title Plan --content-file <plan temp file>`

   Then, **only if this session ran `nja-linear-start` on that issue**, hand off: invoke `nja-delegate-implementation` with the spec and plan paths and the Linear issue identifier and URL. Starting an issue takes it all the way to delegation. An issue that came from `nja-linear-capture` is queued work: upload, report, and stop.
4. **No identifier in context:** ask ONE question, the same draft-and-confirm question `nja-linear-capture` asks. Show:
   - **Title:** imperative, specific, under ~70 characters.
   - **Description:** markdown, drafted from the spec's intent section.
   - **Priority:** proposed, with a one-line reason (Linear's 1 urgent, 2 high, 3 medium, 4 low, 0 none).
   - **Kind:** `Bug`, `Feature` or `Improvement`, proposed.
   - **Label:** `Brainstorm`, preset.

   Ask whether to create the issue; Carlo confirms or edits in the same answer.
   - **Yes:** write the description to a temp file, run `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh create-issue --title "<title>" --description-file <file> --priority <N> --label <kind> --label Brainstorm`, then run both `upsert-doc` commands from step 3 against the new identifier.
   - **No:** skip.
5. **Report** the identifier and URL in one line of the hand-back. If any command exits 3, quote its stderr sentence in the hand-back instead; the plan itself is still done.
