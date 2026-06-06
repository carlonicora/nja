---
name: nja-verify
description: Use when auditing uncommitted changes for architecture compliance — before committing, before handing work back to the user, after generating or implementing a module, or whenever asked to verify/audit/review a diff against the nestjs-neo4jsonapi + nextjs-jsonapi architecture rules.
---

# Architecture audit

Audit a working tree's uncommitted changes against the architecture rules. This is a read-only review pass: it finds violations and cites them with evidence. It does NOT fix them.

## Core principle

**The `nja-architecture` skill is the ONLY source of truth for rules.** Do not cite rules from memory, from `CLAUDE.md`, or from prior conversation — cite them by skill-doc path + section. If a rule is not in the skill, it is not a rule for this audit.

## Scope

Audit the changes introduced in the working tree that have **not been committed yet**. Compute the scope-introduced file list FIRST, before reading any rule, via:

```bash
git status --short
```

Audit ONLY these files. Anything outside this list is pre-existing — flag it separately, do not block on it.

## Method (non-negotiable)

1. **Invoke the `nja-architecture` skill via the Skill tool.** Read the full routing table AND every layer-reference doc relevant to the files in scope. Match each scope file against the routing table; read the reference(s) it points to before judging that file.

2. **Compute the scope file list first** (the `git status --short` above). Pre-existing code outside the list is noted, never blocking.

3. **Do not rationalize.** If a scope file matches a pattern listed in `references/anti-patterns.md`, it is a violation — even if sibling files in the same directory do the same thing. **Pre-existing wrongness is not precedent.**

4. **Evidence per claim.** Every flagged violation cites `file_path:line_number` + verbatim code + the exact rule it breaks (skill-doc path + line/section). Every "compliant" claim cites the skill-doc's canonical example by `file:line` it follows. A claim without evidence does not go in the report.

## Output format

For each violation:

- **Severity:** BLOCKING (`references/anti-patterns.md` or a layer doc explicitly forbids it) / DEFENCE-IN-DEPTH / COSMETIC
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
| "I know this rule, I'll cite it from memory / CLAUDE.md." | The `nja-architecture` skill is the only authority. Cite by skill-doc path + section, or don't claim it. |
| "This is close enough to compliant." | Either it matches a canonical example (cite it) or it's a violation. There is no "close enough." |
| "I'll just fix this one while I'm here." | This pass is hands-off. Report the fix; let the user decide. Fixing mid-audit hides what was wrong. |
| "Let me audit the whole repo to be thorough." | Scope is uncommitted changes only. Pre-existing issues are noted separately, never blocking. |
| "No line number handy, the file is enough." | Evidence requires `file:line` + verbatim code. A claim without it is not reportable. |
