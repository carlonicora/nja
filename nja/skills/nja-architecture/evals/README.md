# Evals — nja-architecture skill

Manual replay scenarios that verify Claude follows this skill's rules. Each `NN-<name>.md` file contains:

- **Setup** — a one-line task to give Claude in a fresh Code session
- **Expected behavior** — the skill invocation and references Claude must read before writing code
- **Pass criteria** — concrete checks against the resulting diff and behavior

## How to run

1. Open a fresh Claude Code session in the repo (`/clear` an existing one or open a new terminal).
2. Paste the **Setup** text into Claude.
3. Observe whether Claude meets the **Expected behavior** before writing code.
4. Inspect the resulting diff against the **Pass criteria**.
5. Discard or revert any code changes after replay (these are diagnostic, not real changes).

## When to run

- After modifying `SKILL.md` (especially the routing table or `description`).
- After modifying this plugin's `hooks/remind-architecture.sh`.
- Before bumping any version that touches the skill.

## v1 scenarios (5)

| # | File | Tests |
|---|---|---|
| 1 | `01-add-backend-entity-field.md` | Entity Descriptor pattern; meta updated |
| 2 | `02-custom-cypher-query.md` | `buildDefaultMatch`, `{CURSOR}`, parameterized query |
| 3 | `03-new-post-endpoint.md` | DTO + `createCrudHandlers` + meta constants |
| 4 | `04-new-frontend-service-call.md` | `callApi()` not `fetch`; `type: Modules.X`; `EndpointCreator` |
| 5 | `05-baseui-trigger-composition.md` | `render` prop, no `asChild`, no `<Button>`-in-trigger |
