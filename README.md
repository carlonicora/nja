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
| **`nja-writing-plan`** | Writing an implementation plan. Wraps `superpowers:writing-plans` with architecture compliance: inline citations to canonical examples, a structured self-audit, skill-wins-over-plan dispatch, and an audit step in the final verification task. |
| **`nja-delegate-implementation`** | Handing a written plan to a fresh session to implement. Writes a temp markdown file that *is* the prompt for that session: `@`-links to the spec and plan, the context that dies with the conversation (session decisions, repo state, resolved commands), and the execution protocol — parallel task dispatch, no per-task tests, one lint/build/test at the end, `nja-verify` audit, no commits. |
| **`nja-verify`** | Auditing uncommitted changes against the architecture rules — before committing, before handing work back, or after generating/implementing a module. Read-only: it reports violations with evidence, it does not fix them. |
| **`nja-update-dependencies`** | Updating or upgrading npm dependencies across the monorepo — root, apps, and `packages/*`. Sweeps all three surfaces (workspace manifests, pnpm `catalog:`, and concrete `overrides:` — `ncu` sees only the first), holds back the majors that break this stack, then verifies with lint, build, a real `pnpm dev` boot check, and tests. Leaves everything uncommitted for you to test and commit. |
| **`nja-update-fleet`** | Updating dependencies across **multiple** nja monorepos at once. Discovers every nja repo on the machine, computes one fleet-wide version set, sweeps and validates both shared libraries against every consumer *before* pushing, releases each library exactly once, then verifies every app with lint, build, tests and a serialized `pnpm dev` boot. Never commits an app repo. |
| **`nja-handoff`** | Ending a session whose work another agent will continue. Compacts the conversation into a handoff document (saved to the OS temp dir, sensitive data redacted) with a "suggested skills" section, referencing existing artifacts instead of duplicating them. |

`nja-architecture` is the authority; `nja-generate`, `nja-writing-plan`, and `nja-verify`
all invoke it and cite its reference docs.

The plan-driven path runs `nja-writing-plan` → `nja-delegate-implementation` → (fresh
session) → `nja-verify`.

`nja-update-dependencies` ships three deterministic scripts — `nja-deps-sweep.sh`,
`nja-deps-doctor.sh`, and `nja-dev-boot.sh` — in the same spirit as `nja-lint.sh`: grep-fast,
zero-model-context checks the skill drives rather than reimplements. `nja-dev-boot.sh` tears
the dev stack down by process group, never by name pattern — the same discipline `nja-lint`
enforces for architecture, applied here to killing processes safely.

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
controllers importing repositories; plus WARN-level heuristics like raw `result.records`
access and `@IsString()` on date DTOs).
Two tiers — **BLOCKING** (calibrated near-zero false positives) and **WARN** (heuristic).
The `fetch` rule targets only literal own-API calls, so S3 presigned uploads and local
functions named `fetch()` are not flagged. Run it directly:

```bash
# check specific files, or omit args to check `git status` (the uncommitted diff)
nja/scripts/nja-lint.sh apps/api/src/features/crm/account/repositories/account.repository.ts
```

Suppress a genuine false positive with a comment containing `nja-lint-ignore` on that line.

**3. `Stop` gate** (`hooks/architecture-gate.sh`) — runs `nja-lint` over the uncommitted
diff when Claude tries to end its turn. If any **BLOCKING** violation remains, it **blocks
completion** and feeds the violation list back, so a turn cannot be declared "done" with
mechanical architecture violations in the diff. It's grep-fast (sub-second) — no build or
tests — and is soft on non-git directories and when warnings are the only finding.

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
    │   ├── hooks.json              # PreToolUse + Stop wiring
    │   ├── remind-architecture.sh  # PreToolUse soft reminder
    │   └── architecture-gate.sh    # Stop gate (deterministic)
    ├── scripts/
    │   ├── nja-lint.sh             # deterministic anti-pattern checker
    │   ├── nja-detect.sh           # "is this an nja project?" guard
    │   ├── nja-deps-lib.sh         # sourced helpers for the deps scripts below
    │   ├── nja-deps-sweep.sh       # dependency sweep (manifests + catalog + overrides)
    │   ├── nja-deps-doctor.sh      # post-install duplicate-resolution checks
    │   └── nja-dev-boot.sh         # boot/verify/tear down a real `pnpm dev`
    ├── skills/
    │   ├── nja-architecture/   # routing table + references/ + evals/
    │   ├── nja-generate/       # generator workflow + references/
    │   ├── nja-arrows/         # Arrows.app diagram → structure/*.json → nja-generate
    │   ├── nja-writing-plan/   # plan-writing wrapper
    │   ├── nja-delegate-implementation/  # plan → prompt file for a fresh session
    │   ├── nja-verify/         # architecture audit
    │   ├── nja-update-dependencies/  # dependency sweep workflow + references/ + evals/
    │   ├── nja-update-fleet/         # fleet sweep workflow + references/ + evals/
    │   └── nja-handoff/        # session → handoff document for the next agent
    └── tests/                  # bash test suite for scripts/*.sh (run.sh, lib.sh, fixtures/)
```

## License

MIT
