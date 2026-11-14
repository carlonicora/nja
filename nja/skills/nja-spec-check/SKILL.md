---
name: nja-spec-check
description: Use right after superpowers:brainstorming writes a design spec in an nja monorepo, in place of brainstorming's builder check (builder-check-prompt.md), and after any substantive edit to that spec. Runs ONE exhaustive builder check that lists every open question at once instead of the top few, requires a states-and-actions table for features with saved state, steps or undo, then checks the answers against the rest of the spec instead of re-running the full check. Triggers include "validate the spec", "builder check", "check the spec before planning".
---

# Spec check

This replaces the builder check in `superpowers:brainstorming` for nja repos. Brainstorming's check asks a fresh reader for the questions it would need answered, ranked. A thorough reader returns the few it ranks highest; once those are answered, the next check returns the next few, and every round pays to read the whole repo again. Answers also add states and rules nobody checks against each other, so later rounds find contradictions the earlier answers created.

This skill gets every question in one pass, then checks only the answers.

Everything else in brainstorming stays as it is: the three piles, one message of questions, the hard gate before building.

## 1. States and actions table, before the check

When the feature stores something between requests and the user moves it through steps, can apply, undo, discard or retry, or can have several of them open at once, the spec MUST contain a **States and actions** section before the check runs:

- **Rows:** every state the thing can be in, the partial ones included (half applied, failed partway, finished, abandoned).
- **Columns:** every action the user can take inside the flow, then every change made outside it: the user editing or deleting a linked record elsewhere, a second open flow on the same data, another user, a retry after a failure.
- **Cells:** what happens, or `not allowed — <what the user sees>`.

Fill every cell you can. A cell you cannot fill is an open question; leave it as `?` for the check. A feature with no stored state skips the table, and the spec says so in one line.

Most questions that surface in a third or fourth round of checks are a cell nobody wrote down.

## 2. One builder check, exhaustive

Dispatch ONE fresh sub-agent (model: opus) with the prompt below. Fill in the repo root and the spec path. Never give it your reasoning or the conversation.

```
You are a talented software engineer on the monorepo at [REPO_ROOT]
(NestJS + Neo4j API, Next.js frontend, JSON:API between them). You've
been handed a design document and asked to plan the build. You will not
be able to talk to the person who wrote it, and nobody reads this
document again before the plan is written: whatever you leave out, the
plan will guess.

Read [SPEC_PATH].

Report EVERY question you would need answered before you could plan this
well: every place where you would have to guess and a wrong guess would
change what gets built. No cap, and no ranking that drops the tail.
Group the questions by the spec section they come from. Mark each one
HIGH (it changes the data model, an endpoint, or what the user sees) or
LOW.

Work through these four passes in order, and finish each one:

1. Code claims. Every statement the spec makes about the code as it is
   today (a file, a field, an order, a default, a behaviour, a component
   to reuse): check it in the repo. Report each one that does not hold,
   with file:line.
2. The States and actions table, cell by cell. A cell that is empty,
   vague, or contradicts another cell or the text is a question. Then
   name the rows and columns the table is missing: a state the text
   implies, an outside change the text allows.
3. Rules against rules. Every rule in the spec against every other one.
   Two rules that cannot both hold, or a default that breaks a rule, is
   a question.
4. Reach. Every place the change reaches that the spec does not name:
   other callers of what changes, other pages or components that share
   it, offline or cached copies, other roles' views of the same data,
   seed and sample data, background jobs and AI calls that read or write
   it. Name each one and ask whether it is in scope.

For each question give: the question, the options you see, and what each
option changes in the plan.

Skip anything the document explicitly leaves to the builder, and
anything you could decide yourself without changing what gets built.
Skip wording.

End with one line: "Checked: N code claims, M table cells, K rules,
L places reached." If nothing important is left, add "nothing important
left" after it.
```

If the closing line is missing, or a count is zero where the spec clearly has claims, cells or rules, the check is incomplete: send it back (continue the same sub-agent) to finish the missing pass. Do not start a new check.

## 3. Sort and ask, once

Sort the questions into brainstorming's three piles:

- **Answered already** by the conversation or the project: write the answer into the spec.
- **Minor:** settle it yourself and mark it in the spec as your call.
- **Theirs:** only the user can answer it, and the answer changes what gets built.

Ask the "theirs" pile in ONE message, most important first, as real questions with options (the check already gives them). Write every answer into the spec, and update the States and actions table for each one.

## 4. Consistency check on the answers

After the answers are written in, dispatch ONE fresh sub-agent with the prompt below. It reads the spec only, not the repo, which keeps it cheap.

```
Read [SPEC_PATH]. These sections were just edited to answer open
questions: [EDITED SECTIONS, with line ranges].

For each edited section, report:
1. Every contradiction with any other part of the document. Quote both
   lines.
2. Every state, action or outside change it adds that the States and
   actions table does not cover, and every table cell it changes that
   still shows the old behaviour.
3. Every rule it adds that breaks, or is broken by, a default or rule
   elsewhere in the document.
4. Every claim it makes about the code as it is today. List each one
   with its line; do not check them.

Report every issue, no cap. If there is none, say "consistent".
```

Then:

- Check each code claim from item 4 yourself in the repo (Grep or Read). They are few, and a sub-agent for them costs more than the check.
- Fix every issue. One only the user can decide goes to them, in one message.
- If the fixes edited the spec again, run the consistency check once more on the newly edited sections only. At most 2 consistency checks; if issues remain after the second, show them to the user with the spec instead of looping.

## 5. Later edits

After the check, a substantive edit (scope, data model, UI shape) gets the consistency check in step 4 on the edited sections, not a new builder check. A new builder check runs only when an edit adds an area the first check never saw (a new entity, a new page, a new integration), and then only on that area: add to the prompt "Focus on [sections]. The rest of the document was checked on [date]; read it for context only."

## 6. Hand-off

When you hand the spec over for approval, say in one line what ran: the builder check (how many questions: answered, your calls, theirs) and how many consistency checks. Then list your calls so the user can check them while reading.

## Failure modes

| Thought | Why it's wrong |
|---|---|
| "The check came back with five questions; I'll answer them and run it again." | That is the loop this skill exists to end. One exhaustive check, then consistency checks on the answers. |
| "This feature is simple; it needs no table." | The table is required whenever there is stored state with steps, undo, discard or retry. A feature without one says so in a line. |
| "The answers are small, no consistency check needed." | Answers are what create the contradictions later rounds find. The check reads only the spec; it is cheap. |
| "I'll run a fresh builder check to be safe after this edit." | A fresh full check re-reads the repo and pages through a new set of questions. Check the edit for consistency, and scope a builder check to a genuinely new area. |
| "The check left out a pass; I'll start a new one." | Continue the same sub-agent to finish the pass. A new one starts over. |
