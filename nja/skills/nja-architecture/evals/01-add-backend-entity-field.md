# Eval 01 — Add a field to a backend entity

## Setup (paste into Claude)

> Add an optional `notes: string` field to the Account entity at `apps/api/src/features/crm/account/entities/account.ts` (or any existing entity under `apps/api/src/features/*/entities/`). The field should be nullable in Neo4j and surface through the JSON:API response.

## Expected behavior (before writing code)

1. Claude invokes the `nja-architecture` skill.
2. The skill's routing table matches `apps/api/src/features/*/entities/*`.
3. Claude reads, in order:
   - `references/core-principles.md`
   - `references/backend/01-entity-basics.md`

## Pass criteria

- The new field appears in the entity's Entity Descriptor (NOT inserted manually into a Cypher query).
- The associated `*.meta.ts` is updated with the new field metadata.
- No raw Neo4j `result.records` access introduced anywhere in the diff.
- No manual JSON:API payload construction.

## Fail signals

- Claude edits the entity file before invoking the skill.
- Claude bypasses the Entity Descriptor and writes a custom Cypher query for the field.
- DTOs aren't updated when the routing chain pulls them in for a NEW field.
