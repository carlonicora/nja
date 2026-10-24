---
id: backend-03-repositories
title: "Backend: Repositories"
applies_to: backend
layer: repository
depends_on:
  - backend-01-entity-basics
source_files:
  - "apps/api/src/features/*/repositories/*.ts"
  - "packages/nestjs-neo4jsonapi/src/core/AbstractRepository.ts"
related_docs:
  - backend-04-services
  - anti-patterns
  - backend-template
enforcement: critical
last_updated: "2026-10-24"
---

# Backend: Repositories

## Contents

- WHEN TO USE
- CRITICAL RULES
- ENFORCEMENT CHECKPOINT
- DECISION MATRIX
- COMMON MISTAKES
- RELATED FILES
- Repository Pattern
- WRONG vs RIGHT Examples
- Error Handling
- Exception: cross-tenant administrative read repository

---

## WHEN TO USE
Read this file when:
- Creating a new repository
- Adding custom query methods
- Overriding `buildReturnStatement()` for computed data
- Understanding pagination and company filtering

---

## CRITICAL RULES

1. **ALWAYS use `readOne` or `readMany`** - They return typed objects, never raw Neo4j records. The only exception is the documented exception below ("Exception: cross-tenant administrative read repository").
2. **NEVER return raw Neo4j records** - No `result.records[0]`, except the documented exception below ("Exception: cross-tenant administrative read repository").
3. **ALWAYS use `{CURSOR}`** for paginated queries.
4. **Company filtering is automatic** via `buildDefaultMatch()`. For an `isCompanyScoped: false` descriptor the predicate comes from its `tenancy` declaration: `{ via }` walks the named relationship to the owning company (or to the company node itself), `"self"` matches the company node; `"global"` and `"internal"` emit none. Never re-add a company predicate by hand in a query. See [01-entity-basics.md](01-entity-basics.md) § "Company Scope and Tenancy".
   Hand-written Cypher that links client-supplied ids bypasses the generic writers' company check: call `Neo4jService.validateRelatedNodes()` before writing (`validateExistingNodes()` checks existence only). See [01-entity-basics.md](01-entity-basics.md) § "Relationship Writes: the Company Check".
5. **ALWAYS extend `AbstractRepository`** - Get company filtering and typed mapping for free.
6. **Custom Cypher writes to a `"date"` / `"datetime"` field MUST cast the value** — `date(left($v, 10))` or `datetime($v)`. The framework only auto-casts the standard `create`/`put`/`patch` path; ad-hoc `executeInTransaction` blocks bypass it. See [../date-handling.md](../date-handling.md).

---

## ENFORCEMENT CHECKPOINT

> **STOP — Before committing repository code, verify:**
> 1. Does every query use `buildDefaultMatch()` or explicitly join to Company? If no, **STOP** — security vulnerability. Except the documented exception below ("Exception: cross-tenant administrative read repository").
> 2. Are you returning typed objects via `readOne`/`readMany`? If returning `result.records`, **STOP**. Except the documented exception below ("Exception: cross-tenant administrative read repository").
> 3. Do paginated queries have `{CURSOR}` placeholder? If using manual SKIP/LIMIT, **STOP**.
> 4. Did you pass `serialiser` to `initQuery()`? If no, **STOP** — type mapping will fail.
> 5. Does every custom write to a date/datetime property cast with `date(left($v, 10))` or `datetime($v)`? If you wrote `SET n.foo = $foo` for a temporal field, **STOP**.

---

## DECISION MATRIX

### When to Override `buildReturnStatement()`

| Question | Answer |
|----------|--------|
| Need computed data (counts, sums, aggregations)? | **Override** |
| Need to collect sample/related nodes? | **Override** |
| Standard entity with fields and relationships only? | **Use inherited** |

### When to Add Custom Query Methods

| Question | Answer |
|----------|--------|
| Need specialized filtering (e.g., `/pending`, `/active`)? | **Add custom method** |
| Need complex joins not covered by inherited methods? | **Add custom method** |
| Standard CRUD operations? | **Use inherited methods** |

---

## COMMON MISTAKES

- Returning `result.records[0]` instead of using `readOne()`
- Manual company filtering with `WHERE company.id = $companyId`
- Manual pagination with `SKIP ${offset} LIMIT ${limit}`
- Missing `{CURSOR}` placeholder in paginated queries
- Forgetting to pass `cursor` parameter to `initQuery()`
- Treating a sibling file that maps `result.records` by hand as precedent. Only the documented exception below ("Exception: cross-tenant administrative read repository") allows it, and only when every one of its requirements holds

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [01-entity-basics.md](01-entity-basics.md) | Entity descriptor for computed properties |
| [04-services.md](04-services.md) | Services expose repository methods |
| [../anti-patterns.md](../anti-patterns.md) | Common repository mistakes |

---

## Repository Pattern

```typescript
// gallery.repository.ts
import {
  AbstractRepository,
  companyMeta,
  JsonApiCursorInterface,
  Neo4jService,
  ownerMeta,
  SecurityService,
} from "@carlonicora/nestjs-neo4jsonapi";
import { Injectable } from "@nestjs/common";
import { ClsService } from "nestjs-cls";
import { Gallery, GalleryDescriptor } from "../entities/gallery";
import { galleryMeta } from "../entities/gallery.meta";
import { photographMeta } from "../../photograph/entities/photograph.meta";

@Injectable()
export class GalleryRepository extends AbstractRepository<Gallery, typeof GalleryDescriptor.relationships> {
  protected readonly descriptor = GalleryDescriptor;

  constructor(
    neo4j: Neo4jService,
    securityService: SecurityService,
    clsService: ClsService,
  ) {
    super(neo4j, securityService, clsService);
  }

  /**
   * Override to customize the RETURN statement for all queries
   * This adds computed fields like sample photos and counts
   */
  protected buildReturnStatement(): string {
    return `
      MATCH (${galleryMeta.nodeName}:${galleryMeta.labelName})-[:BELONGS_TO]->(${galleryMeta.nodeName}_${companyMeta.nodeName}:${companyMeta.labelName})
      MATCH (${galleryMeta.nodeName})<-[:CREATED]-(${galleryMeta.nodeName}_${ownerMeta.nodeName}:${ownerMeta.labelName})
      CALL {
        WITH ${galleryMeta.nodeName}
        OPTIONAL MATCH (${galleryMeta.nodeName})-[:CONTAINS]->(photo:${photographMeta.labelName})
        WITH ${galleryMeta.nodeName}, count(photo) as photoCount
        OPTIONAL MATCH (${galleryMeta.nodeName})-[:CONTAINS]->(topPhoto:${photographMeta.labelName})
        WITH ${galleryMeta.nodeName}, photoCount, topPhoto ORDER BY topPhoto.position
        WITH ${galleryMeta.nodeName}, photoCount, collect(topPhoto)[0..4] as samplePhotos
        RETURN samplePhotos, photoCount
      }
      RETURN ${galleryMeta.nodeName},
        ${galleryMeta.nodeName}_${companyMeta.nodeName},
        ${galleryMeta.nodeName}_${ownerMeta.nodeName},
        samplePhotos,
        photoCount
    `;
  }

  /**
   * Custom query: Find galleries with pending reviews
   */
  async findPendingReviews(params: { cursor: JsonApiCursorInterface }): Promise<Gallery[]> {
    const query = this.neo4j.initQuery({
      serialiser: GalleryDescriptor.model,
      cursor: params.cursor,
    });

    query.query = `
      ${this.buildDefaultMatch()}
      MATCH (${galleryMeta.nodeName})<-[access:HAS_ACCESS_TO]-(person:Person)
      WHERE access.completed = false
      ORDER BY ${galleryMeta.nodeName}.createdAt DESC
      {CURSOR}
      ${this.buildReturnStatement()}
    `;

    return this.neo4j.readMany(query);  // Returns Gallery[], not Neo4j records!
  }
}
```

---

## WRONG vs RIGHT Examples

### Raw Records vs Typed Objects

```typescript
// ❌ WRONG - Returning raw Neo4j records
async findById(id: string) {
  const result = await this.neo4j.read(
    `MATCH (n:Gallery {id: $id}) RETURN n`,
    { id }
  );
  return result.records[0];  // RAW RECORD - WRONG!
}

// ✅ CORRECT - Using readOne with serialiser
async findById(params: { id: string }): Promise<Gallery> {
  const query = this.neo4j.initQuery({ serialiser: GalleryDescriptor.model });
  query.queryParams = { ...query.queryParams, searchValue: params.id };
  query.query = `
    ${this.buildDefaultMatch({ searchField: "id" })}
    ${this.buildReturnStatement()}
  `;
  return this.neo4j.readOne(query);  // Returns typed Gallery object
}
```

### Manual vs Automatic Company Filtering

```typescript
// ❌ WRONG - Manual company filtering
async find() {
  const companyId = this.clsService.get("companyId");
  return this.neo4j.read(
    `MATCH (n:Gallery)-[:BELONGS_TO]->(c:Company {id: $companyId}) RETURN n`,
    { companyId }
  );
}

// ✅ CORRECT - buildDefaultMatch() auto-injects company
async find(params: { cursor: JsonApiCursorInterface }): Promise<Gallery[]> {
  const query = this.neo4j.initQuery({
    serialiser: GalleryDescriptor.model,
    cursor: params.cursor,
  });
  query.query = `
    ${this.buildDefaultMatch()}
    ORDER BY ${galleryMeta.nodeName}.name ASC
    {CURSOR}
    ${this.buildReturnStatement()}
  `;
  return this.neo4j.readMany(query);  // Auto-filtered by company!
}
```

### Manual vs Automatic Pagination

```typescript
// ❌ WRONG - Manual pagination
query.query = `MATCH (n) RETURN n SKIP ${offset} LIMIT ${limit}`;

// ✅ CORRECT - Using {CURSOR} placeholder
query.query = `
  MATCH (n:Gallery)
  ORDER BY n.name
  {CURSOR}
  RETURN n
`;  // {CURSOR} replaced with SKIP/LIMIT automatically
```

---

## Error Handling

Repositories should:
- Throw `NotFoundException` when `readOne()` returns null/undefined
- Let database errors propagate (framework handles them)
- Use transactions for multi-step operations

```typescript
async findById(params: { id: string }): Promise<Gallery> {
  const result = await this.neo4j.readOne(query);
  if (!result) {
    throw new NotFoundException(`Gallery with id ${params.id} not found`);
  }
  return result;
}
```

---

## Exception: cross-tenant administrative read repository

<!-- nja-lint-exception: "cross-tenant administrative read repository" files=*.admin.repository.ts rules=raw-neo4j-records,raw-neo4j-query,manual-query-no-company-scope -->

This is the only allowed file-level exception to CRITICAL RULES 1, 2 and 4. Nothing else lifts them for a whole file. Decided by the owner on 2026-10-24 (see [../decisions.md](../decisions.md) § "ADR-007: Cross-Tenant Administrative Read Repositories").

**Canonical example:** `packages/nestjs-neo4jsonapi/src/foundations/analytics/repositories/analytics.admin.repository.ts`. Its sibling `foundations/tokenusage/repositories/tokenusage.admin.repository.ts` has the same shape; in an app, `apps/api/src/features/activation/repositories/activation.admin.repository.ts` with `controllers/activation.admin.controller.ts` follows it.

### When it applies

All of these must be true:

- The repository serves a platform-wide administrative report that reads across every company at once (dashboards such as analytics, token usage, activation).
- Its queries `RETURN` scalar columns (counts, sums, buckets, labels), not graph nodes. `readOne()`/`readMany()` cannot map scalar rows, because the entity factory expects nodes.
- Any query that returns a node still goes through `readOne()`/`readMany()` with a serialiser. The exception covers scalar rows only.

It does not apply to anything a company user can reach, to writes, or to a report about the caller's own company. Those follow the normal rules above.

### Why the normal path is wrong here

- `buildDefaultMatch()` scopes to the caller's company through CLS. A platform report must not be scoped to the administrator's company.
- `initQuery()` prepends its own CLS-scoped company `MATCH` whenever the caller's CLS carries a `companyId`. An administrator who also belongs to a company does, so every aggregation shrinks to that one company. In the token-usage dashboard this returned zero rows and the page rendered as a successful, empty report.

### Requirements

1. The file is named `*.admin.repository.ts`.
2. The first line is exactly:

   ```typescript
   // nja-lint-ignore-file: cross-tenant administrative read repository.
   ```

   followed by a rationale comment that says why `buildDefaultMatch()` and `initQuery()` are skipped, why rows are scalar, and which controller gates access.
3. The class still extends `AbstractRepository` (the descriptor only satisfies the base class; nothing goes through the inherited CRUD).
4. Every controller route that reaches the repository is admin-only. In the library that is a class-level `@UseGuards(JwtAuthGuard)` plus `@Roles(SystemRoles.Administrator)` on each route (`analytics.admin.controller.ts`). In an app it is `@UseGuards(AdminJwtAuthGuard, JwtAuthGuard)` plus `@Roles(RoleId.Administrator)` (`activation.admin.controller.ts`).
5. Queries are seeded the way the canonical files do, not with `initQuery()`: a private `_adminQuery()` returns `{ query: "", queryParams: { ... } }` holding only the parameters the report needs. Never bind the caller's own `companyId`. A company filter the administrator picks is passed in explicitly as a request parameter.
6. Queries stay parameterized. Any value that changes the query text (a granularity, a dimension) comes from a lookup table in the file, never from the request string.
7. Rows from `this.neo4j.read(...)` are mapped by hand into a typed shape (an entity type from the feature's `entities/`), converting driver integers to numbers and temporal values with `convertFieldValue`.

```typescript
// activation.admin.repository.ts (shape only)
private _adminQuery(params: { asOf: string; excludeUserIds: string[] }): AdminQuery {
  return { query: "", queryParams: { asOf: params.asOf, excludeUserIds: params.excludeUserIds } };
}

async findSources(params: { excludeUserIds: string[] }): Promise<ActivationSourceEntity[]> {
  const seed = this._adminQuery({ asOf: new Date().toISOString(), excludeUserIds: params.excludeUserIds });
  seed.query = `
    ...
    RETURN gmSource AS label, count(*) AS letIn
  `;
  const result = await this.neo4j.read(seed.query, seed.queryParams);
  return (result.records as any[]).map((r) => ({
    id: String(r.get("label")),
    label: String(r.get("label")),
    letIn: int(r.get("letIn")),
  })) as ActivationSourceEntity[];
}
```

A repository that misses any requirement is not covered by this exception, and every rule above applies to it in full.

---

**Next**: See [04-services.md](./04-services.md) for business logic patterns
