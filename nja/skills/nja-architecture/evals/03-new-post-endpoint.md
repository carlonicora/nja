# Eval 03 — Create a new POST endpoint with validation

## Setup (paste into Claude)

> In the Account controller at `apps/api/src/features/crm/account/controllers/account.controller.ts`, add a new `POST /accounts/:id/annotations` endpoint that creates an Annotation attached to the Account. The body is `{ content: string }`. Use the existing CRUD scaffolding.

## Expected behavior (before writing code)

1. Claude invokes the `nja-architecture` skill.
2. Claude reads, in order:
   - `references/backend/05-controllers.md`
   - `references/backend/02-dtos.md`

## Pass criteria

- A new DTO file is created (or an existing one extended) with class-validator decorators on `content`.
- The endpoint uses `createCrudHandlers()` or `createRelationshipHandlers()` — not a hand-rolled handler.
- The endpoint path is built from a meta constant — no hardcoded route string in the controller.
- The controller calls a service, never the repository directly.

## Fail signals

- The body is destructured directly without a DTO class.
- The route string is hardcoded inline (e.g., `@Post('accounts/:id/annotations')` with the literal path).
- Controller imports a repository.
