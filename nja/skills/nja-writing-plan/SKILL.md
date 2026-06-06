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

3. **Cite canonical examples inline.** Every type signature, DTO shape, descriptor block, Cypher query template, controller route, or model method body included in the plan MUST carry an inline citation in the form `(mirrors references/<layer>/<doc>.md § "<section>" canonical example)`. If you cannot find a canonical example for something the plan needs, STOP and ask the user — do not invent.

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
   - If the audit surfaces a contradiction, fix the plan and re-run the audit — do not save a plan with known violations.

---

## Verification task in the plan

7. **The plan's final task (Task K or equivalent verification step) MUST run in this order:**

   a. `pnpm lint` (0 errors; pre-existing warnings OK; translation validator must say "All translation keys are valid")
   b. `pnpm build` (all packages green)
   c. `pnpm test` (no regressions)
   d. **Architecture audit of the diff against the skill, with findings reported.** Compute scope from `git status --short`. For each scope file, match the routing table to its reference doc(s) and check the diff against the rules. Output severity (BLOCKING / DEFENCE-IN-DEPTH / COSMETIC), file:line, verbatim code, and the rule cited by skill-doc-path + section. The audit precedes hand-off back to the user.

   Run lint/build/test only ONCE — in this task — after all other implementation tasks are complete.

---

## Implementation execution model

8. **Run ALL implementation tasks in parallel** as independent sub-agents in a single message with multiple Agent tool calls. The "Shared Contracts" section (already skill-verified by step 4) is what makes parallelism safe; sub-agents must not invent contract variations.

9. **NO git commits at any point.** No `git add`, no `git commit`, no `git push` — not in any sub-agent, not between tasks, not at the end of Task K. The user commits after manual verification.

---

## Now invoke the plan writer

After absorbing the rules above, invoke `superpowers:writing-plans` to produce the plan body. Apply every rule above throughout — they are not advisory, they are the success criteria.

When you hand the plan back to the user, prepend a one-sentence confirmation that the "Plan compliance check" section is present and clean. If the audit surfaced anything you could not resolve, surface it explicitly instead of declaring done.
