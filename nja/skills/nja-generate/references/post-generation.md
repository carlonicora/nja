# Post-generation steps & gotchas

The generators scaffold the module files and (unless `--no-register`) wire registration.
They CANNOT do the steps below — do them in order. Step 1 is build-blocking.

## 1. Add the `ModuleId` entry (REQUIRED — build fails without it)

The generated backend module does `import { ModuleId } from "@<scope>/shared"` and calls
`this.graphRegistry.register({ descriptor, moduleId: ModuleId.<Module> })`. If `ModuleId.<Module>`
is missing, the backend (and the shared package) **fail to compile**.

- File: `packages/shared/src/const/module.id.ts`
- Add: `<Module>: "<uuid>",` using the **exact same UUID** as the structure JSON `moduleId`.
- Place it under the matching domain comment block.
- The frontend `Modules.<Module>` registry resolves from this same map, so this also unblocks the frontend.

## 2. Seed the Neo4j `(Module)` node (REQUIRED for graph/chatbot/RBAC integration)

`module.id.ts`'s header states these IDs are "seeded in `apps/api/src/neo4j.migrations/20250901_002.ts`
and `20250901_005.ts`" and are the authoritative identity for the `(Module)` nodes. Feature modules
register their entity descriptors with the chatbot's `GraphDescriptorRegistry` by these IDs.

- Add a seed entry for the new module's UUID following the pattern in `20250901_005.ts` (feature modules).
- Without it, the chatbot catalog / graph features desync, even though plain CRUD may work.

## 3. Regenerate RBAC paths (REQUIRED for the endpoints to be permission-reachable)

New controller routes need RBAC entries.

- Run: `pnpm --filter <api-app> generate:rbac-paths`
- This rebuilds the module-id map and `src/features/rbac/module-relationships.map.ts`.
- The declarative permission matrix lives at `apps/api/src/rbac/permissions.ts` (see `apps/api/CLAUDE.md` "RBAC"). New modules typically need permission entries before their routes are usable.

## 4. Complete i18n (if `languages` did not include `"it"`)

The frontend generator only updates the locale files listed in the JSON's `languages`. The repo ships
both `apps/web/messages/en.json` and `it.json`. If you generated with `["en"]` only, the Italian help
keys are absent — add the `features.<module>.*` keys to `it.json`, or regenerate with `["en", "it"]`.
Reuse existing entity-named keys where possible.

## 5. Add the `FeatureIds` entry (only if you set `featureId`)

If the module JSON has `featureId: "X"`, the generated frontend module factory references
`FeatureIds.X`. Confirm `FeatureIds.X` exists in `apps/web/src/enums/feature.ids.ts`; add it if not.

## 6. Fill the bespoke gaps (the generator only scaffolds standard CRUD)

The output is a working CRUD scaffold. Anything beyond standard CRUD is hand-added afterward, e.g.:
- Custom business logic methods on the service/repository (custom Cypher, side effects).
- Rich editors with bespoke pickers / multi-step wizards (the generated `Editor` is a basic `EditorSheet`).
- Inline cell controls (`components/inline/…`), custom detail content beyond `AttributeElement`s.
- `containerTabs` that need a hand-rolled tab (e.g. a Tasks tab).

## 7. Verify

1. `pnpm lint` — must be 0 errors; the translation validator must say "All translation keys are valid!".
2. `pnpm build` — full monorepo; this is where missing `ModuleId` / type issues surface.
3. Invoke the **`nja-architecture`** skill and audit the generated files against the layer rules
   (entity descriptor, DTOs, repository company-scoping, model `rehydrate`/`createJsonApi`,
   `formatLocalDate` on dates, `dtoKey` parity backend↔frontend).
4. Run the relevant tests if the change is substantial (`pnpm --filter <api-app> test` / `<web-app> test`).

## Gotchas checklist

- [ ] `moduleId` in JSON === `ModuleId.<Module>` value === migration seed UUID (all three in sync).
- [ ] JSON lives in `structure/` (frontend cross-module resolution depends on it).
- [ ] Name / endpoint / page route not already taken (checked BEFORE generating).
- [ ] Generators built from source (`dist/`) if you changed the templates.
- [ ] `relationshipName` is an UPPER_SNAKE verb; `toNode: true` = outgoing.
- [ ] `alias`/`dtoKey` only where there is a collision or a required specific wire key.
- [ ] `requiresS3: true` if the entity has an image/file field.
- [ ] Money fields use `kind: { "type": "money" }`; derived fields use `computed` + `readOnly`.
