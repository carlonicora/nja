---
id: frontend-01-models
title: "Frontend: Models"
applies_to: frontend
layer: model
depends_on:
  - core-principles
  - frontend-02-interfaces
source_files:
  - "apps/web/src/features/*/data/*.ts"
  - "packages/nextjs-jsonapi/src/core/AbstractApiData.ts"
related_docs:
  - frontend-03-services
  - frontend-template
enforcement: critical
last_updated: "2026-03-01"
---

# Frontend: Models

---

## WHEN TO USE
Read this file when:
- Creating a new frontend model
- Adding rehydration for new fields/relationships
- Creating JSON:API payloads for create/update
- Adding dedicated relationship methods

---

## CRITICAL RULES

1. **ALWAYS implement `rehydrate()`** - Deserializes JSON:API response to typed object.
2. **ALWAYS implement `createJsonApi()`** - Serializes input to JSON:API request.
3. **Use `_readIncluded()` for simple relationships** - Single or array relationships without edge properties.
4. **Use `_readIncludedWithMeta()` ONLY for edge properties** - When relationship has metadata (position, code, etc.).
5. **Create dedicated methods for relationship operations** - Instead of using `overridesJsonApiCreation` in services.
6. **Date/datetime fields:** in `rehydrate()`, parse wire strings with `new Date(...)`. In `createJsonApi()`, emit dates with `formatLocalDate(d)` (`YYYY-MM-DD`) and datetimes with `d.toISOString()`. **Never pass a raw `Date` to a JSON:API attribute** — `JSON.stringify` UTC-shifts and can lose a day. See [../date-handling.md](../date-handling.md).

---

## DECISION MATRIX

### `_readIncluded()` vs `_readIncludedWithMeta()`

| Question | Method |
|----------|--------|
| Simple relationship without edge properties? | `_readIncluded()` |
| Relationship has edge properties (position, code, timestamp)? | `_readIncludedWithMeta()` |

### When to Create Dedicated Relationship Methods

| Question | Answer |
|----------|--------|
| Need to add related entity with edge properties? | **Create method like `createAddPhotoJsonApi()`** |
| Service would need `overridesJsonApiCreation`? | **Create dedicated model method instead** |
| Standard entity create/update? | **Use standard `createJsonApi()`** |

---

## COMMON MISTAKES

- Using `_readIncludedWithMeta()` when there are no edge properties
- Using `overridesJsonApiCreation` in service instead of dedicated model method
- Forgetting to call `super.rehydrate(data)` at start of rehydrate()
- Forgetting to return `this` from rehydrate()
- Passing a raw `Date` through `createJsonApi()` for a `"date"` field — `JSON.stringify` UTC-shifts. Wrap in `formatLocalDate(d)`. See [../date-handling.md](../date-handling.md).

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [02-interfaces.md](02-interfaces.md) | Define interface before model |
| [03-services.md](03-services.md) | Services call model methods |
| [template.md](template.md) | Copy-paste ready code |

---

## Model Pattern

```typescript
// Gallery.ts
import { AbstractApiData } from "@carlonicora/nextjs-jsonapi";
import { JsonApiHydratedDataInterface } from "@carlonicora/nextjs-jsonapi";
import { GalleryInput } from "./GalleryInput";
import { GalleryInterface, PersonRelationshipMeta } from "./GalleryInterface";
import { Modules } from "@/core/registry/Modules";
import { PersonInterface } from "../../person/data/PersonInterface";
import { PhotographInterface } from "../../photograph/data/PhotographInterface";
import { UserInterface } from "../../user/data/UserInterface";

export class Gallery extends AbstractApiData implements GalleryInterface {
  private _name?: string;
  private _description?: string;
  private _samplePhotographs?: string[];
  private _photoCount?: number;
  private _owner?: UserInterface;
  private _photographs?: PhotographInterface[];
  private _persons?: (PersonInterface & PersonRelationshipMeta)[];

  // Getters
  get name(): string { return this._name ?? ""; }
  get description(): string | undefined { return this._description; }
  get samplePhotographs(): string[] { return this._samplePhotographs ?? []; }
  get photoCount(): number { return this._photoCount ?? 0; }
  get owner(): UserInterface | undefined { return this._owner; }
  get photographs(): PhotographInterface[] { return this._photographs ?? []; }
  get persons(): (PersonInterface & PersonRelationshipMeta)[] { return this._persons ?? []; }

  /**
   * Deserialize JSON:API response into typed object
   */
  rehydrate(data: JsonApiHydratedDataInterface): this {
    super.rehydrate(data);  // ALWAYS call super first

    // Simple attributes
    this._name = data.jsonApi.attributes.name;
    this._description = data.jsonApi.attributes.description;
    this._samplePhotographs = data.jsonApi.attributes.samplePhotographs;
    this._photoCount = data.jsonApi.meta?.photoCount;

    // Single relationship - use _readIncluded
    this._owner = this._readIncluded(data, "owner", Modules.User) as UserInterface;

    // Array relationship - use _readIncluded
    this._photographs = this._readIncluded(
      data,
      "photographs",
      Modules.Photograph
    ) as PhotographInterface[];

    // Relationship WITH edge metadata - use _readIncludedWithMeta
    this._persons = this._readIncludedWithMeta<PersonInterface, PersonRelationshipMeta>(
      data,
      "persons",
      Modules.Person,
    ) as (PersonInterface & PersonRelationshipMeta)[];

    return this;  // ALWAYS return this
  }

  /**
   * Serialize TypeScript object to JSON:API for POST/PUT
   */
  createJsonApi(data: GalleryInput) {
    const response: any = {
      data: {
        type: Modules.Gallery.name,
        id: data.id,
        attributes: {},
        relationships: {},
      },
      included: [],
    };

    // Set attributes
    if (data.name !== undefined) response.data.attributes.name = data.name;
    if (data.description !== undefined) response.data.attributes.description = data.description;

    // Set single relationship
    if (data.ownerId) {
      response.data.relationships.owner = {
        data: {
          type: Modules.User.name,
          id: data.ownerId,
        },
      };
    }

    // Set array relationship
    if (data.photographIds && data.photographIds.length > 0) {
      response.data.relationships.photograph = {
        data: data.photographIds.map((id) => ({
          type: Modules.Photograph.name,
          id,
        })),
      };
    }

    return response;
  }

  /**
   * Dedicated method for adding photo with position (edge property)
   * Use this INSTEAD of overridesJsonApiCreation in service
   */
  createAddPhotoJsonApi(params: { photoId: string; position: number }) {
    return {
      data: {
        type: Modules.Photograph.name,
        id: params.photoId,
        meta: {
          position: params.position,
        },
      },
    };
  }

  /**
   * Dedicated method for adding person with access code (edge properties)
   */
  createAddPersonJsonApi(params: { personId: string; code: string; expiresAt?: string }) {
    return {
      data: {
        type: Modules.Person.name,
        id: params.personId,
        meta: {
          code: params.code,
          completed: false,
          expiresAt: params.expiresAt,
        },
      },
    };
  }
}
```

---

## Rehydration Patterns

### Simple Attributes

```typescript
rehydrate(data: JsonApiHydratedDataInterface): this {
  super.rehydrate(data);

  // String attribute
  this._name = data.jsonApi.attributes.name;

  // Optional string attribute
  this._description = data.jsonApi.attributes.description;

  // Number from meta
  this._photoCount = data.jsonApi.meta?.photoCount;

  // Array attribute
  this._tags = data.jsonApi.attributes.tags ?? [];

  return this;
}
```

### Single Relationship

```typescript
// No edge properties - use _readIncluded
this._owner = this._readIncluded(data, "owner", Modules.User) as UserInterface;
```

### Array Relationship

```typescript
// No edge properties - use _readIncluded
this._photographs = this._readIncluded(
  data,
  "photographs",
  Modules.Photograph
) as PhotographInterface[];
```

### Relationship with Edge Properties

```typescript
// HAS edge properties - use _readIncludedWithMeta
this._persons = this._readIncludedWithMeta<PersonInterface, PersonRelationshipMeta>(
  data,
  "persons",
  Modules.Person,
) as (PersonInterface & PersonRelationshipMeta)[];
```

---

## Error Handling

Models handle deserialization errors gracefully:
- Missing attributes return `undefined` or default values
- Missing relationships return `undefined` or empty arrays
- Edge properties are merged into entity when present

```typescript
get name(): string { return this._name ?? ""; }  // Default to empty string
get description(): string | undefined { return this._description; }  // Return undefined if missing
get photographs(): PhotographInterface[] { return this._photographs ?? []; }  // Default to empty array
```

---

**Next**: See [02-interfaces.md](./02-interfaces.md) for type contracts
