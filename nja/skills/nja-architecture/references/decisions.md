---
id: decisions
title: "Architecture Decision Records"
applies_to: both
layer: meta
depends_on:
  - core-principles
source_files: []
related_docs:
  - core-principles
  - anti-patterns
enforcement: recommended
last_updated: "2026-10-24"
---

# Architecture Decision Records

## Contents

- Decision Template
- ADR-007: Cross-Tenant Administrative Read Repositories
- ADR-006: Tenancy Declaration for Unscoped Entities
- ADR-005: RBAC via Neo4j Relationship Patterns
- ADR-004: JSON:API as API Protocol
- ADR-003: Neo4j as Primary Database
- ADR-002: pnpm Monorepo with Shared Libraries
- ADR-001: NestJS + Next.js Stack

> Record WHY you chose X over Y. Future-you (and future-Claude) will thank you.
> New decisions are added at the top. Use the template below.

---

## Decision Template

```markdown
## ADR-XXX: [Title]

**Date:** YYYY-MM-DD
**Status:** Accepted | Superseded by ADR-XXX | Deprecated

### Context
What is the issue or situation that motivated this decision?

### Decision
What is the change we're making?

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Option A | ... | ... |
| Option B | ... | ... |

### Consequences
What are the positive and negative results of this decision?
```

---

## ADR-007: Cross-Tenant Administrative Read Repositories

**Date:** 2026-10-24
**Status:** Accepted (decided by the owner)

### Context
Platform-wide admin reports (analytics, token usage, activation) aggregate across every company and return scalar columns such as counts and sums. `buildDefaultMatch()` and `initQuery()` both scope to the caller's company through CLS, so an administrator who also belongs to a company sees only that company; in the token-usage dashboard this produced empty pages with no error. `readOne()`/`readMany()` cannot map scalar rows. Plans kept copying these files as precedent for ordinary repositories, because no rule said where the exception starts and ends.

### Decision
One documented file-level exception: a `*.admin.repository.ts` that opens with `// nja-lint-ignore-file: cross-tenant administrative read repository.` and a rationale, seeds its queries with a private `_adminQuery()` instead of `initQuery()`, maps scalar rows by hand into typed shapes, and is reached only through routes guarded by `@UseGuards(AdminJwtAuthGuard, JwtAuthGuard)` + `@Roles(RoleId.Administrator)`. Rows that return nodes still use `readMany()`. The requirements live in [backend/03-repositories.md](backend/03-repositories.md) § "Exception: cross-tenant administrative read repository". No other file-level lint exception is allowed.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| One named exception with fixed requirements (chosen) | Matches the existing working files; a linter can check the marker; plans can cite it | Hand-mapped rows lose the serialiser's type mapping |
| Framework support for scalar rows in `readMany()` | No exception needed | Library change; CLS scoping in `initQuery()` still needs a bypass |
| No exception, rewrite admin reports | Single rule | Reports would need node-shaped results they do not have |

### Consequences
- A plan or audit may cite the exception only for files that meet every requirement
- Existing code that maps `result.records` outside this exception is a violation, not precedent

---

## ADR-006: Tenancy Declaration for Unscoped Entities

**Date:** 2026-10-15
**Status:** Accepted

### Context
`isCompanyScoped: false` removes the company predicate from every read. Entities that also carry a `description` are listed by the graph catalog and reachable through the assistant and the MCP tools. In a360ai, 48 such descriptors (companies, activity logs, research messages, portal records…) were readable across tenants through `search_entities`, and nothing in the framework distinguished "shared reference data" from "tenant data whose company is one hop away" from "never expose this".

### Decision
An unscoped described descriptor must declare `tenancy`: `"global"` (shared reference data), `{ via: "<relationship key>" }` (one hop to a company-scoped entity or to the company node; `buildDefaultMatch()` emits the predicate), `"self"` (the company entity), or `"internal"` (never catalogued). `defineEntity` throws without it and `GraphCatalogService.buildCatalog()` refuses an undeclared or mis-targeted type at boot. Module visibility is bound to the token's company (`findModuleIdsForUser(userId, companyId)`), not to the union of the user's companies.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Mandatory `tenancy` on unscoped described entities (chosen) | The leak becomes a boot error; one declaration documents the intent; predicate lives in `buildDefaultMatch()` like the company one | Breaking change: every nja app must declare it (apps have 0–80 such descriptors) |
| Catalog-only exclusion of unscoped types | No descriptor changes | HTTP reads stay unscoped; reference data (laws, tariffs) disappears from the assistant |
| Reuse `chat.scope` for tenancy | No new key | `chat.scope` is the proceeding/campaign scope of a chat run and is inert without a scope id; reusing it broke the judgement lookup |
| Per-repository overrides | Local, no framework change | Invisible to the catalog; the next unscoped entity leaks again |

### Consequences
- nestjs-neo4jsonapi 5.0.0 is a major release; every app in the fleet declares `tenancy` on its unscoped described descriptors before bumping
- `"global"` is a statement, not a bypass: tenant data without a company-reaching relationship is `"internal"` until the relationship exists
- `tenancy` covers reads; unscoped entities stay out of `chat.writable` unless their repository guards writes
- Since nestjs-neo4jsonapi 6.6.0 the same declaration also decides what a relationship write may link to: every target id is checked against its label's tenancy (see backend/01-entity-basics.md § "Relationship Writes: the Company Check")
- `via` is single-hop by design; chains are expressed by giving each intermediate entity its own `tenancy`

---

## ADR-005: RBAC via Neo4j Relationship Patterns

**Date:** 2026-02-25
**Status:** In Progress

### Context
The ERP needs role-based access control across all modules. Permissions must be granular (per-module CRUD), auditable, and scoped to companies.

### Decision
Implement RBAC using Neo4j relationship patterns: `(User)-[:HAS_ROLE]->(Role)-[:HAS_PERMISSION]->(Permission)` with dedicated backend and frontend modules.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Neo4j relationship RBAC | Native to graph, flexible, audit trail, company-scoped | More complex queries |
| JWT claims-based | Simple, stateless | Hard to revoke, no audit trail, stale on role change |
| External RBAC service (e.g., Casbin) | Separation of concerns | Network hop, added infrastructure, not graph-native |

### Consequences
- Permissions checked at service/controller level via guards
- All queries already scoped by company; now also by permission
- Role management UI in admin section
- Migration needed to seed default roles and permissions

---

## ADR-004: JSON:API as API Protocol

**Date:** 2024-01-01
**Status:** Accepted

### Context
Needed a standardized API protocol that handles serialization, pagination, relationships, and error formatting consistently across all entities.

### Decision
Use the JSON:API specification with framework-level enforcement via Entity Descriptors (backend) and Model `rehydrate()`/`createJsonApi()` (frontend). Manual JSON:API construction is an anti-pattern.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| JSON:API | Standard spec, auto-serialization, relationship handling, pagination built-in | Learning curve, verbose payloads |
| REST + custom format | Flexible, familiar | Inconsistent, manual serialization work |
| GraphQL | Flexible queries, typed schema | Different paradigm, over-fetching prevention complexity |

### Consequences
- All entities follow the Descriptor pattern (backend) and Model pattern (frontend)
- Manual JSON:API construction is forbidden (see [anti-patterns.md](anti-patterns.md))
- Framework handles serialization end-to-end via `AbstractService` and `AbstractApiData`
- Pagination is automatic via `{CURSOR}` placeholder

---

## ADR-003: Neo4j as Primary Database

**Date:** 2024-01-01
**Status:** Accepted

### Context
ERP data is highly relational: accounts → persons → locations → opportunities → orders → invoices. Need efficient traversal of complex relationship chains.

### Decision
Use Neo4j graph database with Cypher queries. All data access goes through `AbstractRepository` with automatic company filtering via `buildDefaultMatch()`.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| Neo4j | Native graph traversal, relationship-first model, company scoping via graph patterns | Cypher learning curve, fewer ORM tools |
| PostgreSQL | Mature, rich ecosystem, JSONB for flexibility | JOINs for deep relationships, complex recursive queries |
| MongoDB | Flexible schema, easy to start | No native relationships, denormalization complexity |

### Consequences
- All data access through `AbstractRepository` — never raw Neo4j driver calls
- Company filtering is automatic and cannot be bypassed (security by default)
- Cypher queries must use parameterized values (never string interpolation)
- Relationship traversal is natural and performant

---

## ADR-002: pnpm Monorepo with Shared Libraries

**Date:** 2024-01-01
**Status:** Accepted

### Context
Frontend and backend share types, constants, and patterns. Need consistent deployment and version management across packages.

### Decision
pnpm workspace monorepo with `apps/` (api, web) and `packages/` (nestjs-neo4jsonapi, nextjs-jsonapi, shared). Both framework libraries are published to npm.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| pnpm monorepo | Shared deps, atomic commits, workspace protocol | Build complexity, package version management |
| Separate repos | Independent deployment, clear boundaries | Type drift, version mismatches, duplicated code |
| Turborepo | Built-in caching, parallel builds | Additional tooling dependency |

### Consequences
- Changes to shared packages require version bumps
- Both libraries published as `@carlonicora/nestjs-neo4jsonapi` and `@carlonicora/nextjs-jsonapi`
- Single `pnpm test` runs all tests across packages
- Atomic commits ensure frontend and backend stay in sync

---

## ADR-001: NestJS + Next.js Stack

**Date:** 2024-01-01
**Status:** Accepted

### Context
Building an ERP SaaS platform. Need a type-safe backend with dependency injection and a modern frontend with SSR capability.

### Decision
NestJS for backend (TypeScript, DI, modular architecture) and Next.js for frontend (React, SSR, file-based routing). Both use TypeScript for end-to-end type safety.

### Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| NestJS + Next.js | Full TypeScript, DI pattern, SSR, rich ecosystems | Two frameworks to maintain |
| Express + React SPA | Simple, widely known | No DI, no SSR, manual type wiring |
| tRPC + Next.js | End-to-end type safety, no serialization | Tight coupling, harder to add non-TS clients |

### Consequences
- Shared TypeScript types across the entire stack
- DI pattern in backend enables clean testing and modularity
- SSR provides initial page load performance
- Component-based frontend with established patterns
