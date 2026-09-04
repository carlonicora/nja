---
name: nja-interrogate
description: Use for "interrogate", "adversarial review", "second opinion", "challenge this", "stress test this", "find blind spots", "tear this apart", or before committing to a spec or plan you do not fully trust. Spawns several independent reviewers over the same diff or document and returns one synthesised verdict, split into act on / consider / noted / dismissed.
---

# Interrogate

Spawn several reviewers to adversarially review a change, a spec, or a plan. Each reviewer gets the same prompt and rubric. The adversarial signal comes from independence, not from assigned personas.

Agreement across reviewers is high-confidence signal. A lone finding is worth reading but carries less weight.

**The deliverable is a synthesised verdict. Do NOT auto-apply changes.**

## Step 1: determine scope

Identify what to review:

- If the user points at specific files, a diff, or a spec/plan document, use that.
- If on a worktree branch, run `git diff dev...HEAD` for the full changeset. In an nja repo the base is `dev`, not `master`.
- If the user's message references recent work, gather the relevant files.

Package the diff or document plus any surrounding context files the reviewers need.

## Step 2: state the intent

Before spawning anything, state the intent explicitly. What is this work trying to accomplish? Derive it from the user's message, the spec, the commit messages, and the code itself.

Write one clear paragraph. Reviewers challenge whether the work achieves the intent well, not whether the intent is correct. If you are unsure about the intent, ask the user before proceeding.

## Step 3: spawn reviewers

Launch all reviewers in **one message** so they run in parallel. Use the `Agent` tool with `subagent_type: "general-purpose"`.

Default to **four reviewers on `opus`**. Diversity of model family is not available here, so buy independence a different way: each reviewer gets an identical prompt and no sight of the others, and you weight a finding by how many reviewers reached it alone.

Where the user has another model available and asks for it, use it for at least one reviewer. Genuine cross-family disagreement is worth more than a fourth same-model opinion.

Read `references/reviewer-prompt.md` and fill in the template with:

1. The stated intent.
2. The diff or file contents.
3. The review rubric from `references/rubric.md`.
4. The code-quality lens from `references/code-quality-review.md`.
5. **For any nja code:** the `nja-architecture` skill, named as required reading. A reviewer who has not read it will miss the violations that matter most here — `fetch()` in the frontend, `overridesJsonApiCreation`, raw `neo4j.read()`, `query.query +=`, dates stored as strings, app-specific code leaking into a shared package, a hand-rolled component where one exists in `nextjs-jsonapi`.

The same filled template goes to every reviewer.

## Step 4: synthesise

As results come back, build a unified picture:

1. **Parse all findings.**
2. **Identify consensus.** Findings raised by two or more reviewers independently are the highest signal.
3. **Identify lone findings.** Still worth reading, weighted lower.
4. **Deduplicate.** Different reviewers describe the same issue differently. Merge, and note who raised it.
5. **Note disagreements.** One reviewer flagging what another explicitly cleared is useful context.

## Step 5: lead judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator. Read `references/lead-judgment.md` for the full framework.

Reviewers see a slice. You have the full context: the goal, the constraints, what was already considered and rejected. Use that aggressively.

Categorise every finding:

- **Act on.** Real issues affecting correctness, security, or maintainability given the actual goals. These would block the change.
- **Consider.** Legitimate, but you are not sure they outweigh the cost of addressing them now.
- **Noted.** Technically valid, not actionable. Context-dependent or low-impact.
- **Dismissed.** Wrong, nitpicky, or missing context. Say briefly why.

For each finding: which reviewers raised it, the category, and a one-line rationale.

## Output format

### Intent
> The stated intent paragraph from step 2.

### Reviewers
One bullet per reviewer: label, model, number of findings.

### Act on
Findings that should be addressed. Description, who raised it, why it matters.

### Consider
Description, who raised it, the tradeoff.

### Noted
Brief list.

### Dismissed
Rejected findings with a brief rationale, so the user can override your judgment.

### Agreement map
Where reviewers agreed, where they diverged, and what that pattern says.

---

Adapted for nja from the `interrogate` skill in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.
