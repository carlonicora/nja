---
id: anti-patterns
title: "Anti-Patterns Detection Guide"
applies_to: both
layer: meta
depends_on:
  - core-principles
source_files: []
related_docs:
  - backend-03-repositories
  - frontend-03-services
enforcement: critical
last_updated: "2026-08-26"
---

# Anti-Patterns (DON'T DO THIS)

---

## WHEN TO USE
Read this file when:
- Reviewing code for correctness
- Debugging unexpected behavior
- Before committing changes

---

## CRITICAL RULES

1. **All anti-patterns are equally important** - Any violation breaks the architecture.
2. **If you see these patterns in code, fix them immediately** - They indicate bugs or security issues.
3. **NEVER use `overridesJsonApiCreation`** - Create dedicated model methods instead.

---

## DETECTION GUIDE

**How to spot anti-patterns in code:**

| Code Pattern | Anti-Pattern |
|--------------|--------------|
| `result.records[0]` | Returning raw Neo4j records |
| `WHERE company.id = $companyId` (manual) | Manual company filtering |
| `SKIP ${offset} LIMIT ${limit}` | Manual pagination |
| `{ data: { type: ..., attributes: ... } }` (manual) | Manual JSON:API construction |
| `fetch('/api/...')` | Using fetch() directly |
| `overridesJsonApiCreation: true` | Bypassing model validation |
| `asChild`, `<DialogContent>` as single component, `<Sub>` | Using Radix API — this project uses Base UI |
| `blocksToText(...)`, `paragraphBlocks(...)`, any blocks↔text converter | Duplicates the BlockNote editor — display with `BlockNoteEditorContainer`, test emptiness with `onEmptyChange` (see [frontend/06-blocknote.md](frontend/06-blocknote.md)) |
| A plain `<Input>` feeding a rich-text (`description`/`content`/`notes`) field | The blocks array is the only representation — collect it with an editor |
| `<PopoverTrigger><Button>` or trigger wrapping Button | Nested `<button>` — hydration error |
| `someDate: { type: "string" }` for a calendar field | Storing a date as a String — Cypher temporal ops break (see [date-handling.md](date-handling.md)) |
| `SET n.due_date = $due_date` in custom Cypher | Bypasses framework cast — stores a String (use `date(left($v, 10))`) |
| `SET n.processed_at = $processed_at` in custom Cypher | Same, datetime variant (use `datetime($v)`) |
| `response.data.attributes.date = data.date` with `data.date: Date` | `JSON.stringify` UTC-shifts and can lose a day (use `formatLocalDate`) |
| `get date(): string` on a frontend interface | Type lie — wire is a string but in-memory must be `Date` |
| `@IsString()` for a date attribute on a DTO | Accepts garbage like `"yesterday"` (use `@IsDateString()`) |
| `jest.fn()`, `jest.mock()`, `import ... from "@jest/globals"` | Jest API in a Vitest project — use `vi.*` |
| `jest.config.js`, `jest-e2e.json`, a `jest` / `ts-jest` / `@types/jest` dependency | Dead Jest configuration — delete it |
| A `vi.mock` factory referencing a module-scope `const` | Vitest hoists the factory above it — "Cannot access before initialization" (use `vi.hoisted()`) |
| `vi.importActual()` inside a non-`async` factory | `importActual` is async, unlike `jest.requireActual` |
| `unplugin-swc` in a `vitest.config.ts` with no `oxc: false` | Oxc owns the transform; `decoratorMetadata` is not guaranteed, breaking reflection-resolved DI |
| A content check on a valid LLM response that triggers `llm.call` again | Quality retry — banned; fix the schema/prompt, demote the check to a logged detector (see backend/06-llm-calls.md § "Retries — failures yes, quality never") |

---

## COMMON MISTAKES

- Using inherited methods when custom logic is needed
- Forgetting to register model in module's `onModuleInit()`
- Missing `{CURSOR}` placeholder in paginated queries
- Returning `undefined` instead of throwing `NotFoundException`

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [00-core-principles.md](00-core-principles.md) | Understanding why these are wrong |
| [backend/03-repositories.md](backend/03-repositories.md) | Correct repository patterns |
| [frontend/03-services.md](frontend/03-services.md) | Correct service patterns |

---

## Backend Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|---------------|------------------|
| Returning raw Neo4j records | No type safety, breaks serialization | Use `readOne`/`readMany` with serialiser |
| Manual company filtering | Security risk, inconsistent | Use `buildDefaultMatch()` |
| Manual pagination | Inconsistent, error-prone | Use `{CURSOR}` placeholder |
| Manual JSON:API construction | Breaks spec compliance | Use `JsonApiService.buildSingle/buildList` |
| Not extending AbstractRepository | Loses company filtering, typed mapping | Always extend `AbstractRepository` |
| Not extending AbstractService | Loses DTO handling, JSON:API building | Always extend `AbstractService` |
| `type: "string"` for a calendar field in the descriptor | Cypher temporal operators (`<`, `duration.between`) break on String | `type: "date"` (or `"datetime"`) — see [date-handling.md](date-handling.md) |
| Custom Cypher `SET n.foo = $foo` for a date/datetime field | Bypasses framework auto-cast, stores a String | Cast in the query: `SET n.foo = date(left($foo, 10))` or `datetime($foo)` |
| DTO uses `@IsString()` for a date/datetime attribute | Accepts non-date input, no validation | `@IsDateString()` |

### Backend Examples

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
  return this.neo4j.readOne(query);
}
```

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
  return this.neo4j.readMany(query);
}
```

---

## Frontend Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|---------------|------------------|
| Using `fetch()` directly | No type safety, no rehydration | Use `callApi()` |
| Using `overridesJsonApiCreation` | Bypasses model validation | Create dedicated model method |
| Manual JSON:API construction | Error-prone, inconsistent | Use `Model.createJsonApi()` |
| Not implementing `rehydrate()` | Breaks deserialization | Always implement `rehydrate()` |
| Not implementing `createJsonApi()` | Breaks serialization | Always implement `createJsonApi()` |
| Accessing `data.jsonApi.data.*` directly | Bypasses type system | Use typed getters after rehydrate |
| Using Radix patterns (`asChild`, Radix naming) | Base UI uses different API | See [frontend/04-components.md](frontend/04-components.md) |
| Wrapping `<Button>` inside trigger components | Nested `<button>` — invalid HTML | Use `render` prop or styled `<div>` inside trigger |
| Converting a BlockNote value to/from a string in app code | The editor already does it; the string form exists only on the wire | `BlockNoteEditorContainer` to display, `onEmptyChange` for emptiness — see [frontend/06-blocknote.md](frontend/06-blocknote.md) |
| Writing a new component that already exists in the package or a named reference repo | Visual/structural drift across the fleet the user must later reconcile | Grep first; copy a named reference verbatim and propose any deviation before writing it |
| Passing raw `Date` to `createJsonApi()` for a `"date"` field | `JSON.stringify` calls `.toISOString()` — UTC shift loses a day west of UTC | Wrap in `formatLocalDate(d)` — see [date-handling.md](date-handling.md) |
| Returning the wire string from a `Date` getter (no `new Date(...)` in rehydrate) | Type lie — getter signature is `Date` but value is `string` | `new Date(data.jsonApi.attributes.foo)` in `rehydrate()` |
| Typing a date getter as `string` in the interface | Loses temporal semantics; consumers can't compare or format | `get foo(): Date \| undefined` |

### Frontend Examples

```typescript
// ❌ WRONG - Using fetch directly
static async findOne(id: string) {
  const response = await fetch(`/api/galleries/${id}`);
  const json = await response.json();
  return json.data;  // Raw JSON:API, not typed!
}

// ✅ CORRECT - Using callApi
static async findOne(params: { id: string }): Promise<GalleryInterface> {
  return this.callApi<GalleryInterface>({
    type: Modules.Gallery,
    method: HttpMethod.GET,
    endpoint: new EndpointCreator({
      endpoint: Modules.Gallery,
      id: params.id,
    }).generate(),
  });
}
```

```typescript
// ❌ WRONG - Using overridesJsonApiCreation for edge properties
static async addPhoto(params: { galleryId: string; photoId: string; position: number }) {
  return this.callApi({
    endpoint: ...,
    input: {
      data: { meta: { position: params.position } },
    },
    overridesJsonApiCreation: true,  // WRONG - bypasses model
  });
}

// ✅ CORRECT - Create dedicated model method
// In Gallery.ts model:
createAddPhotoJsonApi(params: { photoId: string; position: number }) {
  return {
    data: {
      type: Modules.Photograph.name,
      id: params.photoId,
      meta: { position: params.position },
    },
  };
}

// In GalleryService.ts:
static async addPhoto(params: { galleryId: string; photoId: string; position: number }) {
  const model = new Gallery();
  return this.callApi({
    type: Modules.Gallery,
    method: HttpMethod.POST,
    endpoint: new EndpointCreator({
      endpoint: Modules.Gallery,
      id: params.galleryId,
      childEndpoint: Modules.Photograph,
      childId: params.photoId,
    }).generate(),
    input: model.createAddPhotoJsonApi({ photoId: params.photoId, position: params.position }),
    overridesJsonApiCreation: true,  // OK when using dedicated model method
  });
}
```

---

## Summary

**Follow these patterns exactly. Deviating creates broken, inconsistent code.**

The architecture provides:
1. **Type Safety**: TypeScript types from descriptor → DTO → response
2. **Security**: Automatic company filtering via ClsService
3. **Consistency**: JSON:API compliance without manual work
4. **Simplicity**: Inherit from abstract classes, get CRUD for free
