---
id: frontend-template
title: "Frontend: New Entity Template"
applies_to: frontend
layer: template
depends_on:
  - frontend-02-interfaces
  - frontend-01-models
  - frontend-03-services
source_files: []
related_docs: []
enforcement: recommended
last_updated: "2026-03-01"
---

# Frontend: New Entity Template (Copy-Paste Ready)

---

## WHEN TO USE
Use this template when creating a new frontend entity. Choose the appropriate complexity tier based on your requirements.

---

## COMPLEXITY TIERS

| Tier | Description | When to Use |
|------|-------------|-------------|
| **Simple** | Basic CRUD, attributes only | Entities with fields and single relationship |
| **Medium** | Array relationships, edge metadata | Entities with multiple relationships, some with edge properties |
| **Complex** | Custom relationship methods | Entities needing add/remove methods with edge properties |

---

## DECISION MATRIX

| Requirement | Tier |
|-------------|------|
| Only attributes and single relationship | **Simple** |
| Array relationships without edge properties | **Simple** |
| Relationships with edge properties (position, code, etc.) | **Medium** |
| Need `_readIncludedWithMeta()` | **Medium** |
| Custom methods for adding/removing relationships | **Complex** |
| Multiple relationship operations with edge properties | **Complex** |

---

## Directory Structure

All tiers follow the same structure:

```
src/features/[domain]/data/
├── Example.ts           # Model
├── ExampleInterface.ts  # Type interface
├── ExampleInput.ts      # Input type for create/update
└── ExampleService.ts    # API service
```

---

# Tier 1: Simple Entity

**Use when**: Basic CRUD with attributes and simple relationships (no edge properties).

## Step 1: Interface (Simple)

```typescript
// src/features/[domain]/data/ExampleInterface.ts
import { ApiDataInterface } from "@carlonicora/nextjs-jsonapi";
import { UserInterface } from "../../user/data/UserInterface";

export interface ExampleInterface extends ApiDataInterface {
  // Required attribute - always has value
  get name(): string;

  // Optional attribute - can be undefined
  get description(): string | undefined;

  // Single relationship - may not be included
  get owner(): UserInterface | undefined;
}
```

## Step 2: Input Type (Simple)

```typescript
// src/features/[domain]/data/ExampleInput.ts
export type ExampleInput = {
  id: string;                 // Always required for JSON:API
  name: string;               // Required attribute
  description?: string;       // Optional attribute
  ownerId: string;            // Required relationship
};
```

## Step 3: Model (Simple)

```typescript
// src/features/[domain]/data/Example.ts
import { AbstractApiData, JsonApiHydratedDataInterface } from "@carlonicora/nextjs-jsonapi";
import { ExampleInput } from "./ExampleInput";
import { ExampleInterface } from "./ExampleInterface";
import { Modules } from "@/core/registry/Modules";
import { UserInterface } from "../../user/data/UserInterface";

export class Example extends AbstractApiData implements ExampleInterface {
  private _name?: string;
  private _description?: string;
  private _owner?: UserInterface;

  get name(): string { return this._name ?? ""; }
  get description(): string | undefined { return this._description; }
  get owner(): UserInterface | undefined { return this._owner; }

  rehydrate(data: JsonApiHydratedDataInterface): this {
    super.rehydrate(data);  // ALWAYS call super first

    // Simple attributes
    this._name = data.jsonApi.attributes.name;
    this._description = data.jsonApi.attributes.description;

    // Single relationship - use _readIncluded
    this._owner = this._readIncluded(data, "owner", Modules.User) as UserInterface;

    return this;  // ALWAYS return this
  }

  createJsonApi(data: ExampleInput) {
    const response: any = {
      data: {
        type: Modules.Example.name,
        id: data.id,
        attributes: {},
        relationships: {},
      },
      included: [],
    };

    if (data.name !== undefined) response.data.attributes.name = data.name;
    if (data.description !== undefined) response.data.attributes.description = data.description;

    if (data.ownerId) {
      response.data.relationships.owner = {
        data: { type: Modules.User.name, id: data.ownerId },
      };
    }

    return response;
  }
}
```

## Step 4: Service (Simple)

```typescript
// src/features/[domain]/data/ExampleService.ts
import { AbstractService, EndpointCreator, HttpMethod } from "@carlonicora/nextjs-jsonapi";
import { ExampleInput } from "./ExampleInput";
import { ExampleInterface } from "./ExampleInterface";
import { Modules } from "@/core/registry/Modules";

export class ExampleService extends AbstractService {
  static async findOne(params: { id: string }): Promise<ExampleInterface> {
    return this.callApi<ExampleInterface>({
      type: Modules.Example,
      method: HttpMethod.GET,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.id,
      }).generate(),
    });
  }

  static async findMany(params: { search?: string; fetchAll?: boolean } = {}): Promise<ExampleInterface[]> {
    const endpoint = new EndpointCreator({ endpoint: Modules.Example });
    if (params.fetchAll) endpoint.addAdditionalParam("fetchAll", "true");
    if (params.search) endpoint.addAdditionalParam("search", params.search);

    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.GET,
      endpoint: endpoint.generate(),
    });
  }

  static async create(params: ExampleInput): Promise<ExampleInterface> {
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.POST,
      endpoint: new EndpointCreator({ endpoint: Modules.Example }).generate(),
      input: params,
    });
  }

  static async update(params: ExampleInput): Promise<ExampleInterface> {
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.PUT,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.id,
      }).generate(),
      input: params,
    });
  }

  static async delete(params: { id: string }): Promise<void> {
    await this.callApi({
      type: Modules.Example,
      method: HttpMethod.DELETE,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.id,
      }).generate(),
    });
  }
}
```

## Step 5: Register in Modules

```typescript
// src/core/registry/Modules.ts
// Add to the existing Modules registry
Example: {
  name: "examples",
  model: Example,
},
```

---

# Tier 2: Medium Entity

**Adds to Simple**: Array relationships, edge property interfaces, `_readIncludedWithMeta()`.

## Interface (Medium) - Add edge property interface

```typescript
// src/features/[domain]/data/ExampleInterface.ts
import { ApiDataInterface } from "@carlonicora/nextjs-jsonapi";
import { UserInterface } from "../../user/data/UserInterface";
import { ItemInterface } from "../../item/data/ItemInterface";
import { PersonInterface } from "../../person/data/PersonInterface";

// Edge metadata for person relationship
export interface PersonRelationshipMeta {
  code: string;
  completed: boolean;
  expiresAt?: string;
}

export interface ExampleInterface extends ApiDataInterface {
  get name(): string;
  get description(): string | undefined;
  get photoCount(): number;                    // Computed from backend meta
  get owner(): UserInterface | undefined;
  get items(): ItemInterface[];                 // Array relationship
  get persons(): (PersonInterface & PersonRelationshipMeta)[];  // With edge properties
}
```

## Input Type (Medium) - Add array relationships

```typescript
// src/features/[domain]/data/ExampleInput.ts
export type ExampleInput = {
  id: string;
  name: string;
  description?: string;
  ownerId: string;
  itemIds?: string[];       // Array relationship
  personIds?: string[];     // Array relationship (edge props handled separately)
};
```

## Model (Medium) - Add _readIncludedWithMeta

```typescript
// src/features/[domain]/data/Example.ts
import { AbstractApiData, JsonApiHydratedDataInterface } from "@carlonicora/nextjs-jsonapi";
import { ExampleInput } from "./ExampleInput";
import { ExampleInterface, PersonRelationshipMeta } from "./ExampleInterface";
import { Modules } from "@/core/registry/Modules";
import { UserInterface } from "../../user/data/UserInterface";
import { ItemInterface } from "../../item/data/ItemInterface";
import { PersonInterface } from "../../person/data/PersonInterface";

export class Example extends AbstractApiData implements ExampleInterface {
  private _name?: string;
  private _description?: string;
  private _photoCount?: number;
  private _owner?: UserInterface;
  private _items?: ItemInterface[];
  private _persons?: (PersonInterface & PersonRelationshipMeta)[];

  get name(): string { return this._name ?? ""; }
  get description(): string | undefined { return this._description; }
  get photoCount(): number { return this._photoCount ?? 0; }
  get owner(): UserInterface | undefined { return this._owner; }
  get items(): ItemInterface[] { return this._items ?? []; }
  get persons(): (PersonInterface & PersonRelationshipMeta)[] { return this._persons ?? []; }

  rehydrate(data: JsonApiHydratedDataInterface): this {
    super.rehydrate(data);

    // Simple attributes
    this._name = data.jsonApi.attributes.name;
    this._description = data.jsonApi.attributes.description;

    // Computed from meta
    this._photoCount = data.jsonApi.meta?.photoCount;

    // Single relationship - use _readIncluded
    this._owner = this._readIncluded(data, "owner", Modules.User) as UserInterface;

    // Array relationship without edge properties - use _readIncluded
    this._items = this._readIncluded(data, "items", Modules.Item) as ItemInterface[];

    // Array relationship WITH edge properties - use _readIncludedWithMeta
    this._persons = this._readIncludedWithMeta<PersonInterface, PersonRelationshipMeta>(
      data,
      "persons",
      Modules.Person,
    ) as (PersonInterface & PersonRelationshipMeta)[];

    return this;
  }

  createJsonApi(data: ExampleInput) {
    const response: any = {
      data: {
        type: Modules.Example.name,
        id: data.id,
        attributes: {},
        relationships: {},
      },
      included: [],
    };

    if (data.name !== undefined) response.data.attributes.name = data.name;
    if (data.description !== undefined) response.data.attributes.description = data.description;

    if (data.ownerId) {
      response.data.relationships.owner = {
        data: { type: Modules.User.name, id: data.ownerId },
      };
    }

    if (data.itemIds && data.itemIds.length > 0) {
      response.data.relationships.items = {
        data: data.itemIds.map((id) => ({
          type: Modules.Item.name,
          id,
        })),
      };
    }

    return response;
  }
}
```

---

# Tier 3: Complex Entity

**Adds to Medium**: Dedicated relationship methods for edge properties.

## Model (Complex) - Add dedicated relationship methods

```typescript
// src/features/[domain]/data/Example.ts
// ... (same as Medium tier, plus the following methods)

export class Example extends AbstractApiData implements ExampleInterface {
  // ... all properties and getters from Medium tier ...

  rehydrate(data: JsonApiHydratedDataInterface): this {
    // ... same as Medium tier ...
  }

  createJsonApi(data: ExampleInput) {
    // ... same as Medium tier ...
  }

  /**
   * Dedicated method for adding item with position (edge property)
   * Use this INSTEAD of overridesJsonApiCreation in service
   */
  createAddItemJsonApi(params: { itemId: string; position: number }) {
    return {
      data: {
        type: Modules.Item.name,
        id: params.itemId,
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

  /**
   * Dedicated method for updating person's edge properties
   */
  createUpdatePersonJsonApi(params: { personId: string; completed: boolean }) {
    return {
      data: {
        type: Modules.Person.name,
        id: params.personId,
        meta: {
          completed: params.completed,
        },
      },
    };
  }
}
```

## Service (Complex) - Add relationship methods

```typescript
// src/features/[domain]/data/ExampleService.ts
import { AbstractService, EndpointCreator, HttpMethod } from "@carlonicora/nextjs-jsonapi";
import { Example } from "./Example";
import { ExampleInput } from "./ExampleInput";
import { ExampleInterface } from "./ExampleInterface";
import { Modules } from "@/core/registry/Modules";

export class ExampleService extends AbstractService {
  // ... all methods from Simple tier ...

  /**
   * Nested endpoint - get by relationship
   */
  static async findManyByOwner(params: { ownerId: string }): Promise<ExampleInterface[]> {
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.GET,
      endpoint: new EndpointCreator({
        endpoint: Modules.User,
        id: params.ownerId,
        childEndpoint: Modules.Example,
      }).generate(),
    });
  }

  /**
   * Add item with position (edge property)
   * Uses dedicated model method - NEVER manual JSON:API construction
   */
  static async addItem(params: {
    exampleId: string;
    itemId: string;
    position: number;
  }): Promise<ExampleInterface> {
    const example = new Example();
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.POST,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.exampleId,
        childEndpoint: Modules.Item,
        childId: params.itemId,
      }).generate(),
      input: example.createAddItemJsonApi({
        itemId: params.itemId,
        position: params.position,
      }),
      overridesJsonApiCreation: true,  // OK - model method provides structure
    });
  }

  /**
   * Add person with access code (edge properties)
   */
  static async addPerson(params: {
    exampleId: string;
    personId: string;
    code: string;
    expiresAt?: string;
  }): Promise<ExampleInterface> {
    const example = new Example();
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.POST,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.exampleId,
        childEndpoint: Modules.Person,
        childId: params.personId,
      }).generate(),
      input: example.createAddPersonJsonApi({
        personId: params.personId,
        code: params.code,
        expiresAt: params.expiresAt,
      }),
      overridesJsonApiCreation: true,  // OK - model method provides structure
    });
  }

  /**
   * Update person's edge properties (e.g., mark completed)
   */
  static async updatePerson(params: {
    exampleId: string;
    personId: string;
    completed: boolean;
  }): Promise<ExampleInterface> {
    const example = new Example();
    return this.callApi({
      type: Modules.Example,
      method: HttpMethod.PUT,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.exampleId,
        childEndpoint: Modules.Person,
        childId: params.personId,
      }).generate(),
      input: example.createUpdatePersonJsonApi({
        personId: params.personId,
        completed: params.completed,
      }),
      overridesJsonApiCreation: true,  // OK - model method provides structure
    });
  }

  /**
   * Remove item from example
   */
  static async removeItem(params: {
    exampleId: string;
    itemId: string;
  }): Promise<void> {
    await this.callApi({
      type: Modules.Example,
      method: HttpMethod.DELETE,
      endpoint: new EndpointCreator({
        endpoint: Modules.Example,
        id: params.exampleId,
        childEndpoint: Modules.Item,
        childId: params.itemId,
      }).generate(),
    });
  }
}
```

---

## Checklist

Before finishing, verify:
- [ ] Interface extends `ApiDataInterface`
- [ ] Interface uses getter syntax for all properties
- [ ] Edge property interfaces defined separately (if needed)
- [ ] Model implements interface
- [ ] Model has `rehydrate()` with `super.rehydrate(data)` at start and `return this` at end
- [ ] Model has `createJsonApi()` for standard CRUD
- [ ] Model has dedicated relationship methods for edge properties (Complex tier)
- [ ] Service uses `callApi()` (never `fetch()`)
- [ ] Service uses `EndpointCreator` for URLs
- [ ] Service uses dedicated model methods (not manual JSON:API construction)
- [ ] Entity registered in Modules
