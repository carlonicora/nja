---
name: nja-automate-me
description: Use ONLY when explicitly asked — "automate me", "/nja-automate-me", "create/update my mode skill", "capture how I work as a skill", "turn my preferences into a skill". Mines the user's own transcripts, memories and CLAUDE.md files for recurring working conventions, asks a few structured questions, and writes or revises one personal <handle>-mode skill that agents follow. Never invoke this on your own initiative.
disable-model-invocation: true
---

# Automate me

Turn the user's working conventions into one skill agents read, instead of a boilerplate paragraph they retype at the top of every task.

The output is a single `<handle>-mode` skill — `carlo-mode` for this user.

> **Do not auto-invoke.** This skill rewrites how every future session behaves. It runs when the user asks for it by name, never because the description looked like a match.

## Where the output lives

**`~/.claude/skills/<handle>-mode/SKILL.md`.** Global, not project-local, and **not** inside this plugin.

The reason is not stylistic. This plugin is published to a public GitHub repo and describes a stack. A mode skill describes a person, applies to every repo including the ones that are not nja monorepos, and carries their name. It does not belong in a shared artefact.

## Flow

### 0. Check for an existing mode skill

```bash
ls ~/.claude/skills/*-mode/SKILL.md .claude/skills/**/*-mode/SKILL.md 2>/dev/null
```

If one exists, ask whether to **update** it (the default for a repeat run) or **start fresh** (rare — ask why first).

Update mode changes the rest of the flow:

- Step 2 mines only history since the skill was last edited: `git log -1 --format=%cI <path>`, or the file's mtime if it is not in git.
- Step 3 asks what has changed or is missing, not what to capture from zero.
- Step 5 edits the existing file in place. Preserve sections the user has not contradicted, revise the ones with new evidence, and add new sections only for genuinely new rules.

### 1. Read the prior

Read `references/known-patterns.md` first. It holds the cross-validated output of a full audit of this user's prompt history, with the date and method it came from.

Treat it as a **prior to confirm or contradict, not as an answer.** It saves the first run most of its mining cost, and it goes stale. Anything in it that the fresh mining pass contradicts is wrong, and the fresh evidence wins.

If the file is missing, or its date is more than a few months old, do the full mining pass in step 2 without it.

### 2. Mine the history

Three sources, cheapest and highest-signal first.

**a. The auto-memory files.** These are already-distilled corrections, and they cost almost nothing to read:

```bash
ls ~/.claude/projects/*/memory/*.md 2>/dev/null | wc -l
grep -l . ~/.claude/projects/*/memory/feedback_*.md 2>/dev/null
```

A `feedback_*` memory is a correction someone already decided was worth keeping. Read them all. They are the strongest evidence in the system.

**b. The CLAUDE.md files.** A rule written into more than one repo is a rule the user got tired of saying:

```bash
find ~/Development -maxdepth 3 -name CLAUDE.md -not -path '*/node_modules/*' | xargs cat | sort | uniq -c | sort -rn | head -40
```

A line appearing in five or more repos is a confirmed convention.

**c. The transcripts.** `~/.claude/projects/<slug>/<uuid>.jsonl`, where `<slug>` is a directory path with **both `/` and `.`** replaced by `-` (`tr '/.' '--'` — replacing only `/` misses every worktree).

**Mine every project, not just this one.** This is a deliberate departure from the upstream skill, which scopes mining to one workspace to avoid reading unrelated people's private chats. That rationale does not apply here: every project belongs to the same person, on their own machine, and a mode skill that only saw one repo would miss most of how they work.

Fan out. Split the window into three or four slices by date and give each slice to its own `Agent` (`subagent_type: "general-purpose"`, `model: "opus"`). Each returns a short structured list of patterns with evidence pointers — never raw transcript text. The raw reading stays in the subagents; the main thread keeps only findings.

Signals worth hunting:

- **Response preferences.** Length, tone, format, and every "dumb it down" correction.
- **Delegation habits.** Subagents, models, worktrees, parallelism, handoffs.
- **Verification posture.** What "done" means. Gates versus live proof. Who tests.
- **Code and prose discipline.** Style rules, principles cited, reuse expectations.
- **Process conventions.** Commits, branches, releases, what the agent may and may not touch.
- **Meta preferences.** Fixing skills mid-task, proposing new ones, model steering.

**Cross-check before elevating.** A pattern seen in two or more slices is high-confidence. A lone signal is weak and usually gets dropped.

### 3. Ask directly

Mining misses intent that has not come up yet. Use `AskUserQuestion` — structured options, not a blank page.

Shape: one or two questions, four to six options each, `multiSelect: true` for category questions. Start broad ("which areas matter most?"), then follow up on what they picked. After the structured rounds, one free-form question catches the rest.

Two structured rounds plus one open question is enough. Do not dump twenty questions.

### 4. Cluster

Group the findings into sections. `references/mode-skill-shape.md` has the shape and the section list. Use only the sections that apply — sparse is fine, bloated is not.

### 5. Draft

Author through `superpowers:writing-skills`. Do not hand-roll the file.

- **Path:** `~/.claude/skills/<handle>-mode/SKILL.md`.
- **Handle:** the user's first name.
- **Description:** trigger on their name, `/<handle>-mode`, and "work in their style". Never on generic words like "write code" or "review this". A mode skill that fires on its own is a bug — it is heavy, opinionated, and the user did not ask for it.

### 6. Cut the prose

Apply `nja-unslop` to every line, plus `superpowers:writing-skills`' own writing rules.

Show the draft and take feedback. Expect several rounds. Cut ruthlessly — a mode skill is not a manual.

### 7. Hand it back

Write the file. **Do not commit it, and do not open a PR.** The user reads it before it governs anything.

Then say plainly which sections came from mining evidence, which came from their answers, and which came from the prior in `references/known-patterns.md`, so they know what to scrutinise.

## Guardrails

- **Do not overfit to one conversation.** A preference stated once and contradicted later is noise. Require repeats.
- **Do not be clever.** Restating other skills, inventing metaphors, or writing poetically for an agent reader is cost with no benefit. Keep it operational.
- **Reference, do not inline.** Skills the user relies on appear as names, not pasted excerpts.
- **Keep sections minimal.** "Communicate clearly" is not a section. "TL;DR first. Numbered options he can answer with one letter. No invented acronyms." is.
- **Do not force symmetry.** No process rules worth writing down means no Process section.
- **Name conventions generic.** Write imperatives about "the user", not the first name, so the file reads sanely if it is ever shared.
- **Contradictions are findings, not problems.** When two rules genuinely conflict, write both and name the condition that picks between them. Flattening a real tension into one rule produces a skill that is wrong half the time.

## When not to use

- A task-specific skill, not working conventions: use `superpowers:writing-skills` alone.
- One narrow workflow ("how I write commit messages"): that is a regular skill, not a mode skill.
- Keeping an existing skill current after a bad session: that is `nja-reflect`.

---

Adapted for nja from the `automate-me` skill in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.

Deliberate departures from upstream: mining spans every project rather than one workspace; auto-memory files and CLAUDE.md files are added as first-class sources ahead of transcripts; the output is written to the user's global skills directory and left uncommitted instead of landing through a worktree and a PR.
