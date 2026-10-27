---
name: nja-verify
description: Use when auditing uncommitted changes for architecture compliance — before committing, before handing work back to the user, after generating or implementing a module, or whenever asked to verify/audit/review a diff against the nestjs-neo4jsonapi + nextjs-jsonapi architecture rules. Also audits a saved implementation plan in plan mode (as nja-writing-plan requires before hand-back). Runs a read-only audit of the uncommitted files, or of the plan file, against the nja-architecture skill and reports each violation with file:line evidence, the rule it breaks and a severity, without fixing anything. Plan mode also checks the nja-writing-plan execution contract (the nja header, no commit steps, the e2e task, the spec review).
---

# Architecture audit

Audit a working tree's uncommitted changes against the architecture rules. This is a read-only review pass: it finds violations and cites them with evidence. It does NOT fix them.

## Core principle

**The `nja-architecture` skill is the ONLY source of truth for rules.** Do not cite rules from memory, from `CLAUDE.md`, or from prior conversation — cite them by skill-doc path + section. If a rule is not in the skill, it is not a rule for this audit. The one exception is plan mode, which also enforces the `nja-writing-plan` execution contract (see "Plan mode").

## Scope

Audit the changes introduced in the working tree that have **not been committed yet**. Compute the scope-introduced file list FIRST, before reading any rule, via:

```bash
git status --short
```

Audit ONLY these files. Anything outside this list is pre-existing — flag it separately, do not block on it.

If the caller hands you a list of files that were already dirty before the work started, exclude them from the scope too.

## Plan mode

Use plan mode when the caller hands you a plan file (and its spec) instead of asking about the working tree. The scope is the plan file, not `git status`. The method, the output format and the hands-off rule are the same; locations are plan-file line numbers (`plan.md:123`).

Audit:

- every code snippet in the plan (type signatures, DTOs, descriptors, Cypher, controller routes, model methods) against the layer reference docs, exactly as if it were code in scope;
- the "Shared Contracts" / "Canonical names" sections against the relevant Decision Matrix;
- every recorded decision: it must cite a skill section, or say who decided and when;
- the "Plan compliance check" section, row by row.

Flag as BLOCKING:

- any choice justified by pointing at existing app or library code instead of a skill section ("mirrors `apps/...`", "same as the existing X repository");
- any "OK" or "exception" in the compliance check that is not backed by a skill section. "Precedent in existing code" and "documented in a code comment" are not backing;
- a cited exception (for example `references/backend/03-repositories.md` § "Exception: cross-tenant administrative read repository") whose requirements the plan does not meet in full.

The items below come from the execution contract in the `nja-writing-plan` skill (`SKILL.md` § "Implementation execution model", § "Reshape the superpowers output", § "E2E task in the plan" and § "Verification task in the plan"), not from `nja-architecture`. They are the one stated exception to the core principle. Also flag as BLOCKING, in plan mode only, the items below. Read `${CLAUDE_PLUGIN_ROOT}/skills/nja-writing-plan/SKILL.md` and quote the matching section verbatim as the rule:

- a plan header that names `superpowers:subagent-driven-development` or `superpowers:executing-plans` as a REQUIRED SUB-SKILL, or tells the executor to run the plan "task-by-task";
- any step that runs `git add`, `git commit`, `git push`, `git stash`, or creates a branch or worktree, or a "Commit" step in any task;
- any plan text that offers an execution-method choice (Subagent-driven vs Native/Inline) or a REQUIRED SUB-SKILL line;
- a plan with no nja `For agentic workers` header (`nja-writing-plan` step 10a);
- a spec that changes a page, route or rendered component, in a repo that has an e2e suite, with no e2e task in the plan. The plan may instead state explicitly that the repo has no e2e suite. The repo has an e2e suite when `scripts/e2e.sh` and `apps/web/tests/README.md` exist in the repo root the caller passes. If no repo root was passed, report the e2e check as not verifiable rather than guessing;
- a final verification task with no spec-review step (a fresh sub-agent checking the code against the spec), or one where the nja-verify audit and the spec review loop separately instead of running together each round.

Read the spec only to understand intent. Do not audit the spec.

## Method (non-negotiable)

1. **Invoke the `nja-architecture` skill via the Skill tool.** Read the full routing table AND every layer-reference doc relevant to the files in scope. Match each scope file against the routing table; read the reference(s) it points to before judging that file.

2. **Compute the scope file list first** (the `git status --short` above). Pre-existing code outside the list is noted, never blocking.

3. **Do not rationalize.** If a scope file matches a pattern listed in `references/anti-patterns.md`, it is a violation — even if sibling files in the same directory do the same thing. **Pre-existing wrongness is not precedent.**

4. **Evidence per claim.** Every flagged violation cites `file_path:line_number` + verbatim code + the exact rule it breaks (skill-doc path + line/section). Every "compliant" claim cites the skill-doc's canonical example by `file:line` it follows. A claim without evidence does not go in the report.

## Output format

For each violation:

- **Severity:** BLOCKING (`references/anti-patterns.md` or a layer doc explicitly forbids it, or, in plan mode, a `nja-writing-plan` execution-contract section forbids it) / DEFENCE-IN-DEPTH / COSMETIC
- **Location:** `file:line` + verbatim code
- **Rule:** skill-doc path + section, verbatim quote
- **Fix:** the exact replacement code, with `file:line` of the canonical skill example it mirrors

End with a summary table:

| Metric | Count |
|---|---|
| Scope-introduced files audited | … |
| BLOCKING violations | … |
| DEFENCE-IN-DEPTH violations | … |
| COSMETIC violations | … |
| Pre-existing violations noted (not blocking) | … |

## Hands-off

**Do not fix anything during this pass. Audit only.** The user decides what to fix and in what order. Proposing the fix code in the report is required; applying it is not — that is a separate, user-authorized step.

## Failure modes — STOP if you catch yourself doing any of these

| Failure mode | Why it's wrong |
|---|---|
| "The sibling files do this too, so it's fine." | Pre-existing wrongness is not precedent. Each scope file is judged against the skill, not its neighbours. |
| "I know this rule, I'll cite it from memory / CLAUDE.md." | The `nja-architecture` skill is the only authority (plan mode adds the `nja-writing-plan` execution contract). Cite by skill-doc path + section, or don't claim it. |
| "This is close enough to compliant." | Either it matches a canonical example (cite it) or it's a violation. There is no "close enough." |
| "I'll just fix this one while I'm here." | This pass is hands-off. Report the fix; let the user decide. Fixing mid-audit hides what was wrong. |
| "The plan says this mirrors existing code, so it is fine." | Existing code is not precedent. A plan choice stands only on a skill section. |
| "Let me audit the whole repo to be thorough." | Scope is uncommitted changes only. Pre-existing issues are noted separately, never blocking. |
| "No line number handy, the file is enough." | Evidence requires `file:line` + verbatim code. A claim without it is not reportable. |
