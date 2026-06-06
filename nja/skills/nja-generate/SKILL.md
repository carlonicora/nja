---
name: nja-generate
description: Use when creating, scaffolding, or generating a new feature module or entity in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo — backend (NestJS), frontend (Next.js), or both. Triggers include "create a new module", "scaffold an entity", "generate the backend/frontend for X", "add a feature module", or building a new feature that needs CRUD code.
---

# Generate a module (nestjs-neo4jsonapi + nextjs-jsonapi)

## Overview

nestjs-neo4jsonapi and nextjs-jsonapi ship two purpose-built code generators that scaffold a complete module from a single JSON "module shape". **Always use the generators — never hand-write the entity / DTO / repository / service / controller / model / component files.** Hand-written modules drift from the live templates and violate the architecture.

- **Backend (NestJS + Neo4j):** `pnpm generate-module <json>`
- **Frontend (Next.js):** `pnpm generate-web-module <json>`

Both read the **same** JSON schema (an array of module definitions). Your job is to turn a module description into a correct JSON schema, run the generators, and complete the handful of manual steps the generators can't do (chiefly the `ModuleId` enum).

> **Placeholders:** this skill uses `<api-app>` / `<web-app>` for the workspace package names of your NestJS API and Next.js web apps (the values you pass to `pnpm --filter`), and `@<scope>/shared` for your shared-types package. Substitute your repo's actual names before running any command.

## When to use

- Asked to create / scaffold / generate a new module or entity (directly or as part of a feature).
- Default scope is **both** backend and frontend; honour "backend only" / "frontend only".

**When NOT to use:** editing an existing module's bespoke logic (custom editors, business methods) — the generators only scaffold standard CRUD; refine by hand afterward.

## Workflow

Run from the monorepo root. **REQUIRED REFERENCE:** read `references/schema-reference.md` before authoring the JSON, and `references/post-generation.md` before/after generating.

1. **Decide scope** — backend, frontend, or both (default both).

2. **Check for name/endpoint collisions FIRST.** A clash silently overwrites or duplicates existing code. Grep for the proposed `moduleName`, `endpointName`, and page route:
   ```bash
   grep -rn "<Module>Module\|\"<plural>\"\|/<plural>\b" apps/web/src/config/Bootstrapper.ts apps/web/src/app packages/shared/src/const/module.id.ts apps/api/src/features/*/*.modules.ts
   ```
   If taken (e.g. "Supplier" is already an Account role-view), pick a different name/endpoint or resolve the collision with the user before proceeding.

3. **Gather the module shape.** From the user's description; if invoked autonomously and details are missing, ask targeted questions. You need: domain (`targetDir`), fields (name, type, nullable, optional description/kind), relationships (target entity, its `directory`, cardinality, Neo4j edge name, direction, optional edge fields / alias / dtoKey). See `references/schema-reference.md` for every field and how to infer it.

4. **Author the structure JSON** in a **single-module file** `structure/<module-kebab>.json` (a one-element array). Two reasons it must be its own file in `structure/`:
   - The frontend generator scans **every `*.json` in that directory** to resolve cross-module relationship selectors, so it MUST live in `structure/`.
   - The backend generator **errors** (`Files already exist. Use --force`) on the first already-generated module in a multi-module array — so do NOT generate from the shared `structure/<domain>.json` (it would abort on existing siblings, and `--force` would overwrite/regenerate them, discarding hand edits). A single-module file processes only the new module.

   Mint a fresh UUID for `moduleId`. Verify each relationship's target `name`/`directory` against the **live** entity (its `*.meta.ts` and `ModuleId` key), not a possibly-stale structure file.

5. **Build the generators if stale** (they run from `dist/`):
   ```bash
   pnpm --filter @carlonicora/nestjs-neo4jsonapi build
   pnpm --filter @carlonicora/nextjs-jsonapi build
   ```

6. **Dry-run** to preview the file list (writes nothing):
   ```bash
   pnpm generate-module structure/<module-kebab>.json --dry-run
   pnpm generate-web-module structure/<module-kebab>.json --dry-run
   ```

7. **Confirm with the user** — show the authored shape and the dry-run file list before any real write.

8. **Generate** (real write + auto-registration). Add `--force` only when intentionally re-scaffolding (it overwrites and discards hand edits); add `--no-register` to skip editing the parent modules file / `Bootstrapper.ts` / i18n.
   ```bash
   pnpm generate-module structure/<module-kebab>.json
   pnpm generate-web-module structure/<module-kebab>.json
   ```

9. **Complete the manual steps** in `references/post-generation.md` — most importantly add `<Module>: "<same-uuid>"` to `packages/shared/src/const/module.id.ts` (**the build fails without it**), then the Neo4j module-node seed, RBAC paths, and `it.json` i18n.

10. **Verify.** Run `pnpm lint` and `pnpm build` (full monorepo). Then invoke the `nja-architecture` skill to audit the generated code, and flag the bespoke parts the generator only scaffolds (custom business logic, custom editor pickers).

## Quick reference

| What | Command / location |
|---|---|
| Backend generator | `pnpm generate-module structure/<module-kebab>.json [--dry-run] [--force] [--no-register]` |
| Frontend generator | `pnpm generate-web-module structure/<module-kebab>.json [--dry-run] [--force] [--no-register]` |
| Input JSON | `structure/<module-kebab>.json` — single-module array, lives in `structure/` |
| ModuleId enum (manual) | `packages/shared/src/const/module.id.ts` — `moduleId` UUID must match |
| Module-node seed (manual) | `apps/api/src/neo4j.migrations/20250901_005.ts` |
| RBAC paths | `pnpm --filter <api-app> generate:rbac-paths` |

## Common mistakes

- **Skipping the `ModuleId` entry** → `ModuleId.<Module>` is undefined → backend build fails. Always do step 9 first.
- **Generating from the shared `structure/<domain>.json`** → backend errors `Files already exist` on existing siblings. Use a single-module `structure/<module-kebab>.json`.
- **Putting the JSON outside `structure/`** → frontend relationship selectors resolve wrong (the generator can't see sibling modules).
- **Edge fields with `required: true`** → the key is ignored; use `nullable: false`/`true` instead.
- **Trusting a stale structure file's entity name** → e.g. `Item` vs the live `CatalogItem`; verify against the entity's `*.meta.ts` and `ModuleId`.
- **`kind: { "type": "money" }` expecting frontend money UI** → it's a backend hint only; money formatting is manual.
- **Hand-writing module files** → drift from templates; use the generators.
- **Reusing a taken name/endpoint** → overwrites existing pages / duplicates registry keys. Always do step 2.
- **`languages: ["en"]` only** → Italian (`it.json`) is left empty; add `"it"` or translate manually.
