---
name: nja-arrows
description: Use when generating feature modules from an Arrows.app diagram or any Neo4j-style entity-relationship JSON (a `{nodes, relationships, style}` export) in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo. Triggers include "generate modules from this diagram", "import the arrows/ER JSON", "scaffold from <name>.json", or turning a graph data-model export into modules.
---

# Generate modules from an Arrows.app diagram

## Overview

Translate an **Arrows.app** export (`{ nodes, relationships, style }`) into confirmed `structure/<module>.json` files, then hand off to **`nja-generate`** for the actual scaffolding. The diagram is the **single source of truth** for entities, fields, and edges; everything Arrows can't express is **asked and confirmed per node — never invented**.

**Core principle:** the diagram says WHAT exists; the user confirms the SHAPE. You translate and ask — you do not back-fill from prior knowledge, and you do not silently drop or fold anything.

## When to use

- You're handed an Arrows.app JSON (or any `{nodes, relationships, style}` graph export) and asked to create the corresponding modules.
- Works for ANY such JSON — nothing is hardcoded to a particular schema.

**When NOT to use:** authoring a single module from a text description (use `nja-generate` directly); editing an existing module's bespoke logic.

## The pipeline

1. **Ingest** the JSON (path given or ask). Validate it is `{ nodes, relationships, style }`. If not, stop.
2. **Parse** into an entity model using `references/arrows-mapping.md` (the encoding rules). Per node: `name = caption`, `fields` from `node.properties`. Per relationship: owner = `fromId` (`toNode: true`), `relationshipName = type`, edge `fields` from `relationship.properties`.
3. **Classify every node** (see Classification). Compute generation order: a module's relationship targets must be generated before it (foundation/existing targets count as already-present).
4. **Per net-new node, in order — the confirmation gate (MANDATORY):**
   a. Resolve only what the diagram can't encode by asking the user: each relationship's **cardinality** (single/many) and **nullability**, any **ambiguous field type**, the **targetDir**, and any **alias** (two edges to the same target).
   b. **Present the COMPLETE proposed `structure/<module>.json` and require explicit confirm/edit before writing or generating anything.** One node at a time.
   c. On confirmation: write `structure/<module-kebab>.json` (a one-element array, fresh UUID v4 `moduleId`).
   d. **Invoke the `nja-generate` skill** for that structure file (it builds, dry-runs, generates, and lists the manual steps). Then move to the next node.
5. **New edges owned by an existing module** (target or owner already exists): after the net-new modules, for each such edge, show the **exact descriptor diff** to add to the existing entity and **ask per-edit confirmation** before applying it. Never edit a hand-tuned descriptor silently.
6. **Final report:** generated (net-new) / skipped (existing + foundation, with reasons) / existing-module edits applied or offered / anything that needs manual follow-up.

## Classification (every node)

Decide by querying the repo — never by node colour, position, or any visual cue:

| Class | Test | Action |
|---|---|---|
| **foundation** | name resolves to a framework entity (User, Company, …) — present as a `ModuleId` seeded by the package, importable from `@foundation` | **skip generation**; relationships route to it with `directory: "@foundation"` |
| **existing** | a `ModuleId.<Name>` and/or `apps/api/src/features/**/<kebab>` already exist | **skip generation** (don't clobber); only its NEW edges are handled via step 5 |
| **net-new** | neither of the above | **generate** |

## Encoding convention (source of truth)

- A node's/relationship's `properties` is a `{ key: value }` map → fields. **Key = field name**, a trailing **`!` = required** (else optional). **Value = type**, normalized (case-insensitive; `BlockNote`→`blocknote`). See `references/arrows-mapping.md` for the full type table.
- A relationship's `properties` become that relationship's **edge `fields[]`** (same rule).
- **A node with no `properties` has NO known fields — ASK the user; do not invent any.** (A module still needs a display field, usually `name` — ask, don't assume.)

## Common mistakes (these are the baseline failures — do not repeat)

- **Inventing fields** the diagram doesn't contain (back-filling `name`/`description`/etc. from memory). The diagram is the source of truth; empty `properties` → ask.
- **Folding nodes into fields via heuristics** (e.g. node colour). Every node is a module candidate; the only reasons to not generate one are *foundation* or *existing*.
- **Silently dropping nodes or edges.** Everything is generated, routed, flagged, or explicitly confirmed-as-dropped by the user.
- **Skipping the per-node confirmation gate.** Confirm each module's full structure before writing/generating it.
- **Reusing an on-disk UUID for a net-new module** (mint fresh) or **regenerating an existing module** (skip it).
- **Guessing cardinality/nullability.** Arrows encodes neither — ask.

## Reference

- `references/arrows-mapping.md` — exact parse rules: caption→names, `properties`→fields, type normalization table, edge ownership/direction, alias detection, ordering.
- `nja-generate`'s `references/schema-reference.md` — the target `structure/*.json` schema (do not duplicate it).
