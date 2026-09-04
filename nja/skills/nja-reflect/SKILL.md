---
name: nja-reflect
description: Use when the user says "reflect", "/nja-reflect", "what did you get wrong", "how do we stop this happening again", or after a session where the same correction had to be given more than once. Spawns three parallel reviewers over the session transcript, surfaces durable learnings, and routes each one to a concrete edit on an existing skill or reference doc — with the user approving before anything is written.
disable-model-invocation: true
---

# Reflect

Mine the session for durable learnings, then route them into skill edits.

> **Why this exists.** The corrections that matter get given out loud, once, in anger, and then live nowhere. This is the loop that turns them into something the next agent reads before it makes the same mistake. It is the difference between 92 memories nobody consults and five rules in a reference doc that gets invoked on every task.

## When to invoke

- The user said "reflect".
- The user had to give the same correction twice in one session.
- A complex task landed cleanly and the recipe is worth keeping.
- The agent hit dead ends, found the working path, and the path generalises.
- The user corrected the agent's approach mid-task.

Skip when the conversation is trivial, off-topic, or already covered by a skill the agent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

Transcripts live at `~/.claude/projects/<slug>/<uuid>.jsonl`. The slug is the working directory with **both `/` and `.`** replaced by `-`. The dot matters: a worktree at `/Users/x/Development/wyrdli/.claude/worktrees/ai` becomes `-Users-x-Development-wyrdli--claude-worktrees-ai`, so replacing only `/` resolves to a directory that does not exist and every worktree session silently falls through.

```bash
SLUG=$(pwd | tr '/.' '--')
ls -td "$HOME/.claude/projects/$SLUG" 2>/dev/null || echo "NO TRANSCRIPT DIR for $SLUG"
ls -t "$HOME/.claude/projects/$SLUG/"*.jsonl 2>/dev/null | head -5
```

Order by real modification time, never by the UUID in the filename. The first line of a transcript is a `{"type":"last-prompt",...}` header, **not** a message — to identify the right file, find the first line whose `"type"` is `"user"` and compare that against this conversation's opening prompt.

Read only this project's transcripts. Do not glob across `~/.claude/projects/*/` — that reads unrelated sessions from other repos.

**If no path resolves, say so out loud and stop.** Do not quietly fall back to writing a digest from your own recollection: a reflection built on what you remember rather than what happened is exactly the self-report `nja-architecture`'s `references/discipline.md` §1 forbids. Ask the user for the transcript path, or run with an explicitly-labelled digest only if they say to.

### 2. Spawn three reviewers in parallel

One message, three `Agent` calls, `subagent_type: "general-purpose"`, `model: "opus"`. The prompt forbids file writes; the parent applies edits.

| Lens | Prompt template |
|---|---|
| Judgment | `references/judgment-reviewer.md` |
| Tooling | `references/tooling-reviewer.md` |
| Divergent | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked.

### 3. Synthesise

One `Agent` call, `subagent_type: "general-purpose"`, `model: "opus"`. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. It returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the Accepted list. Any item that would be enforced more reliably by a lint rule, a script, a hook, an entity-descriptor constraint, or a runtime check moves from Accepted to Backlog — the fix is the mechanism, not more prose.

This is the `nja-architecture` skill's `references/discipline.md` §4, "Encode lessons in structure", applied to this skill's own output. A rule an agent has to remember is a rule an agent will skip.

### 5. Apply — after approval

**Present the full Accepted / Rejected / Backlog output to the user and wait for an explicit yes before touching any file.** Skill changes affect every future session in every repo that installs this plugin. Never auto-apply.

The user picks which subset to apply and may redirect where each one lands.

Routing targets, in order of preference:

| Kind of learning | Where it goes |
|---|---|
| An architecture rule for this stack | `nja-architecture/references/` — the layer doc it belongs to, or `anti-patterns.md` |
| A cross-cutting working discipline | `nja-architecture/references/discipline.md` |
| A change to how one workflow runs | the relevant `nja-*` skill's `SKILL.md` |
| The skill exists but did not trigger | its frontmatter `description` — tune the trigger words, not the body |
| A genuinely new workflow | a new skill, authored through `superpowers:writing-skills` |
| A repo-specific fact, not a general rule | that repo's `CLAUDE.md`, not this plugin |

For a substantive edit — a new section, a new table, more than about ten lines — hand it to `superpowers:writing-skills` and run its draft/iterate loop rather than free-handing it.

**Do not commit.** Leave the edits in the working tree for the user to read.

### 6. Summarise

Short list, no preamble:

- **Applied:** `<path>`. What changed, one line each.
- **Backlog:** the structural fixes worth building, one line each. Offer to append them to `docs/reflect-backlog.md`; that file is a write like any other and waits for the same yes as the rest.
- **Dropped:** one line per rejected finding plus the reason.

---

Adapted for nja from the `reflect` skill in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.
