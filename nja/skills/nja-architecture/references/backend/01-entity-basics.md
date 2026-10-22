---
id: backend-01-entity-basics
title: "Backend: Entity Basics"
applies_to: backend
layer: entity
depends_on:
  - core-principles
source_files:
  - "apps/api/src/features/*/entities/*.ts"
  - "apps/api/src/features/*/entities/*.meta.ts"
related_docs:
  - backend-02-dtos
  - backend-03-repositories
  - backend-template
enforcement: critical
last_updated: "2026-10-15"
---

# Backend: Entity Basics

## Contents

- WHEN TO USE
- CRITICAL RULES
- ENFORCEMENT CHECKPOINT
- DECISION MATRIX
- COMMON MISTAKES
- RELATED FILES
- Entity Metadata
- Entity Type Definition
- Entity Descriptor Definition
- Company Scope and Tenancy
- Field Types

---

## WHEN TO USE
Read this file when:
- Creating a new entity
- Adding/modifying fields on an existing entity
- Adding/modifying relationships
- Adding computed properties or transforms

---

## CRITICAL RULES

1. **Entity Descriptor is the single source of truth** - Fields, relationships, and computed properties are all defined here.
2. **Metadata file is separate** - JSON:API type, endpoint, Neo4j label in `.meta.ts` file.
3. **Export both the type and the descriptor** - `export type Example = ...` and `export const ExampleDescriptor = ...`
4. **An unscoped described entity declares its tenancy** - `isCompanyScoped: false` together with a `description` requires `tenancy` (`"global"` | `"self"` | `"internal"` | `{ via: "<relationship key>" }`). `defineEntity` throws without it and the graph catalog refuses the type at boot (nestjs-neo4jsonapi 5.0.0+).
5. **A relationship write checks every target against its label's tenancy** - `create`, `put`, `patch` and `addToRelationship` refuse a target id of another company with the same 400 as a missing id (nestjs-neo4jsonapi 6.6.0+). A second descriptor of a label owned elsewhere declares `isProjection: true`, or the app does not boot (6.6.1+). Hand-written relationship Cypher calls `Neo4jService.validateRelatedNodes` itself.

---

## ENFORCEMENT CHECKPOINT

> **STOP — Before committing entity code, verify:**
> 1. Is the Descriptor exported alongside the type? If no, **STOP**.
> 2. Are computed values in `computed`, not `fields`? If a derived value is in `fields`, **STOP**.
> 3. Are relationship directions correct from THIS entity's perspective? If unsure, **STOP** and check the Decision Matrix below.
> 4. Is the model registered in the module's `onModuleInit()`? If no, **STOP**.
> 5. Is the entity `isCompanyScoped: false` AND does it carry a `description`? Then is `tenancy` declared, and does a `via` key point at a company-scoped entity or at the company itself? If no, **STOP** — the app will not boot.

---

## DECISION MATRIX

### Field vs Computed Property

| Question | Answer |
|----------|--------|
| Is the value stored directly in Neo4j node? | **Field** |
| Is it derived from query results (count, sum, aggregation)? | **Computed** |
| Does it come from related nodes collected in query? | **Computed** |
| Is it a simple atomic value (string, number, boolean)? | **Field** |

### Relationship Direction

| Question | Use Direction |
|----------|---------------|
| Does this entity OWN/CREATE/CONTAIN the related entity? | `direction: "out"` |
| Is this entity OWNED_BY/BELONGS_TO the related entity? | `direction: "in"` |
| Example: Gallery CONTAINS Photographs | `direction: "out"` |
| Example: User CREATED Gallery | `direction: "in"` (from Gallery's perspective) |

### When to Use Edge Properties

| Question | Answer |
|----------|--------|
| Does the relationship need metadata (position, code, timestamp)? | Add `fields` array |
| Is it just a simple association? | No `fields` array needed |
| Example: position of photo in gallery | `fields: [{ name: "position", type: "number" }]` |

### Company Scope and Tenancy

| The entity… | Declare |
|---|---|
| belongs to one company (the default) | `isCompanyScoped: true` (or omit it); the framework adds the `BELONGS_TO` edge and the read predicate |
| is reference data every company reads (laws, tariffs, feature flags, how-tos) | `isCompanyScoped: false, tenancy: "global"` |
| reaches its company through ONE relationship on this descriptor (a message → its conversation, a line → its invoice) | `isCompanyScoped: false, tenancy: { via: "<relationship key>" }` — the target must be company-scoped or be the company itself |
| IS the company | `isCompanyScoped: false, tenancy: "self"` |
| is an auth/ingestion/admin record the assistant must never see | `isCompanyScoped: false, tenancy: "internal"` (not catalogued; reads unchanged) |
| has no relationship that reaches a company and is not reference data | `"internal"` until a company relationship exists — never `"global"` to make it boot |
| mixes platform rows (no company edge) with company-owned rows, and a relationship write may link a platform row or one of the caller's own rows, never another company's (the library's `Role`) | `linkScope: "own-or-platform"` on THIS (the target) descriptor — valid only on a company-scoped or `tenancy: { via }` entity; `defineEntity` throws otherwise |
| has ONE relationship that legitimately crosses tenants (a player's character in the player's company joining a campaign owned by the GM's company; the library's `AiConnection.company`) | `crossCompany: true` on that relationship — the write checks existence only for it |
| is another descriptor of a label owned by a different descriptor (portal projection, count, OAuth row, lookup) | `isProjection: true`, with a one-line comment naming the owner — the label's relationship rule then comes from the owner only |

---

## COMMON MISTAKES

- Putting computed values in `fields` instead of `computed`
- Wrong relationship direction (remember: from THIS entity's perspective)
- Missing `dtoKey` on relationships (defaults to relationship name)
- Forgetting to export the descriptor type
- Setting `isCompanyScoped: false` on an entity with a `description` and no `tenancy` (boot error), or declaring `"global"` on tenant data just to make it boot (every company's rows become visible to the assistant)
- A second descriptor of a label (portal projection, count, lookup) with different tenancy and no `isProjection: true` (boot error since 6.6.1; before it, the looser descriptor silently downgraded the label's relationship check to existence only), or "fixing" that boot error by changing the owner's tenancy to match the projection
- Writing relationships with hand-written Cypher without calling `Neo4jService.validateRelatedNodes` (the generic writers' company check is bypassed and a client can link another company's node)

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [02-dtos.md](02-dtos.md) | After defining entity, create DTOs |
| [03-repositories.md](03-repositories.md) | When computed properties need custom queries |
| [template.md](template.md) | Copy-paste ready code |

---

## Entity Metadata

Every entity has a metadata file defining its JSON:API type and Neo4j labels.

```typescript
// gallery.meta.ts
import { DataMeta } from "@carlonicora/nestjs-neo4jsonapi";

export const galleryMeta: DataMeta = {
  type: "galleries",        // JSON:API type (plural, kebab-case)
  endpoint: "galleries",    // HTTP endpoint path
  nodeName: "gallery",      // Neo4j query variable name
  labelName: "Gallery",     // Neo4j node label (PascalCase)
};
```

---

## Entity Type Definition

```typescript
// gallery.ts
import { Company, defineEntity, Entity, ownerMeta, S3Service, User } from "@carlonicora/nestjs-neo4jsonapi";
import { galleryMeta } from "./gallery.meta";
import { Photograph } from "../../photograph/entities/photograph";
import { photographMeta } from "../../photograph/entities/photograph.meta";
import { Person } from "../../person/entities/person";
import { personMeta } from "../../person/entities/person.meta";

/**
 * Entity Type - TypeScript type definition
 * Extends Entity base type with entity-specific properties
 */
export type Gallery = Entity & {
  name: string;
  description?: string;
  samplePhotographs?: string[];  // Computed - derived from query
  photoCount?: number;           // Computed - count from query
  company: Company;
  owner: User;
  photograph?: Photograph[];
  person?: Person[];
};
```

---

## Entity Descriptor Definition

```typescript
export const GalleryDescriptor = defineEntity<Gallery>()({
  ...galleryMeta,  // Spread metadata

  // Services available in transforms
  injectServices: [S3Service],

  // Field definitions (atomic properties stored in Neo4j node)
  fields: {
    name: { type: "string", required: true },
    description: { type: "string" },
    samplePhotographs: {
      type: "string[]",
      // Transform: convert S3 keys to signed URLs
      transform: async (data, services) => {
        if (!data.samplePhotographs?.length) return [];
        return Promise.all(
          data.samplePhotographs.map((url: string) =>
            services.S3Service.generateSignedUrl({ key: url })
          )
        );
      },
    },
    photoCount: { type: "number" },
  },

  // Computed properties (derived from Neo4j query results)
  computed: {
    samplePhotographs: {
      compute: (params) => {
        if (!params.record.has("samplePhotos")) return [];
        const photographs = params.record.get("samplePhotos") || [];
        return photographs.map((p: any) => p?.properties?.url).filter(Boolean);
      },
    },
    photoCount: {
      compute: (params) => {
        if (!params.record.has("photoCount")) return params.data?.photoCount;
        const count = params.record.get("photoCount");
        if (count?.toNumber) return count.toNumber();
        return Number(count) || 0;
      },
    },
  },

  // Relationship definitions
  relationships: {
    owner: {
      model: ownerMeta,
      direction: "in",           // User CREATED Gallery → incoming to Gallery
      relationship: "CREATED",   // Neo4j relationship type
      cardinality: "one",        // Single relationship
      dtoKey: "owner",           // Key in DTOs
    },
    photograph: {
      model: photographMeta,
      direction: "out",          // Gallery CONTAINS Photographs → outgoing from Gallery
      relationship: "CONTAINS",
      cardinality: "many",       // Collection
      required: false,
      dtoKey: "photographs",
      // Edge properties (stored on the relationship)
      fields: [{ name: "position", type: "number", required: true }],
    },
    person: {
      model: personMeta,
      direction: "in",           // Person HAS_ACCESS_TO Gallery → incoming to Gallery
      relationship: "HAS_ACCESS_TO",
      cardinality: "many",
      required: false,
      dtoKey: "persons",
      // Edge properties for access control
      fields: [
        { name: "code", type: "string", required: true },
        { name: "expiresAt", type: "datetime", required: false },
      ],
    },
  },
});

export type GalleryDescriptorType = typeof GalleryDescriptor;
```

---

## Company Scope and Tenancy

`isCompanyScoped` (default `true`) tells `AbstractRepository.buildDefaultMatch()` to add the
`BELONGS_TO` company predicate to every read, and `defineEntity` to manage the `company`
relationship. An entity that sets it to `false` has no such predicate, so when it also carries a
`description` (which makes it visible to the assistant and the MCP tools) it MUST say how it is
scoped. `tenancy` is that declaration; `defineEntity` rejects an unscoped described entity without
it, and the graph catalog refuses to boot on one.

```typescript
// Reference data shared by every company
export const LawDescriptor = defineEntity<Law>()({
  ...lawMeta,
  isCompanyScoped: false,
  tenancy: "global",
  description: "A statute (legge) in the shared legal corpus.",
  fields: { /* … */ },
  relationships: {},
});

// Reaches its company through its parent: the predicate becomes
// EXISTS { MATCH (message)<-[:HAS_MESSAGE]-(:Conversation)-[:BELONGS_TO]->(company) }
export const MessageDescriptor = defineEntity<Message>()({
  ...messageMeta,
  isCompanyScoped: false,
  tenancy: { via: "conversation" },
  description: "One message of a conversation.",
  fields: { /* … */ },
  relationships: {
    conversation: { model: conversationMeta, direction: "in", relationship: "HAS_MESSAGE", cardinality: "one" },
  },
});
```

Rules:
- `tenancy` is only valid together with `isCompanyScoped: false`.
- `{ via }` names ONE relationship key of this descriptor. Its target must be company-scoped, or be the
  company itself (then the predicate matches the company node directly). Multi-hop chains are not
  supported: give the intermediate entity its own `tenancy` and point `via` at it.
- `"internal"` keeps the type out of the assistant catalog; its HTTP reads are unchanged, so scope them
  in the repository as before.
- `tenancy` governs READS through `buildDefaultMatch()`. Write paths of an unscoped entity still match the
  entity itself by id; keep an unscoped entity out of `chat.writable` unless its repository guards writes
  itself. The relationship TARGETS of a write are checked per target label (see "Relationship Writes"
  below, nestjs-neo4jsonapi 6.6.0+).

### Relationship Writes: the Company Check

Before 6.6.0 a client-supplied relationship id was linked after an existence check only, so a record could
be linked to another company's node and that node read back through the link. Since 6.6.0 the generic
writers of `AbstractRepository` (`create`, `put`, `patch`, `addToRelationship`) check every target id
against the rule of the target's label before writing:

| Target label | A target id passes when |
|---|---|
| company-scoped (`isCompanyScoped: true`, the default) | `(t)-[:BELONGS_TO]->(:Company {id: $companyId})`; a node with several `BELONGS_TO` edges (a user member of several companies) passes when ANY edge matches |
| `tenancy: "self"` | the target IS the caller's company (`t.id = $companyId`) |
| `tenancy: { via }` | the target's parent through that ONE hop belongs to the caller's company |
| `linkScope: "own-or-platform"` | the target is a platform row (no company edge) or one of the caller's own rows |
| `tenancy: "global"` / `"internal"`, unscoped without `tenancy`, or a label never passed to `defineEntity` (plain-model entities) | it exists |

Existence only, whatever the target label:
- a relationship flagged `crossCompany: true`;
- a relationship with a `contextKey` (server-filled from CLS, e.g. the author = caller);
- the caller's own user id, which is always linkable;
- a write with no company in context (system jobs, crons): the whole check is existence only.

A refused id gets the SAME 400 as a missing id, so the answer leaks nothing about other companies' ids.
`addToRelationship` no longer filters targets by the parent's company (a global target can be linked) and
answers 400 on a missing id.

Hand-written relationship Cypher bypasses the generic writers, so a custom repository that writes
relationships itself runs the same check first. `Neo4jService.validateRelatedNodes` does it in one read
query; the company defaults to the one in CLS. `validateExistingNodes` is unchanged (existence only).

```typescript
await this.neo4j.validateRelatedNodes({
  nodes: params.proceedingIds.map((id) => ({ id, label: proceedingMeta.labelName })),
});
```

**One owner per label: `isProjection`.** `defineEntity` fills a label → tenancy registry
(`entityTenancyRegistry`); `relatedNodeRuleForLabel(label)` and `relatedNodeRule(rel)` return the rule. A
descriptor that is ANOTHER VIEW of a label owned by a different descriptor (portal projection, count, OAuth
row, lookup) declares `isProjection: true` (nestjs-neo4jsonapi 6.6.1+); `defineEntity` then does not register
the label, so it never decides what a relationship write to that label is checked against. Put a one-line
comment naming the owner:

```typescript
isCompanyScoped: false,
tenancy: "internal",
// Another view of the label: the CRM Proceeding descriptor sets what a relationship write to it is checked against.
isProjection: true,
```

Registering a label again with IDENTICAL tenancy is allowed. Registering it with a different
`isCompanyScoped` / `tenancy` / `linkScope` / `via` throws at import time, i.e. at boot and when a spec
imports the descriptor:

```text
entityTenancyRegistry: label "Proceeding" is registered by "proceedings" and "portal-proceedings" with different tenancy. Mark the descriptor that is another view of the label with isProjection: true.
```

Fix it by marking the non-owner descriptor `isProjection: true`. Never fix it by changing the owner's tenancy
to match the projection. Before 6.6.1 the last descriptor registered for a label won, so a looser projection
loaded after the owner silently turned the label's check into existence only; vitest `fast` projects share
one module registry per worker, so in tests the clash depended on file order.

Guard it in the app with a label-tenancy spec (a360ai: `apps/api/src/common/tenancy/label-tenancy.spec.ts`):
import the app's root feature modules as `main.ts` does and assert `relatedNodeRuleForLabel(<label>)` for each
label that has a projection. A spec that calls `defineEntity` repeatedly with ONE fixture label and different
tenancy calls `entityTenancyRegistry.unregister(label)` between definitions (in `afterEach`, and inside loops).

## Field Types

| Type | Description | Neo4j Type |
|------|-------------|------------|
| `"string"` | Text | String |
| `"number"` | Numeric | Integer/Float |
| `"boolean"` | True/false | Boolean |
| `"date"` | Date only | Date |
| `"datetime"` | Date and time | DateTime |
| `"string[]"` | Array of strings | List<String> |
| `"number[]"` | Array of numbers | List<Integer> |

### Dates and DateTimes — non-negotiable

A field that represents a calendar date MUST be `type: "date"`. A field that
represents an instant in time MUST be `type: "datetime"`. **Never declare a
temporal field as `"string"`** — the framework reads the descriptor to emit
the correct Cypher cast (`date(left($v, 10))` / `datetime($v)`), and if the
type is wrong the value lands in Neo4j as a `String` and Cypher temporal
operators silently break.

Full lifecycle (descriptor → DTO → repository → frontend) and verification
checklist: **[../date-handling.md](../date-handling.md)**.

---

**Next**: See [02-dtos.md](./02-dtos.md) for Data Transfer Objects
