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
| **`nja-writing-plan`** | Writing an implementation plan. Wraps `superpowers:writing-plans` with architecture compliance: inline citations to canonical examples, a structured self-audit, skill-wins-over-plan dispatch, and an audit step in the final verification task. |
| **`nja-verify`** | Auditing uncommitted changes against the architecture rules — before committing, before handing work back, or after generating/implementing a module. Read-only: it reports violations with evidence, it does not fix them. |

`nja-architecture` is the authority; `nja-generate`, `nja-writing-plan`, and `nja-verify`
all invoke it and cite its reference docs.

## Enforcement (hooks + linter)

The plugin is **self-enforcing on install** — three layers, escalating from advisory to
deterministic. All require `jq` on `PATH`; hooks run harness-side and cost **zero model
context**.

**1. `PreToolUse` reminder** (`hooks/remind-architecture.sh`) — fires before every
`Edit`/`Write`/`MultiEdit`. When the target file matches the `nja-architecture` routing
table (e.g. an `*.repository.ts` under `apps/api/src/features`), it injects a reminder to
invoke the skill and points at the exact reference doc. **Soft** — reminder only, never
blocks.

**2. `nja-lint`** (`scripts/nja-lint.sh`) — a zero-dependency, deterministic checker for
the greppable anti-patterns in `nja-architecture/references/anti-patterns.md`
(`fetch()` in frontend services, raw `result.records`, manual `SKIP/LIMIT`, `asChild`,
`@radix-ui` imports, controllers importing repositories, `@IsString()` on date DTOs, …).
Two tiers — **BLOCKING** (never correct) and **WARN** (heuristic). Run it directly:

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
    │   └── nja-lint.sh             # deterministic anti-pattern checker
    └── skills/
        ├── nja-architecture/   # routing table + references/ + evals/
        ├── nja-generate/       # generator workflow + references/
        ├── nja-writing-plan/   # plan-writing wrapper
        └── nja-verify/         # architecture audit
```

## License

MIT
