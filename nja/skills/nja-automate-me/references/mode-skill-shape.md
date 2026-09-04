# The shape of a mode skill

The upstream reference implementation is [`poteto-mode`](https://github.com/cursor/plugins/tree/main/pstack/skills/poteto-mode). Read it for granularity if you have network access. Do not copy its content — its rules are one person's, and at least two of them are wrong for this user.

## Frontmatter

```yaml
---
name: <handle>-mode
description: <Handle>'s working style. Use for "<handle>", "/<handle>-mode", or a request to work in their style. Never invoke on your own initiative.
---
```

The description is the whole safety mechanism. It must trigger on the handle and on nothing else. A mode skill that fires because the task looked like a match is a bug: it is heavy, opinionated, and unasked for.

## Sections

Use only what applies. A section earns its place by carrying a rule that is specific and non-default.

| Section | Holds | Skip when |
|---|---|---|
| **Non-negotiables** | The three to five rules whose violation ends the session badly. Nothing else. | Never skip. This is the section that gets read. |
| **Response style** | Length, format, jargon rules, how options are presented. | Never skip for this user. |
| **Autonomy** | What proceeds without asking, what always stops. Name the condition, do not pick a side. | The user has no consistent boundary. |
| **Verification** | What "done" means. What counts as proof. Who tests. | The user does not verify. |
| **Delegation** | Subagents, models, worktrees, parallelism, handoffs. | The user works in one thread. |
| **Code discipline** | Reuse rules, style rules, layering. Reference the architecture skill; do not restate it. | Covered entirely by an architecture skill. |
| **Process** | Commits, branches, releases, what may be touched. | No process rules worth writing down. |
| **Machine safety** | Ports, processes, other running work. | Single project, single machine, no concurrency. |

## Rules for the prose

- **Imperatives, not descriptions.** "Copy the named reference verbatim" beats "the user values consistency".
- **Specific, not general.** "Communicate clearly" is filler. "TL;DR first. Numbered options answerable in one letter. No invented acronyms or unexplained metrics." is a rule.
- **Say the condition, not the average.** Where two real rules conflict, write both and name what picks between them. Flattening a tension produces a skill that is wrong half the time.
- **Reference, do not inline.** Name the skills the user relies on. Do not paste their contents.
- **Write about "the user", not the name.** The file should read sanely if it is ever shared.
- **One page.** If it needs more, the extra belongs in a reference file or in an existing skill.

## What does not go in

- Anything an architecture skill already enforces. Point at it.
- Anything a lint rule, a generator or a hook could enforce instead. That is a backlog item, not a paragraph. See `nja-architecture`'s `references/discipline.md` §4.
- Preferences stated once and contradicted later.
- Aspirations. This describes how the user works, not how they would like to work.
