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
| Creating a NEW backend entity (full chain) | `references/core-principles.md` → `references/backend/01-entity-basics.md` → `references/backend/02-dtos.md` → `references/backend/03-repositories.md` → `references/backend/04-services.md` → `references/backend/05-controllers.md` → `references/backend/template.md` → `references/date-handling.md` (if any field is a date/datetime) |

### Frontend (apps/web)

| File pattern | Read references in this order |
|---|---|
| `apps/web/src/features/*/data/*Interface.ts` | `references/frontend/02-interfaces.md` → `references/date-handling.md` (if any getter is `Date`) |
| `apps/web/src/features/*/data/*Service.ts` | `references/frontend/03-services.md` → `references/anti-patterns.md` |
| `apps/web/src/features/*/data/*.ts` (other) | `references/frontend/01-models.md` → `references/date-handling.md` (if `rehydrate()` or `createJsonApi()` touches a date/datetime) |
| `apps/web/src/features/*/components/**` (or `**/*.tsx` under features) | `references/frontend/04-components.md` → `references/frontend/05-typography.md` (if the edit styles text) |
| Creating a NEW frontend entity (full chain) | `references/core-principles.md` → `references/frontend/02-interfaces.md` → `references/frontend/01-models.md` → `references/frontend/03-services.md` → `references/frontend/04-components.md` → `references/frontend/05-typography.md` → `references/frontend/template.md` → `references/date-handling.md` (if any field is a date/datetime) |

### Shared packages

| File pattern | Read |
|---|---|
| `packages/nestjs-neo4jsonapi/src/*` | `packages/nestjs-neo4jsonapi/CLAUDE.md` + `apps/api/CLAUDE.md` |
| `packages/nextjs-jsonapi/src/*` | `packages/nextjs-jsonapi/CLAUDE.md` + `apps/web/CLAUDE.md` |
| `packages/shared/src/*` | `packages/shared/CLAUDE.md` |

### Code review or debugging

Read `references/anti-patterns.md` first, then the layer-specific reference for the file under review.

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

### Dates and DateTimes (cross-cutting)
- A calendar date (no time) MUST be `type: "date"` in the entity descriptor — never `"string"`
- A point-in-time (timestamped event) MUST be `type: "datetime"` — never `"string"`, never `"date"`
- Custom Cypher writes MUST cast: `date(left($v, 10))` for dates, `datetime($v)` for datetimes — the framework only auto-casts the standard `create`/`put`/`patch` path
- DTOs MUST validate with `@IsDateString()` (never `@IsString()`) on date/datetime attributes
- Frontend interfaces MUST type date/datetime getters as `Date` (or `Date | undefined`) and `rehydrate()` MUST parse with `new Date(...)`
- Frontend `createJsonApi()` MUST use `formatLocalDate(d)` (imported from `@carlonicora/nextjs-jsonapi/core` — never re-implemented inline) for `type: "date"` fields, and `d.toISOString()` for `type: "datetime"` fields
- Full lifecycle and verification checklist: `references/date-handling.md`

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
| `references/date-handling.md` | Cross-cutting: date/datetime native-storage contract, end-to-end (descriptor → DTO → repository → model) |
| `references/decisions.md` | Architecture Decision Records — why patterns exist |
| `references/feature-template.md` | Feature handbook template |
| `references/backend/01-entity-basics.md` | Entity metadata + Entity Descriptors |
| `references/backend/02-dtos.md` | DTOs for POST/PUT request validation |
| `references/backend/03-repositories.md` | AbstractRepository, Cypher queries, company filtering, pagination |
| `references/backend/04-services.md` | AbstractService, business logic, JSON:API response building |
| `references/backend/05-controllers.md` | HTTP handlers, auth guards, cache invalidation |
| `references/backend/template.md` | Copy-paste template for new backend entities |
| `references/frontend/01-models.md` | AbstractApiData, rehydrate(), createJsonApi() |
| `references/frontend/02-interfaces.md` | TypeScript interfaces for models |
| `references/frontend/03-services.md` | AbstractService, callApi(), EndpointCreator |
| `references/frontend/04-components.md` | Base UI patterns (NOT Radix), render prop, trigger composition |
| `references/frontend/05-typography.md` | Typography roles: one Tailwind recipe per text role, color tokens, header-markup rules |
| `references/frontend/template.md` | Copy-paste template for new frontend entities |
