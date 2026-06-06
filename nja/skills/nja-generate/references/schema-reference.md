# Structure JSON schema reference

The generators read a JSON **array** of module definitions from `structure/<domain>.json`.
Both the backend (`generate-module`) and frontend (`generate-web-module`) read the
same file; fields not relevant to one side are ignored by that side.

```json
[
  { /* module 1 */ },
  { /* module 2 */ }
]
```

## Module-level fields

| Field | Required | Notes |
|---|---|---|
| `moduleId` | yes | UUID v4. **Must equal** the value you add to `ModuleId` in `packages/shared/src/const/module.id.ts`. Mint a fresh one. |
| `moduleName` | yes | PascalCase singular, e.g. `"PurchaseOrder"`. Drives class names, file names, `Modules.X`. |
| `endpointName` | yes | kebab/plural, e.g. `"purchase-orders"`. The JSON:API type + REST path. |
| `targetDir` | yes | `"features/<domain>"`, e.g. `"features/procurement"`. Where files are written. |
| `languages` | yes | `["en"]` minimum. Add `"it"` to also seed Italian i18n (the repo uses both). |
| `extendsContent` | no | `true` if the entity extends the Content base (gets `name`/`tldr`/`abstract`/`content` + BlockNote editor). Default `false`. |
| `isCompanyScoped` | no (backend) | Default `true` (auto company filtering). Set `false` only for global/foundation-like entities. |
| `description` | no (backend) | One-line entity description for the chatbot/graph catalog. Recommended. |
| `chat` | no (backend) | `{ "summary": "<TS expr>", "textSearchFields": ["name"] }` — `summary` is the body of `(data) => …`, e.g. `"data.name ?? data.id"`. |
| `requiresS3` | no (backend) | `true` if the entity stores images/files (adds `S3Module`). Trigger: an `image`/`avatar`/`logo` field. |
| `exportService` | no (backend) | Default `true` (module exports its service so others can inject it). |
| `featureId` | no (frontend) | Maps to `FeatureIds.<value>` in the module factory (sidebar/feature gating). e.g. `"Procurement"`. |
| `displayProp` | no (frontend) | Field used as the entity's display label. Default `"name"` if a `name` field exists, else `"id"`. |
| `containerTabs` | no (frontend) | `{ "activity": true, "relations": [{ "module": "Quote", "listProp": "opportunity", "directory": "sales" }] }`. Adds Details + related-list + Activity tabs to the detail page. |
| `inclusions` | no (frontend) | `{ "related": [{ "endpoint": "accounts", "fields": ["name","image"] }] }` — cross-module list inclusions. |

## Field definitions (`fields[]`)

| Field | Required | Notes |
|---|---|---|
| `name` | yes | snake_case attribute, e.g. `"is_active"`, `"sale_price"`. |
| `type` | yes | One of: `string`, `number`, `boolean`, `date`, `datetime`, `json` (and array variants `string[]`, `number[]`, …). |
| `nullable` | yes | `true` = optional. `false` = required. |
| `description` | no | For the chatbot/graph catalog. Recommended on non-obvious fields. |
| `kind` | no (backend only) | `{ "type": "money" }` for currency fields stored as integer cents. This is a **backend descriptor hint** (chatbot/semantic) — the frontend generator ignores it and does **not** produce money-formatted inputs/display. Money UI (`formatCurrency`/`parseCurrencyInput`) is a manual post-gen step. |
| `computed` | no | Raw TS expression (the body of `(p) => …`) for a value derived in Cypher, e.g. `"p.record?.get('effective_value') ?? undefined"`. Use with `readOnly: true`. |
| `readOnly` | no | `true` = present in the model interface + read path, omitted from create/update payloads. Use for derived/computed fields. |

**Type → meaning:** `date` = calendar date (no time, stored native), `datetime` = timestamped instant, `json` = arbitrary object (BlockNote content is usually a `json`/string field plus `extendsContent`). Never use `string` for a real date.

## Relationship definitions (`relationships[]`)

| Field | Required | Notes |
|---|---|---|
| `name` | yes | The **target** entity, PascalCase, e.g. `"Account"`. |
| `directory` | yes | Where the target lives: `"@foundation"` for framework entities (`User`, `Company`, …) or `"features/<domain>"` for feature entities, e.g. `"features/crm"`. |
| `single` | yes | `true` = to-one (belongs-to). `false` = to-many. |
| `relationshipName` | yes | Neo4j edge verb, UPPER_SNAKE_CASE, e.g. `"FOR"`, `"MANAGED_BY"`, `"HAS_ESTIMATE_ITEM"`. Describe the edge. |
| `toNode` | yes | Edge direction. `true` = outgoing (this entity → target), the common case. `false` = incoming. |
| `nullable` | yes | `true` = optional relationship (uses `OPTIONAL MATCH`). |
| `alias` | no | PascalCase. **Required when two or more relationships target the same entity** (disambiguation), e.g. `CreatedBy` and `AssignedTo` both → `User`. Also use to force a specific property/wire name. |
| `immutable` | no | `true` = set only on create, skipped on PUT (e.g. `CreatedBy`). |
| `fields` | no | Edge properties (`[{ "name": "quantity", "type": "number", "nullable": false }]`). Edge fields use the same shape as `fields[]` and **use `nullable`, not `required`** (the generator reads `required: !nullable`; a stray `required` key is ignored). On a to-one rel they become relationship meta; on a to-many rel they become a per-item `<rel>Meta` array. |
| `dtoKey` | no (frontend) | Explicit JSON:API relationship key (the wire name used on both backend DTOs and the frontend model). Defaults to a derived form (lowercased / kebab). Set it to match the backend descriptor's `dtoKey`. |
| `description` | no | For the chatbot/graph catalog. |
| `showInTable` | no (frontend) | `true` adds a column in the list table rendering the related entity's name. |

> **The relationship `name` + `directory` must match the REAL target entity, not a structure file.** Some `structure/*.json` files are stale (e.g. a legacy `Item`/`items` lingers in `catalog.json` while the live entity is `CatalogItem`/`catalog-items` in `features/catalog`). Verify the target against its actual `*.meta.ts` (`nodeName`/`endpoint`), its `ModuleId` key, and the feature directory it lives in — the frontend resolver builds the import path from `kebab(name)` under `directory`, so a wrong name produces broken imports.

### Inference guidance (natural language → schema)

- "belongs to / has one X" → `single: true`. "has many X" → `single: false`.
- "X is required" → `nullable: false`. "optional" → `nullable: true`.
- Pick `relationshipName` as an UPPER_SNAKE verb for the edge (`FOR`, `BELONGS_TO`, `MANAGED_BY`). When unsure, ask — it is a domain-modelling choice.
- Only add `alias`/`dtoKey` when there is a collision (two rels to the same entity) or the wording demands a specific key. A lone `Account` relationship needs neither (defaults to key `account`).
- A money amount (price, total, value) → `type: "number"` + `kind: { "type": "money" }`.
- An `image`/`logo` field → `type: "string"` + set module `requiresS3: true`.

## Example 1 — simple (a `Location` under crm)

```json
{
  "moduleId": "11111111-1111-4111-a111-111111111111",
  "moduleName": "Location",
  "endpointName": "locations",
  "targetDir": "features/crm",
  "extendsContent": false,
  "languages": ["en", "it"],
  "description": "A physical address linked to an account or person.",
  "fields": [
    { "name": "address", "type": "string", "nullable": false, "description": "Full formatted address." },
    { "name": "city", "type": "string", "nullable": true },
    { "name": "is_primary", "type": "boolean", "nullable": true }
  ],
  "relationships": [
    {
      "name": "Account", "directory": "features/crm", "single": true,
      "relationshipName": "AT_ACCOUNT", "toNode": true, "nullable": true,
      "showInTable": true
    }
  ]
}
```

## Example 2 — complex (an `Opportunity`-style module with edge fields + alias + derived field)

```json
{
  "moduleId": "22222222-2222-4222-a222-222222222222",
  "moduleName": "Opportunity",
  "endpointName": "opportunities",
  "targetDir": "features/crm",
  "featureId": "Crm",
  "languages": ["en", "it"],
  "description": "A sales opportunity for an account, tracked through a pipeline.",
  "chat": { "summary": "data.name ?? data.id", "textSearchFields": ["name"] },
  "fields": [
    { "name": "name", "type": "string", "nullable": false },
    { "name": "value", "type": "number", "nullable": true, "kind": { "type": "money" } },
    {
      "name": "effective_value", "type": "number", "nullable": true, "readOnly": true,
      "kind": { "type": "money" },
      "computed": "p.record?.get('effective_value') ?? undefined",
      "description": "Total of the latest sent/accepted quote (pipeline reads only)."
    },
    { "name": "expected_close_date", "type": "date", "nullable": true }
  ],
  "relationships": [
    {
      "name": "Account", "directory": "features/crm", "single": true,
      "relationshipName": "FOR", "toNode": true, "nullable": false,
      "dtoKey": "account", "description": "The account this opportunity is for."
    },
    {
      "name": "Item", "alias": "EstimateItem", "directory": "features/plm", "single": false,
      "relationshipName": "HAS_ESTIMATE_ITEM", "toNode": true, "nullable": true,
      "dtoKey": "estimateitems", "showInTable": false,
      "fields": [{ "name": "quantity", "type": "number", "nullable": false }]
    }
  ],
  "containerTabs": {
    "activity": true,
    "relations": [{ "module": "Quote", "listProp": "opportunity", "directory": "sales" }]
  },
  "inclusions": {
    "related": [{ "endpoint": "accounts", "fields": ["name", "image"] }]
  }
}
```

For more real examples, read the existing files in `structure/` (e.g. `crm.json`, `warehouse.json`, `plm.json`) — but treat their `moduleName`s as **possibly stale**; cross-check any entity you reference against its live `*.meta.ts` and `ModuleId` key.
