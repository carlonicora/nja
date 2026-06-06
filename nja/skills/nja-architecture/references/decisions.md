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
last_updated: "2026-03-01"
---

# Architecture Decision Records

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
