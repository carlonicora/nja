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
last_updated: "2026-03-01"
---

# Backend: Entity Basics

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

---

## ENFORCEMENT CHECKPOINT

> **STOP — Before committing entity code, verify:**
> 1. Is the Descriptor exported alongside the type? If no, **STOP**.
> 2. Are computed values in `computed`, not `fields`? If a derived value is in `fields`, **STOP**.
> 3. Are relationship directions correct from THIS entity's perspective? If unsure, **STOP** and check the Decision Matrix below.
> 4. Is the model registered in the module's `onModuleInit()`? If no, **STOP**.

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

---

## COMMON MISTAKES

- Putting computed values in `fields` instead of `computed`
- Wrong relationship direction (remember: from THIS entity's perspective)
- Missing `dtoKey` on relationships (defaults to relationship name)
- Forgetting to export the descriptor type

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
