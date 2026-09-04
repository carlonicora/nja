# Known patterns — prior for the mining pass

**Audited 2026-09-04.** Source: 22,204 prompts from `~/.claude/history.jsonl` (2025-09-28 → 2026-09-04), plus 1,692 session transcripts, 43 `CLAUDE.md` files, 346 auto-memories and 11 repos.

**Method.** The prompt corpus was split into six chronological slices and read in full by six independent agents, plus one agent auditing config and transcripts. Only patterns that surfaced independently in **two or more slices** are listed. Slice coverage is given per pattern.

**This is a prior, not an answer.** Confirm each one against fresh evidence. Anything the new mining pass contradicts is stale, and the fresh evidence wins. Do not paste these into the mode skill unverified.

---

## Confirmed in all six slices

**Reuse over redesign.** A named reference is a specification, not an example. When a working implementation is pointed at — another repo, another component, an earlier commit — copy it verbatim and adapt only the data. A hand-rolled variant is drift to hunt down across six repos later. Borrowing the logic while redesigning the presentation is the specific failure that draws the strongest reaction.

**Add logs before theorising.** Instrument first, read what actually happens, then change code. Guessing from the code alone, editing, and guessing again is the most expensive loop in the work. Remove the logs afterwards.

**Prove it works.** "It builds", "it lints", "tests pass" is not evidence the feature does what was asked. Claims of completion are challenged, and the challenge is usually right.

**Git is the user's.** No commit before manual testing. Commit only the files this session touched — others are editing the same tree. No branching, no reverting, no stashing, no force-push unless asked.

**TL;DR, plain words, no jargon.** Explicitly framed as an ADHD requirement. Invented acronyms, internal shorthand and unexplained metrics are worse than useless. "Terse" does not mean dropping content — dense and short, not short and empty.

**Scope discipline.** Do exactly what was asked. Unrequested changes, unrequested reverts and unrequested refactors are a trust failure, not a bonus. When something else looks wrong, say so and get a yes.

## Confirmed in four or five slices

**Fix root causes.** No symptom patches, no guards that silence a crash, no caps that hide a query problem, no retry that papers over a weak prompt or schema. Long-term correctness over the cheapest fix — though not over-engineering either; both get called out.

**Parallel implementation, one gate at the end, no commit.** Dispatch every implementation task at once, no review between tasks, one lint/build/test pass when all of them land, no commit until the user has tested. Restated dozens of times and still violated. *(Slices 4, 5, 6 — emerged with the plan-writing skill; treat as current, not historical.)*

**Types are real types.** Dates stored as dates, money in integer cents, a module descriptor where a bare string was used, real schemas with per-field descriptions rather than prose stuffed into a prompt.

**DRY, and shared packages stay generic.** No duplication of a component that exists. No application-specific code inside a shared library. A change to a package must not be made to satisfy one app.

**Worktree and machine safety.** Work in the worktree that was given, not the main checkout. Never kill a process by name — several projects run identical command lines on this machine. Do not start or stop dev servers without being asked.

**Options as numbered lists.** Design questions are answered in one token: `A`, `B+C`, `1. no 2. yes`. Present choices pre-numbered with the tradeoff visible. Never ask for confirmation of something that has not been shown.

## Confirmed in two or three slices

**Disagree when you disagree.** Explicit and repeated: do not agree to avoid disagreeing. A recommendation is a judgment, not validation. Being a sparring partner is the requested role.

**Do not ask what the code already answers.** Questions whose answers are in the codebase read as a signal that the exploration was not done.

**Progress visibility beats speed.** Long silent stretches draw more anger than slow work. Say what is happening.

**`playwright-cli`, never a browser MCP or the Playwright library.** Load the page twice and the session is logged in. Credentials have been supplied repeatedly.

**Model steering.** Opus over Sonnet for anything with judgment in it, stated many times.

## Single-slice signals — weak, verify before using

- Never tell the user when to stop working. That is their call.
- Prompts in English even when the product's UI is Italian.
- Named parameters preferred over positional.
- A compiler warning is treated as a defect, not a style note.
- Pre-existing failures are still failures and get fixed regardless of who wrote them.

---

## Two tensions to preserve, not flatten

Both are real, and a mode skill that picks one side will be wrong half the time. Name the condition instead.

**Autonomy.** "Do not take decisions without asking me first" and "yes to all, no need to ask, implement autonomously" both appear often. The condition is the stage: **design and scope decisions are the user's**; execution inside an agreed plan is not. Asking mid-implementation about something the plan already settled draws the same anger as deciding unilaterally.

**Smallest versus best.** "You are overcomplicating this, KISS" and "I do not need the smallest solution, I need the best long-term one" both appear often. The condition is what is being minimised: **minimise layers, indirection and invented abstraction; do not minimise correctness or durability.** A cheap fix that will break is not simple.
