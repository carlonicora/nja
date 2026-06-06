---
id: date-handling
title: "Date and DateTime Handling (cross-cutting)"
applies_to: both
layer: meta
depends_on:
  - core-principles
source_files:
  - "apps/api/src/features/*/entities/*.ts"
  - "apps/api/src/features/*/dtos/*.ts"
  - "apps/api/src/features/*/repositories/*.ts"
  - "apps/web/src/features/*/data/*.ts"
  - "apps/web/src/features/*/data/*Interface.ts"
  - "packages/nestjs-neo4jsonapi/src/core/neo4j/abstracts/abstract.repository.ts"
  - "apps/web/src/utils/dateFormatters.ts"
related_docs:
  - backend-01-entity-basics
  - backend-02-dtos
  - backend-03-repositories
  - frontend-01-models
  - frontend-02-interfaces
  - anti-patterns
enforcement: critical
last_updated: "2026-05-17"
---

# Date and DateTime Handling

> A single rule, end-to-end: **dates and datetimes are stored as native Neo4j
> temporal types — never as strings**. The framework guarantees this only if
> every layer respects the contract below. Read this before touching any field
> that represents a calendar date or a point in time.

---

## WHEN TO USE
Read this file when:
- Adding a new field that represents a date or a date+time on any entity
- Reviewing or modifying any field whose name ends in `_at`, `_on`, `_date`, `_until`, `_from`, or similar
- Writing a custom Cypher query (in a repository) that sets a date/datetime property
- Implementing `rehydrate()` or `createJsonApi()` on a frontend model
- Debugging a value that arrives in the database as a string instead of a temporal type, or a value that shifts by one day across timezones

---

## THE NON-NEGOTIABLE RULES

1. **A calendar date (no time component) MUST use `type: "date"`** in the entity descriptor — never `"string"`, never `"datetime"`.
   *Examples: invoice date, due date, hire date, birth date, contract start.*

2. **A point in time (timestamped event) MUST use `type: "datetime"`** in the entity descriptor — never `"string"`, never `"date"`.
   *Examples: `createdAt`, `updatedAt`, `signedOffAt`, `confirmedAt`, `processedAt`.*

3. **Custom Cypher writes MUST cast scalars with `date(left($field, 10))` or `datetime($field)`** — never `SET n.foo = $foo` for a date/datetime field. The framework only auto-casts properties declared in the descriptor and routed through `create` / `put` / `patch`; ad-hoc `executeInTransaction` and custom service helpers bypass that path.

4. **Frontend `createJsonApi()` MUST emit dates as `YYYY-MM-DD` strings via `formatLocalDate(d)`** for any `type: "date"` field. Passing a raw JS `Date` causes `JSON.stringify` to call `.toISOString()`, which UTC-shifts and can move the value by a day.

5. **Frontend `createJsonApi()` MUST emit datetimes as ISO 8601 strings** (use `d.toISOString()` — UTC shift is correct for an instant in time).

6. **DTOs MUST use `@IsDateString()`** on date/datetime attributes. They are always strings on the wire; the type cast to a temporal happens in the Cypher write.

7. **Frontend interfaces MUST type date/datetime getters as `Date`** (or `Date | undefined`), and `rehydrate()` MUST parse with `new Date(...)`. The wire format is a string; in TypeScript memory the value is a `Date`.

If any of these rules is broken, the value lands in Neo4j as a plain `String`. Queries that filter with `<`, `>=`, or `duration.between(...)` will silently return wrong results or throw at runtime — Cypher's temporal operators do not coerce strings.

---

## HOW IT WORKS (the full lifecycle)

```
┌────────────┐   "2026-05-17"   ┌──────────────────┐    Neo4j Date     ┌─────────┐
│  Frontend  │ ───────────────► │  REST endpoint   │ ────────────────► │  Neo4j  │
│  (Date)    │  formatLocalDate │  (DTO validates  │  date(left(...,   │  (Date) │
│            │                  │  IsDateString)   │   10)) cast in    │         │
└────────────┘                  └──────────────────┘  AbstractRepo     └─────────┘
       ▲                                                                    │
       │                              "2026-05-17"                          │
       │  new Date(...)  ◄─── convertNeo4jDate ◄──────────────────────────  │
       └────────────────────────────────────────────────────────────────────┘
```

### 1. Entity descriptor — the source of truth

```typescript
fields: {
  // Calendar date: stored as Neo4j Date (no time, no zone)
  date:      { type: "date",     required: true },
  due_date:  { type: "date",     required: true },
  paid_on:   { type: "date" },

  // Instant in time: stored as Neo4j DateTime (UTC + offset)
  signed_off_at: { type: "datetime" },
  processed_at:  { type: "datetime" },
}
```

The descriptor is read by:
- `AbstractRepository.create` / `put` / `patch` — to emit the correct Cypher cast.
- `convertNeo4jDate` (in the framework) — to return `YYYY-MM-DD` on the read path.
- The OpenAPI generator — to emit the correct schema type.

If `type` is wrong, **every other layer goes wrong silently**.

### 2. DTOs — validate the wire format

```typescript
@IsDateString() date: string;       // YYYY-MM-DD or ISO 8601
@IsDateString() signed_off_at: string;
```

`@IsDateString()` accepts both `YYYY-MM-DD` and full ISO 8601. The Cypher
cast strips to the appropriate precision (`left($value, 10)` for dates).

### 3. Repository — framework path is automatic, custom paths are not

The standard `create` / `put` / `patch` paths in `AbstractRepository` already
emit the correct cast (see `abstract.repository.ts:687-692`, `:801-808`,
`:925-932`). You do not have to think about it when you go through the
framework.

**Custom repository helpers (your own `executeInTransaction` blocks) DO
bypass the auto-cast.** Anywhere you write a `SET n.someDate = $someDate`,
you must cast manually:

```typescript
// ❌ WRONG — stores "2026-05-17" as a String
await this.neo4j.executeInTransaction([{
  query: `MATCH (i:Invoice {id: $id}) SET i.paid_on = $paid_on`,
  params: { id, paid_on: "2026-05-17" },
}]);

// ✅ CORRECT — stores a Neo4j Date
await this.neo4j.executeInTransaction([{
  query: `MATCH (i:Invoice {id: $id}) SET i.paid_on = date(left($paid_on, 10))`,
  params: { id, paid_on: "2026-05-17" },
}]);

// ✅ CORRECT — datetime
await this.neo4j.executeInTransaction([{
  query: `MATCH (i:Invoice {id: $id}) SET i.processed_at = datetime($processed_at)`,
  params: { id, processed_at: "2026-05-17T14:23:00Z" },
}]);

// ✅ For "now", use the Cypher function directly — no parameter
SET i.updatedAt = datetime()
```

### 4. Service — string in, string out, no special handling

Service code (and any auto-trigger like the WO-completion auto-invoice) passes
ISO strings into the standard `create` / `put` / `patch` path. The framework
casts them at the Cypher boundary. Do not pre-format, do not stringify a `Date`
yourself in the service layer.

```typescript
const todayIso = new Date().toISOString().slice(0, 10);   // "YYYY-MM-DD"
await this.create({ id, date: todayIso, due_date: todayIso, ... });
```

### 5. Frontend interface — type as `Date`

```typescript
export interface InvoiceInterface extends ApiDataInterface {
  get date(): Date;
  get due_date(): Date;
  get paid_on(): Date | undefined;
  get processed_at(): Date | undefined;   // datetime fields too
}

export type InvoiceInput = {
  date: Date;
  due_date: Date;
  paid_on?: Date;
  processed_at?: Date;
};
```

### 6. Frontend model `rehydrate()` — wire string → `Date`

```typescript
this._date = data.jsonApi.attributes.date
  ? new Date(data.jsonApi.attributes.date)
  : undefined;
```

`new Date("YYYY-MM-DD")` is parsed as UTC midnight by JavaScript. For dates
that should be calendar-only this is fine because the value is displayed in
the user's locale and the storage is timezone-free.

### 7. Frontend model `createJsonApi()` — `Date` → wire string

Date fields (`type: "date"`):

```typescript
import { formatLocalDate } from "@carlonicora/nextjs-jsonapi/core";

createJsonApi(data: InvoiceInput) {
  // ...
  if (data.date !== undefined) response.data.attributes.date = formatLocalDate(data.date);
  if (data.due_date !== undefined) response.data.attributes.due_date = formatLocalDate(data.due_date);
  if (data.paid_on !== undefined) response.data.attributes.paid_on = formatLocalDate(data.paid_on);
}
```

Datetime fields (`type: "datetime"`):

```typescript
if (data.processed_at !== undefined) response.data.attributes.processed_at = data.processed_at.toISOString();
```

**Why this matters:** `JSON.stringify(new Date("2026-05-17"))` produces
`"2026-05-17T00:00:00.000Z"`. In any timezone west of UTC this is interpreted
locally as May 16. `IsDateString()` accepts it, the Cypher cast strips it to
`"2026-05-16"`, and the date is now wrong by one day — silently.

`formatLocalDate` lives in `@carlonicora/nextjs-jsonapi/core` (source:
`packages/nextjs-jsonapi/src/utils/date-formatter.ts`). **Always import it
from the package** — never copy the implementation into a model as a private
method, and never re-implement it inline.

---

## DECISION MATRIX — date vs datetime vs string

| The field represents… | Use |
|---|---|
| A calendar day with no time component (invoice date, hire date, birthday, due date) | `type: "date"` |
| A precise instant a thing happened (createdAt, signedOffAt, processedAt) | `type: "datetime"` |
| A short code, label, year (`"2026"`, `"Q3"`, `"FY26"`) | `type: "string"` |
| An ISO-8601-shaped string the user freely edits | **Reconsider** — almost always actually a `"date"` or `"datetime"` |

A useful litmus test: "if I run `duration.between(a, b)` in Cypher on this
field, do I expect it to work?" If yes, it MUST be `"date"` or `"datetime"`.

---

## ANTI-PATTERNS (DO NOT DO)

| Code pattern | Why it's wrong | Fix |
|---|---|---|
| `someDate: { type: "string" }` for a calendar field | Cypher temporal ops won't work; date math returns wrong results | `type: "date"` |
| `SET n.due_date = $due_date` in custom Cypher | Bypasses framework cast; stores a String | `SET n.due_date = date(left($due_date, 10))` |
| `SET n.processed_at = $processed_at` in custom Cypher | Same as above for datetime | `SET n.processed_at = datetime($processed_at)` |
| `response.data.attributes.date = data.date` where `data.date: Date` | `JSON.stringify` ISO-shifts to UTC, can lose a day | `formatLocalDate(data.date)` |
| `get date(): string` on a frontend interface | Loses `Date` semantics; consumers can't do math, comparisons, formatting | `get date(): Date` |
| Skipping `new Date(...)` in `rehydrate()` and returning the wire string | Type lie — the getter claims `Date` but returns `string` | `new Date(data.jsonApi.attributes.date)` |
| DTO uses `@IsString()` instead of `@IsDateString()` for a date field | Accepts garbage like `"yesterday"` | `@IsDateString()` |
| Building a `new Date(year, month, day)` then `.toISOString().slice(0, 10)` | Re-introduces the UTC shift you were trying to avoid | `formatLocalDate(date)` (uses local getters) |

---

## VERIFYING A FIELD IS STORED CORRECTLY

Quick query to check what's actually in Neo4j:

```cypher
MATCH (n:Invoice) RETURN n.date, apoc.meta.type(n.date) LIMIT 1
```

The second column should be `"Date"` (or `"LocalDate"`) — never `"String"`.
If it is `"String"`, one of the rules above has been broken. Find the write
path and fix it; do not paper over the read side.

---

## CHECKPOINT — before merging a change that touches a date field

> 1. Is every date-like field declared with `type: "date"` or `type: "datetime"` in the entity descriptor? If no, **STOP**.
> 2. Does every custom Cypher write to a date/datetime property use `date(left($v, 10))` or `datetime($v)`? If no, **STOP**.
> 3. Does the DTO use `@IsDateString()`? If no, **STOP**.
> 4. Does the frontend interface type the field as `Date`? If no, **STOP**.
> 5. Does `rehydrate()` parse the wire string with `new Date(...)`? If no, **STOP**.
> 6. Does `createJsonApi()` use `formatLocalDate()` (dates) or `.toISOString()` (datetimes)? If no, **STOP**.

---

**See also:** `apps/api/CLAUDE.md` (backend "Common Mistakes" → "Storing dates as strings in Neo4j") and `apps/web/CLAUDE.md` (frontend "Common Mistakes" → "Raw JS `Date` in JSON:API date-only payloads") — both rules are surfaced into the CLAUDE.md files because they are bugs that recur in PRs.
