# Arrows.app → structure JSON mapping

How to translate a `{ nodes, relationships, style }` Arrows export into the `structure/<module>.json` shape that `nja-generate` consumes. Target schema: `nja-generate`'s `references/schema-reference.md` (authoritative — do not duplicate it here).

## Arrows shape (input)

```jsonc
{
  "nodes": [{ "id": "n1", "caption": "Game", "labels": [], "properties": { "name!": "string", "description": "BlockNote" }, "style": {} }],
  "relationships": [{ "id": "n1", "type": "INCLUDES", "fromId": "n1", "toId": "n2", "properties": { "role": "string" } }],
  "style": { /* visual only — IGNORE for modeling */ }
}
```

Ignore `style` and node visual attributes entirely. Modeling decisions come from `caption`, `properties`, relationship `type`/`fromId`/`toId`/`properties` only.

## Nodes → modules

| structure field | derived from | rule |
|---|---|---|
| `moduleName` | `node.caption` | PascalCase (captions are usually already PascalCase) |
| `endpointName` | `caption` | kebab-case + pluralize (`Game`→`games`, `GameSetting`→`game-settings`, `Npc`→`npcs`) |
| `targetDir` | — | not in the diagram → default `features/<kebab(caption)>`, **ask to confirm/override** |
| `moduleId` | — | mint a fresh UUID v4 for each net-new module |
| `languages` | — | `["en"]` (or repo default) |
| `fields` | `node.properties` | see Properties → fields |

## Properties → fields (nodes AND relationships)

`properties` is a `{ key: value }` string map.

- **Key** = field name. A trailing **`!`** means **required** → `nullable: false`. No `!` → `nullable: true`. Strip the `!` from the stored name (`"name!"` → field `name`, required).
- **Value** = type. Normalize case-insensitively:

| Arrows value (any case) | structure `type` |
|---|---|
| `string`, `text`, `str` | `string` |
| `number`, `int`, `integer`, `float`, `decimal` | `number` |
| `boolean`, `bool` | `boolean` |
| `date` | `date` |
| `datetime`, `timestamp` | `datetime` |
| `json`, `object` | `json` |
| `blocknote`, `richtext`, `rich-text` | `blocknote` |
| `money`, `currency` | `number` + `kind: { "type": "money" }` |
| `<type>[]` (e.g. `string[]`) | the array form |
| anything else / empty | **ambiguous → ask the user** (do not guess) |

- **A node with empty `properties` ⇒ no known fields. ASK the user** which fields it has (at minimum the display field, commonly `name`). Never invent fields from prior knowledge of the repo.

## Relationships → relationships

Each relationship is declared on its **owner = the `fromId` node** (matches the repo convention: the owner declares the edge; the target declares no inverse).

| structure field | derived from | rule |
|---|---|---|
| `name` | `toId` node's caption | the target entity |
| `directory` | target's classification | `@foundation` if the target is a foundation entity, else `features/<kebab(target)>` |
| `relationshipName` | `relationship.type` | used verbatim (already UPPER_SNAKE) |
| `toNode` | always `true` | owner is `fromId`, so the edge is outgoing |
| `single` | — | **not encoded by Arrows → ask** (single = to-one, false = to-many) |
| `nullable` | — | **not encoded by Arrows → ask** |
| `fields` | `relationship.properties` | edge fields, same Properties→fields rule (e.g. `{ "role": "string" }`) |
| `alias` | collision detection | **required when one node has 2+ edges to the SAME target**; not needed when targets differ (e.g. two `PLAYED_BY` to User and Npc keep keys `user`/`npc`) |

Edges whose owner (`fromId`) is a **net-new** node are emitted in that module's structure JSON. Edges whose owner is an **existing or foundation** node are handled by the SKILL's "existing-module edges" step (offer the descriptor diff), NOT written into a new structure file.

## Foundation detection

A node is a foundation entity if its name matches a framework entity provided by `@carlonicora/nestjs-neo4jsonapi` (e.g. `User`, `Company`). Confirm by checking the `ModuleId` map / `@foundation` exports. Foundation nodes are never generated; relationships to them use `directory: "@foundation"`.

## Existing detection

A node already exists if `ModuleId.<Name>` is present in `packages/shared/src/const/module.id.ts` and/or a feature dir `apps/api/src/features/**/<kebab>/` exists. Existing nodes are skipped (no regeneration); only their NEW edges are offered as descriptor edits.

## Generation order

Topological: a module is generated only after every relationship target it references is already present (generated, existing, or foundation). Break ties alphabetically. Generate each from its own single-module `structure/<kebab>.json` (never a multi-module array — the backend generator aborts on the first already-generated sibling).

## Worked example (one node)

Arrows node `{"caption":"Game","properties":{"name!":"string","description":"BlockNote"}}` + edges `INCLUDES`(→Npc, props `{role:string}`), `IN`(→GameSetting), `PLAYED_BY`(→User), with the user confirming: `INCLUDES` many/required, `IN` single/required, `PLAYED_BY` single/required, targetDir `features/game` →

```json
[
  {
    "moduleId": "<fresh-uuid>",
    "moduleName": "Game",
    "endpointName": "games",
    "targetDir": "features/game",
    "languages": ["en"],
    "fields": [
      { "name": "name", "type": "string", "nullable": false },
      { "name": "description", "type": "blocknote", "nullable": true }
    ],
    "relationships": [
      { "name": "Npc", "directory": "features/npc", "single": false, "relationshipName": "INCLUDES", "toNode": true, "nullable": false,
        "fields": [{ "name": "role", "type": "string", "nullable": true }] },
      { "name": "GameSetting", "directory": "features/game-setting", "single": true, "relationshipName": "IN", "toNode": true, "nullable": false },
      { "name": "User", "directory": "@foundation", "single": true, "relationshipName": "PLAYED_BY", "toNode": true, "nullable": false }
    ]
  }
]
```

Everything in `fields`/`relationships` that the diagram didn't encode (`single`, `nullable`, `targetDir`) was **asked**, not assumed; nothing was invented or dropped.
