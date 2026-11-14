---
name: nja-verify
description: Use when auditing uncommitted changes for architecture compliance — before committing, before handing work back to the user, after generating or implementing a module, or whenever asked to verify/audit/review a diff against the nestjs-neo4jsonapi + nextjs-jsonapi architecture rules. Also audits a saved implementation plan in plan mode (as nja-writing-plan requires before hand-back): one auditor on a lookup budget that checks only what the implementation's test run will not catch (steps that leave a choice open, spec requirements no task builds, decisions only the user can make, changes elsewhere no test watches), or one named slice for a recheck. Read-only: reports every finding with file:line evidence, the rule and a class, plus a coverage table, without fixing anything.
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

Use plan mode when the caller hands you a plan file (and its spec) instead of asking about the working tree. The scope is the plan file, not `git status`. The hands-off rule is the same; locations are plan-file line numbers (`plan.md:123`).

### One auditor by default

With no focus named, you are the only auditor of this plan. Cover, in this order: the paraphrase and `spec` checks, then `tasks`, then `reach`, then `architecture` (the four sections below), for every task.

A focus narrows you:

- **`part: <task numbers>`** — the caller splits the plan between two auditors. Run the full order above, but only for these tasks. Of the `spec` section, check the requirements these tasks build; the paraphrase and "a spec requirement no task builds" belong to the auditor whose focus says `part: <task numbers> + plan`.
- **`tasks: <task numbers>`** — a recheck of the tasks a fix changed: those tasks' steps against the code as it is today.
- **`reach: <task numbers>`**, **`architecture`**, **`spec`** — one section below each.

### Budget

Every request re-sends your whole context, so each lookup costs more than the one before. Use about 40 lookups (tool calls) for a full audit or a `part`, and about 15 for any other focus. Spend them in the order above. When the budget runs out, stop, and mark what you did not check as "not checked" in the coverage table. Never mark a row OK without having opened the code for it.

### Out of scope: what the test run will catch

The implementing session runs lint, build and the full unit test suite, and fixes what fails. A unit spec that breaks, a mock missing an export, a type error, a wrong import: those surface there for the price of one run. Do not hunt for them. Look for what that run will NOT catch: a choice the plan leaves open, a spec requirement no task builds, a decision only the user can make, a change elsewhere that no test watches, an existing test file a step would silently overwrite. Something test-catchable you notice anyway: one COSMETIC line with the file.

### Report every finding you see

No ranking that drops the tail, no "lower priority, a careful builder would manage". If it would make the implementer guess, or ship a change nobody asked for, it goes in. End with the coverage table, one row per task step, spec requirement and changed item, saying OK, a finding, or "not checked".

### Reference docs

Read the `nja-architecture` SKILL.md and `references/anti-patterns.md`. Open a layer reference doc only for a code snippet whose correctness depends on it.

### Mechanical checks are already done

The caller ran `${CLAUDE_PLUGIN_ROOT}/scripts/nja-plan-check.sh <plan> <repo-root>` and fixed what it reported: the nja header, git and Commit steps, the execution menu, Create / Modify / Delete markers, and whether every listed Create / Modify / Delete path exists or not. Do not re-check those. With no focus named and no script output handed to you, run the script yourself and include its output.

These checks come from the `nja-writing-plan` execution contract, not from `nja-architecture`; they are the one stated exception to the core principle. When you report one, read `${CLAUDE_PLUGIN_ROOT}/skills/nja-writing-plan/SKILL.md` and quote the matching section verbatim as the rule.

### Focus `tasks`

For each task in your list, read the task, the Shared Contracts it uses, and every existing file it modifies or depends on. Then carry out the task in your head, step by step, against the code as it is today:

- **Every step is decided.** Ask: do I know exactly what to write, in which file, and how? A step that names no file or symbol ("update the account service"), or needs a choice the plan does not make (a signature, a relationship, an error-handling approach, a field type, a default), is a finding. Report the missing choice.
- **Every claim about the code holds.** Every file, function, endpoint, descriptor, relationship, line reference and statement about current behaviour in the step: check it under the repo root (Grep or Read, never from memory). Missing or contradicted is a finding. Paths the plan will `Create` are not findings.
- **No test file is silently overwritten.** A step that creates a spec file that already exists, or rewrites one, drops the tests in it with nothing failing. That is a finding.
- **The e2e task** (when it is in your list): every visible label matches the app's message files in its UI language, every `data-testid` is in Shared Contracts and owned by a task, and the seed data gives every Given what it needs.

Coverage table: one row per step, `Task N · Step M | files and symbols opened | result`.

### Focus `reach`

For each task, list what it changes (fields, defaults, routes, labels, behaviour), then look outward for what no test will flag:

- **Silent behaviour changes elsewhere.** Code that walks every entity, descriptor, field, route or registry entry without naming yours, and will now include, show or treat the change differently: exports, AI tool catalogs, search indexes, sync and clone scope lists, offline route tables, serialisers to other roles. Grep for the collection being walked. When the spec says nothing about whether that consumer should pick up the change, it is NEEDS-CARLO; when the spec forbids it, BLOCKING · recheck.
- **Existing e2e specs.** The final verification runs only the e2e task's own specs, so grep the repo's e2e folder for the routes, labels and test ids the task changes. Each one no task updates is a finding.
- **Other tasks.** What this task needs from another task that runs at the same time, and what it changes that another task's steps assume unchanged.

### Focus `architecture`

- every code snippet in the plan (type signatures, DTOs, descriptors, Cypher, controller routes, model methods) against the layer reference docs, exactly as if it were code in scope;
- the "Shared Contracts" / "Canonical names" sections against the relevant Decision Matrix;
- every recorded decision: it must cite a skill section, or say who decided and when;

Findings:

- any choice justified by pointing at existing app or library code instead of a skill section ("mirrors `apps/...`", "same as the existing X repository");
- a cited exception (for example `references/backend/03-repositories.md` § "Exception: cross-tenant administrative read repository") whose requirements the plan does not meet in full.

Coverage table: one row per snippet, contract and recorded decision, `plan.md:<line> | rule checked | result`.

### Focus `spec`

**Paraphrase first, before you open the spec.** Read the plan alone and write two sections in your own words, 2-5 sentences each: **What this plan builds** and **How the existing code works, per this plan**. They open the report. The caller compares them with the spec, so a wrong paraphrase is a finding even when every rule passes. Only after writing both sections, read the spec.

Then:

- **Every spec requirement is planned.** List each requirement and the task(s) that build it. One no task builds is a finding.
- **Nothing extra.** List what the plan builds that the spec does not ask for. It is a finding when it changes behaviour the spec states; otherwise list it as EXTRA.
- **The tasks connect.** A task you cannot paraphrase, a contract one task produces and no task consumes, or a step that relies on something no task creates, is a finding.
- **The execution contract, where it needs judgment:**
  - a spec that changes a page, route or rendered component, in a repo with an e2e suite (`scripts/e2e.sh` and `apps/web/tests/README.md` exist under the repo root the caller passes), with no e2e task. The plan may instead state that the repo has no e2e suite. With no repo root passed, report this as not verifiable;
  - a final verification task with no spec-review step (a fresh sub-agent checking the code against the spec), or one where the nja-verify audit and the spec review loop separately instead of running together each round.

Coverage table: one row per spec requirement, `spec.md:<line> requirement | task(s) | result`.

### Finding classes

Each plan-mode finding carries one class. The class tells the caller what to do with it:

- **BLOCKING · recheck** — a design defect: fixing it changes what a task does (a missing choice, a claim about the code that changes the approach, a broken test harness, an unhandled caller, a spec requirement no task builds, tasks that do not connect, a wrong paraphrase). The caller fixes it, then the changed task is audited again.
- **BLOCKING · fix-only** — the fix is local and cannot change any other step: a misspelt path, a Create that should be Modify, a citation that points at code where a skill section backs the same choice (name the section), wording. The caller fixes it with no new audit.
- **NEEDS-CARLO** — only the user can decide: an exception to a rule, a deviation from the spec, a choice the skill has no canonical example for (`nja-writing-plan` step 3). The caller asks; it does not decide.
- **DEFENCE-IN-DEPTH** / **COSMETIC** — reported, not fixed.

When unsure between recheck and fix-only, choose recheck.

Read the spec only to understand intent (focus `spec` reads it to check coverage). Do not audit the spec.

## Method (non-negotiable)

1. **Invoke the `nja-architecture` skill via the Skill tool.** Read the full routing table AND every layer-reference doc relevant to the files in scope. (Plan mode: see § "Reference docs".) Match each scope file against the routing table; read the reference(s) it points to before judging that file.

2. **Compute the scope file list first** (the `git status --short` above). Pre-existing code outside the list is noted, never blocking.

3. **Do not rationalize.** If a scope file matches a pattern listed in `references/anti-patterns.md`, it is a violation — even if sibling files in the same directory do the same thing. **Pre-existing wrongness is not precedent.**

4. **Evidence per claim.** Every flagged violation cites `file_path:line_number` + verbatim code + the exact rule it breaks (skill-doc path + line/section). Every "compliant" claim cites the skill-doc's canonical example by `file:line` it follows. A claim without evidence does not go in the report.

## Output format

In plan mode, the report names its focus, opens with the two paraphrase sections when the focus is `spec` (see "Plan mode"), then lists the findings with their class (§ "Finding classes"), then the coverage table. Its summary table counts BLOCKING · recheck, BLOCKING · fix-only, NEEDS-CARLO, DEFENCE-IN-DEPTH and COSMETIC instead of the rows below.

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
| "The plan cites the path, so it exists." | Plans name files that were renamed, never existed, or were remembered wrong. Check every existing path and symbol in the repo. |
| "These are the most important ones; the rest can wait for the next round." | In plan mode there is no next round over your slice. Every finding goes in; a dropped one surfaces only when the code is written. |
| "This row looks fine, I'll mark it OK." | A coverage row says OK only after the code it names was opened. Write "not checked" otherwise. |
| "I'll read the spec first so the paraphrase is accurate." | The paraphrase tests the plan alone. Reading the spec first fills the gaps a fresh session would hit. |
| "Let me audit the whole repo to be thorough." | Scope is uncommitted changes only. Pre-existing issues are noted separately, never blocking. |
| "No line number handy, the file is enough." | Evidence requires `file:line` + verbatim code. A claim without it is not reportable. |
