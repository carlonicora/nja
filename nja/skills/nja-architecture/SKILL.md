---
name: nja-architecture
description: Use BEFORE editing or creating any TypeScript file under apps/api/src/features, apps/web/src/features, or packages/*/src in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo. Routes to the layer-specific reference doc (entity, DTO, repository, service, controller, model, interface, service, component) and surfaces NestJS+Neo4j+JSON:API rules. Required reading before backend or frontend feature work.
---

# Architecture — nestjs-neo4jsonapi + nextjs-jsonapi

> Single source of truth for a nestjs-neo4jsonapi + nextjs-jsonapi monorepo's architecture rules. Use the routing table below to find the references for the file you are about to edit, then read those references BEFORE writing code.

## When to invoke this skill

Invoke whenever the next action is to create or edit a TypeScript file under any of:
- `apps/api/src/features/**`
- `apps/web/src/features/**`
- `packages/*/src/**`

If the task is to create a NEW entity (backend or frontend), use the full-chain rows in the routing table below.

## Routing table (file → references)

> **NOTE:** These patterns mirror this plugin's `hooks/remind-architecture.sh` (a PreToolUse hook that fires before edits and reminds you to invoke this skill). If you change one, change the other.

### Backend (apps/api)

| File pattern | Read references in this order |
|---|---|
| `apps/api/src/features/*/entities/*` | `references/core-principles.md` → `references/backend/01-entity-basics.md` → `references/date-handling.md` (if any field represents a date/datetime) |
| `apps/api/src/features/**/*.dto.ts` (or under `*/dtos/*`) | `references/backend/02-dtos.md` → `references/date-handling.md` (if any attribute is a date/datetime) |
| `apps/api/src/features/**/*.repository.ts` (or under `*/repositories/*`) | `references/backend/03-repositories.md` → `references/anti-patterns.md` → `references/date-handling.md` (if any custom Cypher writes a date/datetime) |
| `apps/api/src/features/**/*.service.ts` (or under `*/services/*`) | `references/backend/04-services.md` |
| `apps/api/src/features/**/*.controller.ts` (or under `*/controllers/*`) | `references/backend/05-controllers.md` → `references/backend/02-dtos.md` |
| `apps/api/src/features/*/agent/**` (agent nodes, prompts, schemas — anything that calls an LLM) | `references/backend/06-llm-calls.md` → `references/backend/04-services.md` |
| Creating a NEW backend entity (full chain) | `references/core-principles.md` → `references/backend/01-entity-basics.md` → `references/backend/02-dtos.md` → `references/backend/03-repositories.md` → `references/backend/04-services.md` → `references/backend/05-controllers.md` → `references/backend/template.md` → `references/date-handling.md` (if any field is a date/datetime) |

### Frontend (apps/web)

| File pattern | Read references in this order |
|---|---|
| `apps/web/src/features/*/data/*Interface.ts` | `references/frontend/02-interfaces.md` → `references/date-handling.md` (if any getter is `Date`) |
| `apps/web/src/features/*/data/*Service.ts` | `references/frontend/03-services.md` → `references/anti-patterns.md` |
| `apps/web/src/features/*/data/*.ts` (other) | `references/frontend/01-models.md` → `references/date-handling.md` (if `rehydrate()` or `createJsonApi()` touches a date/datetime) |
| `apps/web/src/features/*/components/**` (or `**/*.tsx` under features) | `references/frontend/04-components.md` → `references/frontend/05-typography.md` (if the edit styles text) → `references/frontend/06-blocknote.md` (if the file touches a rich-text field: `description`, `content`, `notes`) |
| Creating a NEW frontend entity (full chain) | `references/core-principles.md` → `references/frontend/02-interfaces.md` → `references/frontend/01-models.md` → `references/frontend/03-services.md` → `references/frontend/04-components.md` → `references/frontend/05-typography.md` → `references/frontend/template.md` → `references/date-handling.md` (if any field is a date/datetime) → `references/frontend/06-blocknote.md` (if any field is rich text) |

### Shared packages

| File pattern | Read |
|---|---|
| `packages/nestjs-neo4jsonapi/src/*` | `packages/nestjs-neo4jsonapi/CLAUDE.md` + `apps/api/CLAUDE.md` |
| `packages/nextjs-jsonapi/src/*` | `packages/nextjs-jsonapi/CLAUDE.md` + `apps/web/CLAUDE.md` |
| `packages/shared/src/*` | `packages/shared/CLAUDE.md` |

### Code review or debugging

Read `references/anti-patterns.md` first, then the layer-specific reference for the file under review.

### Cross-cutting (any file)

| Situation | Read |
|---|---|
| About to report work as done, fixed, or passing | `references/discipline.md` §1 Prove it works |
| Debugging anything | `references/discipline.md` §2 Fix root causes |
| Designing a type, an entity descriptor, or a signature | `references/discipline.md` §3 Type system discipline |
| Writing the same instruction or correction a second time | `references/discipline.md` §4 Encode lessons in structure |
| Working in a worktree, or alongside another session | `references/discipline.md` §5 Separate before serialising shared state |

## Non-negotiable rules (mirror of root CLAUDE.md guardrails)

> The canonical copy of these rules lives in the repository root `CLAUDE.md`. This is a survival summary in case CLAUDE.md context was compacted away. If anything here conflicts with `CLAUDE.md`, `CLAUDE.md` wins.

### Protocol
- All API traffic uses **JSON:API**. Never construct JSON:API payloads manually — use the model.

### Backend (NestJS + Neo4j)
- Extend `AbstractRepository` and `AbstractService` — never bypass the framework
- Use `buildDefaultMatch()` for queries — auto-injects company filtering (security-critical)
- Use `readOne()` / `readMany()` — never return raw `result.records`
- Use `{CURSOR}` placeholder for paginated queries — never manual `SKIP`/`LIMIT`
- Pass `serialiser` to `initQuery()` — without it, type mapping fails
- Use `createCrudHandlers()` / `createRelationshipHandlers()` for standard CRUD
- Use meta constants for endpoint paths — never hardcode strings
- Use DTOs for request validation
- Always parameterized Cypher — never string interpolation
- Controllers call services, never repositories directly

### Frontend (Next.js)
- Use `callApi()` — never `fetch()` directly
- Implement `rehydrate()` and `createJsonApi()` on every model
- Use `EndpointCreator` for URLs — never hardcode endpoint strings
- Always pass `type: Modules.X` in `callApi()` calls
- Never use `overridesJsonApiCreation` without a dedicated model method
- Never construct JSON:API payloads manually — the model handles serialization
- This project uses **Base UI** (not Radix). Never use `asChild`. Never wrap `<Button>` inside trigger components. Use the `render` prop.

### Testing (cross-cutting)

- The test runner is **Vitest**. A `jest.*` call, a `jest.config.js`, a `jest-e2e.json`,
  or a `jest` / `ts-jest` / `@types/jest` dependency is a defect, not a style choice —
  fix it rather than matching it
- Mock with `vi.fn()` / `vi.mock()` / `vi.spyOn()`. A `vi.mock` factory CANNOT reference a
  module-scope binding (Vitest hoists the factory above it) — take the value from
  `vi.hoisted()` instead. Jest allowed this; Vitest does not
- `vi.importActual()` is async. A factory using it MUST be `async` — unlike Jest's
  synchronous `jest.requireActual()`
- With `globals: true`, `describe` / `it` / `expect` need no import, but **`vi` is not a
  global** — import it from `vitest` in any file that uses it
- An api `vitest.config.ts` using `unplugin-swc` MUST set `oxc: false`. Vitest 4 handles
  the default transform with Oxc, which makes `esbuild: false` inert; without it Oxc owns
  the TypeScript transform and `decoratorMetadata` — which every reflection-resolved DI
  token depends on — is not guaranteed
- The `include` pattern MUST cover every directory holding specs. `src/**` alone silently
  drops specs under `scripts/**`, and the suite still reports green
- **Vitest mocks are strict about exports.** Jest returned `undefined` for a key the factory
  did not declare; Vitest throws `No "X" export is defined on the … mock`. When stubbing a
  large barrel, wrap the factory object in `new Proxy({…}, { has: () => true })` rather than
  inventing stub values — a made-up value can flip a falsy check and silently change what a
  test proves. If the mocked module is awaited, the Proxy must also answer `then` with
  `undefined`, or Vitest treats the stub as a thenable
- **Vitest CONSTRUCTS a `mockImplementation` when the subject is called with `new`.** Jest
  called the implementation and used its return value. An arrow function therefore throws
  "is not a constructor" — use a `function` expression for any stub reached via `new X()`
- `vi.mock()` takes NO third argument. Jest's `{ virtual: true }` is a tsc error (TS2554);
  drop it — the runtime already ignored it
- A spec MUST import every test global it uses (`describe` / `it` / `expect` / `beforeEach`
  / `afterEach`) unless the package's `tsconfig` sets `types: ["vitest/globals"]`. A file
  that imports only `vi` and then calls bare `expect()` passes at runtime under
  `globals: true` but fails `tsc` with TS2304 / TS2582

### Dates and DateTimes (cross-cutting)
- A calendar date (no time) MUST be `type: "date"` in the entity descriptor — never `"string"`
- A point-in-time (timestamped event) MUST be `type: "datetime"` — never `"string"`, never `"date"`
- Custom Cypher writes MUST cast: `date(left($v, 10))` for dates, `datetime($v)` for datetimes — the framework only auto-casts the standard `create`/`put`/`patch` path
- DTOs MUST validate with `@IsDateString()` (never `@IsString()`) on date/datetime attributes
- Frontend interfaces MUST type date/datetime getters as `Date` (or `Date | undefined`) and `rehydrate()` MUST parse with `new Date(...)`
- Frontend `createJsonApi()` MUST use `formatLocalDate(d)` (imported from `@carlonicora/nextjs-jsonapi/core` — never re-implemented inline) for `type: "date"` fields, and `d.toISOString()` for `type: "datetime"` fields
- Full lifecycle and verification checklist: `references/date-handling.md`

## Reuse before you write

Before writing ANY new component, helper, or utility under `apps/web/src/features`
or `packages/*/src`:

1. **Grep first** — `apps/web/src`, then `packages/nextjs-jsonapi/src`. Reuse with
   props. A near-match adapted through props beats a new file every time.
2. **A named reference is a SPEC, not an example.** When the user points at another
   repo (`~/Development/neural-erp`, a sibling nja monorepo) or at existing code,
   copy it VERBATIM — the step indicator, the footer, the layout — and adapt only
   the data. These repos are deliberately kept identical; a hand-rolled variant is
   drift the user has to hunt down across every repo.
3. **Deviations are proposed, never assumed.** If you believe the reference is
   wrong for this case, say so and get a yes BEFORE writing the alternative.
   Borrowing a reference's logic while silently redesigning its presentation is
   the most common form of this failure.
4. **Existing usage is not proof of correctness.** A helper committed by an earlier
   session can itself be the duplication. Check it against the package and the
   reference repo before extending it — and when it is wrong, delete it and fix
   its callers rather than adding a caller.

## How to use this skill

1. Identify the file you are about to edit.
2. Match it against the routing table above.
3. Read the listed reference(s) in the listed order, BEFORE writing code.
4. If no row matches, read `references/core-principles.md` and ask the user.

## Reference index

| File | Description |
|---|---|
| `references/core-principles.md` | Foundational rules: JSON:API compliance, type safety, security defaults |
| `references/anti-patterns.md` | Common mistakes and how to avoid them |
| `references/discipline.md` | Cross-cutting working discipline: prove it works, fix root causes, type discipline, encode lessons in structure, separate shared state |
| `references/date-handling.md` | Cross-cutting: date/datetime native-storage contract, end-to-end (descriptor → DTO → repository → model) |
| `references/decisions.md` | Architecture Decision Records — why patterns exist |
| `references/feature-template.md` | Feature handbook template |
| `references/backend/01-entity-basics.md` | Entity metadata + Entity Descriptors |
| `references/backend/02-dtos.md` | DTOs for POST/PUT request validation |
| `references/backend/03-repositories.md` | AbstractRepository, Cypher queries, company filtering, pagination |
| `references/backend/04-services.md` | AbstractService, business logic, JSON:API response building |
| `references/backend/05-controllers.md` | HTTP handlers, auth guards, cache invalidation |
| `references/backend/06-llm-calls.md` | LLM call design: inputSchema + .describe() on every field, output schema shape rules, prompt safety, attribution, tools |
| `references/backend/template.md` | Copy-paste template for new backend entities |
| `references/frontend/01-models.md` | AbstractApiData, rehydrate(), createJsonApi() |
| `references/frontend/02-interfaces.md` | TypeScript interfaces for models |
| `references/frontend/03-services.md` | AbstractService, callApi(), EndpointCreator |
| `references/frontend/04-components.md` | Base UI patterns (NOT Radix), render prop, trigger composition |
| `references/frontend/05-typography.md` | Typography roles: one Tailwind recipe per text role, color tokens, header-markup rules |
| `references/frontend/06-blocknote.md` | BlockNote rich-text fields: model conversion, display, editing, emptiness — and the converters never to write |
| `references/frontend/template.md` | Copy-paste template for new frontend entities |
