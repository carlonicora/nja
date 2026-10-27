---
name: nja-writing-plan
description: Use when about to write an implementation plan in this project — typically right after brainstorming finishes a spec, or when the brainstorming flow asks if it should write the plan, or when the user asks for a plan. Wraps superpowers:writing-plans with nja-architecture compliance — it enforces inline citations to canonical examples, a structured self-audit before the plan is saved, skill-wins-over-plan in sub-agent dispatch, and an architecture audit step inside the final verification task.
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

   > "If the plan contradicts the nja-architecture skill, the skill wins. Flag the contradiction in your hand-off summary; do not silently follow either."

   The clause goes in every sub-agent brief, not just one.

---

## Before saving the plan

6. **Run a structured self-audit and include its output as a "Plan compliance check" section at the end of the plan.** The audit covers:

   - `references/anti-patterns.md` — walk it top to bottom. For each anti-pattern row, quote it and state which plan sections were checked. Do not paraphrase.
   - For every layer doc the plan touches: walk its "Common Mistakes" table the same way.
   - For every type signature in "Shared Contracts" / "Canonical names" / equivalents: cross-check against the relevant Decision Matrix. List each signature and the matrix row that authorizes it.
   - `references/date-handling.md` — if any plan field is a date or datetime, walk the lifecycle checklist (descriptor → DTO → repository → frontend interface → rehydrate → createJsonApi → custom Cypher casts) and confirm the plan honors each rule.
   - A row may say OK only by citing a skill section. "Precedent in existing code" or "documented in a code comment" is never a valid justification; a row that has nothing better is a violation or a question for the user (step 3).
   - If the audit surfaces a contradiction, fix the plan and re-run the audit — do not save a plan with known violations.

---

## Verification task in the plan

7. **The plan's final task (Task K or equivalent verification step) MUST run in this order:**

   a. `pnpm lint` (0 errors; pre-existing warnings OK; translation validator must say "All translation keys are valid")
   b. `pnpm build` (all packages green)
   c. `pnpm test` (no regressions)
   d. **Architecture audit of the diff by a fresh sub-agent.** Dispatch ONE fresh sub-agent (model: opus) that runs the `nja-verify` skill on the diff. Give it the repo root and the files that were already dirty before implementation, never the coordinator's reasoning. The coordinator fixes every BLOCKING finding, re-runs the affected spec files, and dispatches a NEW fresh auditor. Repeat until no BLOCKING finding remains, max 3 rounds; then report whatever remains. DEFENCE-IN-DEPTH and COSMETIC findings are reported, not fixed. The audit precedes hand-off back to the user.

   Run lint/build/test only ONCE — in this task — after all other implementation tasks are complete.

---

## Implementation execution model

8. **Run ALL implementation tasks in parallel** as independent sub-agents in a single message with multiple Agent tool calls. The "Shared Contracts" section (already skill-verified by step 4) is what makes parallelism safe; sub-agents must not invent contract variations. Implementers write the specs their task lists and run only those spec files (for example `npx vitest run <file>` inside the package); they never run repo-wide lint, build, or test.

9. **NO git commits at any point.** No `git add`, no `git commit`, no `git push` — not in any sub-agent, not between tasks, not at the end of Task K. The user commits after manual verification.

---

## Now invoke the plan writer

After absorbing the rules above, invoke `superpowers:writing-plans` to produce the plan body. Apply every rule above throughout — they are not advisory, they are the success criteria.

## Independent plan audit (after the plan is saved)

Your own self-audit (step 6) is not enough: you read the plan through the reasoning that wrote it. After the self-audit and before handing the plan back:

- Dispatch ONE fresh sub-agent (model: opus) that invokes the `nja-verify` skill in plan mode on the saved plan file. Give it only the plan path and the spec path, never your reasoning.
- Fix every BLOCKING finding in the plan, then dispatch a NEW fresh auditor. Repeat until clean, max 3 rounds.
- If BLOCKING findings remain after round 3, surface them to the user instead of declaring done.

When you hand the plan back to the user, prepend a one-sentence confirmation that the "Plan compliance check" section is present and clean and that the independent plan audit came back with no BLOCKING findings (say in which round). If either surfaced anything you could not resolve, surface it explicitly instead of declaring done.

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
