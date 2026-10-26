# nja — skills for nestjs-neo4jsonapi + nextjs-jsonapi

A Claude Code plugin that teaches Claude how applications built on
[`@carlonicora/nestjs-neo4jsonapi`](https://www.npmjs.com/package/@carlonicora/nestjs-neo4jsonapi)
and [`@carlonicora/nextjs-jsonapi`](https://www.npmjs.com/package/@carlonicora/nextjs-jsonapi)
are structured — so it builds, plans, generates, and audits code that follows those
frameworks' conventions instead of drifting away from them.

These skills are application-agnostic: they describe the way the two libraries work, not
any single product. Drop the plugin into any monorepo that consumes both libraries.

## Skills

| Skill | Use when |
|---|---|
| **`nja-architecture`** | Before editing or creating any TypeScript file under `apps/api/src/features`, `apps/web/src/features`, or `packages/*/src`. Routes to the layer-specific reference doc (entity, DTO, repository, service, controller, model, interface, service, component) and surfaces the NestJS + Neo4j + JSON:API rules. The single source of truth — the other skills defer to it. |
| **`nja-generate`** | Creating, scaffolding, or generating a new feature module or entity (backend, frontend, or both). Drives the `generate-module` / `generate-web-module` generators from a single JSON "module shape". |
| **`nja-arrows`** | Generating modules from an Arrows.app diagram (or any `{nodes, relationships, style}` graph/ER JSON export). Translates the diagram into confirmed `structure/*.json` — asking per node for what the diagram can't encode — then hands off to `nja-generate`. |
| **`nja-writing-plan`** | Writing an implementation plan. Wraps `superpowers:writing-plans` with architecture compliance: inline citations to canonical examples, a structured self-audit, skill-wins-over-plan dispatch, and an audit step in the final verification task. Before the plan is handed over, a fresh sub-agent audits it independently. Existing code is not precedent: a pattern already in the repo does not make it correct. |
| **`nja-delegate-implementation`** | Handing a written plan to a fresh session to implement. Writes a temp markdown file that *is* the prompt for that session: `@`-links to the spec and plan, the context that dies with the conversation (session decisions, repo state, resolved commands), and the execution protocol — parallel task dispatch, implementers write and run only their own task's specs, one lint/build/test at the end, no commits. The final `nja-verify` audit runs in a fresh sub-agent; violations are fixed and re-audited, for at most 3 rounds. |
| **`nja-verify`** | Auditing uncommitted changes against the architecture rules — before committing, before handing work back, or after generating/implementing a module. Read-only: it reports violations with evidence, it does not fix them. In plan mode it audits a written plan instead of a diff. |
| **`nja-update-dependencies`** | Updating or upgrading npm dependencies across the monorepo — root, apps, and `packages/*`. Sweeps all three surfaces (workspace manifests, pnpm `catalog:`, and concrete `overrides:` — `ncu` sees only the first), holds back the majors that break this stack, then verifies with lint, build, a real `pnpm dev` boot check, and tests. Leaves everything uncommitted for you to test and commit. |
| **`nja-update-fleet`** | Updating dependencies across **multiple** nja monorepos at once. Discovers every nja repo on the machine, computes one fleet-wide version set, sweeps and validates both shared libraries against every consumer *before* pushing, releases each library exactly once, then verifies every app with lint, build, tests and a serialized `pnpm dev` boot. Never commits an app repo. |
| **`nja-handoff`** | Ending a session whose work another agent will continue. Compacts the conversation into a handoff document (saved to the OS temp dir, sensitive data redacted) with a "suggested skills" section, referencing existing artifacts instead of duplicating them. |
| **`nja-e2e`** | Adding end-to-end coverage for a page or route. Two passes: the Given/When/Then list you review as prose, then the Playwright specs that satisfy it. |
| **`nja-pre-release`** | Before releasing or handing back. Drives `pnpm lint`, `pnpm build` and `pnpm test` to green, then runs the full e2e suite and proposes fixes for what it reports. |
| **`nja-create-verifier`** | A repo has no scripted way to prove UI or API behaviour. Generates a project-local `verify-<app>` skill plus a feature map, then proves it by running it once. Stops you being the test harness. |
| **`nja-maintain-verifier`** | Keeping a generated `verify-<app>` skill and its feature map honest as the app changes. Parallel source readers per feature, one live session driving every feature, one batch of proven corrections. |
| **`nja-blast-radius`** | Before a shared-package change, or any diff whose effects reach past itself. Finds the breakage grep won't show across the other nja apps, then *proves* the one fact the change is safe because of by running code. |
| **`nja-interrogate`** | Adversarial review of a diff, spec, or plan. Several independent reviewers, one synthesised verdict split into act on / consider / noted / dismissed. Never auto-applies. |
| **`nja-reflect`** | After a session where the same correction had to be given twice. Three parallel reviewers mine the transcript for durable learnings and route each to a concrete skill or reference edit — you approve before anything is written. |
| **`nja-automate-me`** | Explicitly asked only. Mines your transcripts, auto-memories and CLAUDE.md files for how you actually work, asks a few structured questions, and writes one personal `<handle>-mode` skill to `~/.claude/skills/` — outside this plugin, because it describes a person, not a stack. |
| **`nja-linear-setup`** | Connecting a repo to Linear, once per repo. Checks the key in `.env`, asks which team to use and writes `LINEAR_TEAM_ID` after you approve, then makes sure the `Bug`, `Feature`, `Improvement`, `Brainstorm` and `Small` labels exist. |
| **`nja-linear-capture`** | You find something worth doing while working on something else ("save this as a task"). Drafts a Linear issue with a real title and a self-contained description, asks one question to confirm it and choose Brainstorm or Small, and creates it in Todo. Never starts the work. |
| **`nja-linear-next`** | Asking what to work on ("what's next"). Lists the open issues, in-progress ones first and then by priority, shows whether each Brainstorm issue has its spec and plan, and lets you pick. It never recommends one. |
| **`nja-linear-start`** | Starting an issue ("start WYR-12"). Moves it to In Progress. A Small issue is analysed, fixed and moved to In Review when its specs pass. A Brainstorm issue resumes at brainstorm, plan or delegate, depending on which of its `Spec` and `Plan` documents already exist. |
| **`nja-unslop`** | Any prose an agent produces: reports, docs, commit messages, handoffs. Cuts the AI tells. |

`nja-architecture` is the authority; `nja-generate`, `nja-writing-plan`, `nja-verify`,
`nja-interrogate` and `nja-reflect` all invoke it and cite its reference docs. Its
`references/discipline.md` carries the cross-cutting rules that are not about this stack:
prove it works, fix root causes, type discipline, encode lessons in structure, and
separating shared state when several sessions share one tree.

The plan-driven path runs `nja-writing-plan` → `nja-delegate-implementation` → (fresh
session) → `nja-verify`.

The proof path runs `nja-create-verifier` once per repo, then `nja-blast-radius` before a
package release and `nja-interrogate` on anything you don't trust yet. `nja-reflect` closes
the loop afterwards.

`nja-automate-me` is run once per person, not per repo. Its output lives in
`~/.claude/skills/<handle>-mode/`, and `nja-reflect` keeps that output current.

`nja-update-dependencies` ships three deterministic scripts — `nja-deps-sweep.sh`,
`nja-deps-doctor.sh`, and `nja-dev-boot.sh` — in the same spirit as `nja-lint.sh`: grep-fast,
zero-model-context checks the skill drives rather than reimplements. `nja-dev-boot.sh` tears
the dev stack down by process group, never by name pattern — the same discipline `nja-lint`
enforces for architecture, applied here to killing processes safely.

## Linear

Four skills make Linear the to-do list of each nja repo: `nja-linear-setup`,
`nja-linear-capture`, `nja-linear-next` and `nja-linear-start`. They never call Linear
themselves. Every request goes through `scripts/nja-linear.sh`, which talks to Linear's
GraphQL API with curl and jq and prints JSON.

Two variables in the repo's root `.env` configure it:

| Variable | Set by | Meaning |
|---|---|---|
| `LINEAR_API_KEY` | you, by hand | personal API key for that repo's Linear workspace |
| `LINEAR_TEAM_ID` | `nja-linear-setup`, after asking | the team new issues are created in |

The key belongs to the repo. The script reads `.env` from the repo root, or from the main
checkout when run inside a worktree, and nowhere else. It ignores the process
environment, so a key exported in your shell never reaches another repo's workspace. The
key never appears on a command line or in any output.

The flow is capture, next, start. `nja-linear-capture` creates the issue in Todo,
`nja-linear-next` lists the open ones, and `nja-linear-start` moves the chosen issue to In
Progress. When the work finishes with its checks green (the affected specs for a Small
issue; lint, build, tests and the architecture audit for a delegated plan), the issue moves
to In Review; if a check fails it stays In Progress with a comment saying why. You move it to
Done by hand after testing and committing.

When a Linear issue is in context, `nja-writing-plan` attaches the spec and plan to it as
`Spec` and `Plan` documents, and `nja-delegate-implementation` tells the fresh session to
comment on the issue and move it to In Review when its checks pass. In a repo without the
Linear variables both skills behave as before.

## Enforcement (hooks + linter)

The plugin is **self-enforcing on install** — three layers, escalating from advisory to
deterministic. All require `jq` on `PATH`; hooks run harness-side and cost **zero model
context**.

> **Scoped to nja projects only.** The plugin installs at user scope, so its hooks see
> every repo — but they go completely inert unless the current repo is actually an nja
> project (any tracked `package.json` depends on `@carlonicora/nestjs-neo4jsonapi` or
> `@carlonicora/nextjs-jsonapi`, or the repo has an `nja.config.json`). So editing an
> unrelated project — even one using Radix or NestJS — is never affected. (`nja-lint` run
> manually always checks whatever you pass it, by design.)

**1. `PreToolUse` reminder** (`hooks/remind-architecture.sh`) — fires before every
`Edit`/`Write`/`MultiEdit`. When the target file matches the `nja-architecture` routing
table (e.g. an `*.repository.ts` under `apps/api/src/features`), it injects a reminder to
invoke the skill and points at the exact reference doc. **Soft** — reminder only, never
blocks.

**2. `nja-lint`** (`scripts/nja-lint.sh`) — a zero-dependency, deterministic checker for
the greppable anti-patterns in `nja-architecture/references/anti-patterns.md`
(`fetch()` to the app's own API, manual `SKIP/LIMIT`, hand-written Cypher with no
`buildDefaultMatch()` — a cross-tenant company-scope leak, `asChild`, `@radix-ui` imports,
controllers importing repositories, any `.records` access on a query result such as
`result.records[0]` or `(result.records as any[]).map(...)`; plus WARN-level heuristics like
`@IsString()` on date DTOs).
Two tiers — **BLOCKING** (calibrated near-zero false positives) and **WARN** (heuristic).
The `fetch` rule targets only literal own-API calls, so S3 presigned uploads and local
functions named `fetch()` are not flagged. Run it directly:

```bash
# check specific files, or omit args to check `git status` (the uncommitted diff)
nja/scripts/nja-lint.sh apps/api/src/features/crm/account/repositories/account.repository.ts
```

Suppress a genuine false positive with a comment containing `nja-lint-ignore` on that line.

A whole file can skip rules only when the skill documents the exception. The file carries
`// nja-lint-ignore-file: <name>` in its first 5 lines, and a reference doc under
`nja-architecture/references/` carries the matching marker:

```markdown
<!-- nja-lint-exception: "cross-tenant administrative read repository" files=*.admin.repository.ts rules=raw-neo4j-records,raw-neo4j-query,manual-query-no-company-scope -->
```

When the name matches and the file's basename matches the glob, only the listed rules are
skipped for that file. A header that names no documented exception, or sits on a file the
glob does not match, is itself a **BLOCKING** `undocumented-file-exception`. So a new kind
of exception needs a skill change first, not just a comment.

**3. `SubagentStop` gate** (`hooks/subagent-architecture-gate.sh`) — runs when a sub-agent
finishes, and lints only the files that sub-agent edited (the `Edit`/`Write`/`MultiEdit`
calls in its own transcript; edits made through Bash are not seen). If any **BLOCKING**
violation remains, it blocks the sub-agent and hands it the violation list as its next
instruction, so it fixes them before its report reaches you. It blocks at most 3 times per
sub-agent, then lets it finish. Grep-fast, no build or tests. Turn it off with
`NJA_GATE_DISABLE=1` or `touch .claude/nja-gate-off` in the checkout.

The main-session `Stop` gate (`hooks/architecture-gate.sh`) is intentionally off: the
script stays in the repo but is not wired in `hooks.json`.

## Install

```bash
# Add the marketplace
/plugin marketplace add carlonicora/nja

# Install the plugin
/plugin install nja@nja
```

Once installed, the skills activate automatically when their triggering conditions are
met, or you can invoke one directly (e.g. `/nja-verify`).

## Adapting to your repo

The skills assume the conventional layout of a nestjs-neo4jsonapi + nextjs-jsonapi
monorepo:

- `apps/api` — NestJS + Neo4j backend
- `apps/web` — Next.js frontend
- `packages/*` — shared libraries (including a shared-types package)

Some commands in `nja-generate` reference workspace package names via placeholders:

| Placeholder | Replace with |
|---|---|
| `<api-app>` | the `pnpm --filter` name of your NestJS API package |
| `<web-app>` | the `pnpm --filter` name of your Next.js web package |
| `@<scope>/shared` | your shared-types package name |

The module generators themselves ship with `@carlonicora/nestjs-neo4jsonapi` and
`@carlonicora/nextjs-jsonapi`, so `nja-generate` works in any repo that depends on them.

## Layout

```
nja/
├── .claude-plugin/
│   └── marketplace.json        # marketplace manifest
└── nja/                        # the plugin
    ├── .claude-plugin/
    │   └── plugin.json         # plugin manifest
    ├── hooks/
    │   ├── hooks.json                     # PreToolUse + SubagentStop wiring
    │   ├── remind-architecture.sh         # PreToolUse soft reminder
    │   ├── subagent-architecture-gate.sh  # SubagentStop gate (deterministic)
    │   └── architecture-gate.sh           # main-session Stop gate (not wired, kept off)
    ├── scripts/
    │   ├── nja-lint.sh             # deterministic anti-pattern checker
    │   ├── nja-detect.sh           # "is this an nja project?" guard
    │   ├── nja-deps-lib.sh         # sourced helpers for the deps scripts below
    │   ├── nja-deps-sweep.sh       # dependency sweep (manifests + catalog + overrides)
    │   ├── nja-deps-doctor.sh      # post-install duplicate-resolution checks
    │   ├── nja-dev-boot.sh         # boot/verify/tear down a real `pnpm dev`
    │   ├── nja-fleet-lib.sh        # sourced helpers for the fleet scripts
    │   ├── nja-fleet-survey.sh     # discovers the nja repos on this machine
    │   ├── nja-fleet-waves.sh      # runs a staged command across the fleet
    │   └── nja-linear.sh           # the only code that talks to Linear's API
    ├── skills/
    │   ├── nja-architecture/   # routing table + references/ + evals/
    │   ├── nja-generate/       # generator workflow + references/
    │   ├── nja-arrows/         # Arrows.app diagram → structure/*.json → nja-generate
    │   ├── nja-writing-plan/   # plan-writing wrapper
    │   ├── nja-delegate-implementation/  # plan → prompt file for a fresh session
    │   ├── nja-verify/         # architecture audit
    │   ├── nja-e2e/            # Given/When/Then list → Playwright specs
    │   ├── nja-pre-release/    # lint/build/test gates + e2e
    │   ├── nja-create-verifier/    # generates a project-local verify-<app> skill
    │   ├── nja-maintain-verifier/  # keeps that skill and its feature map honest
    │   ├── nja-blast-radius/   # what a change breaks outside its own diff
    │   ├── nja-interrogate/    # multi-reviewer adversarial review + references/
    │   ├── nja-reflect/        # session → skill edits + references/
    │   ├── nja-automate-me/    # your working style → a <handle>-mode skill + references/
    │   ├── nja-unslop/         # cut AI tells from any prose
    │   ├── nja-update-dependencies/  # dependency sweep workflow + references/ + evals/
    │   ├── nja-update-fleet/         # fleet sweep workflow + references/ + evals/
    │   ├── nja-handoff/        # session → handoff document for the next agent
    │   ├── nja-linear-setup/   # connect a repo to a Linear team, ensure labels
    │   ├── nja-linear-capture/ # finding → Linear issue in Todo
    │   ├── nja-linear-next/    # list open issues, you pick
    │   └── nja-linear-start/   # issue → In Progress → work → In Review
    └── tests/                  # bash test suite for scripts/*.sh (run.sh, lib.sh, fixtures/)
        └── fixtures/
            └── fake-linear/    # fake curl for the nja-linear.sh tests
```

## License

MIT. Parts of this plugin are adapted from [pstack](https://github.com/cursor/plugins/tree/main/pstack)
(MIT, Copyright (c) 2026 Lauren Tan) — see [`nja/THIRD_PARTY.md`](nja/THIRD_PARTY.md).
