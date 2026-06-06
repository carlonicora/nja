# Eval 02 — Add a custom Cypher query to a repository

## Setup (paste into Claude)

> In the Account repository at `apps/api/src/features/crm/account/repositories/account.repository.ts` (or any existing `*.repository.ts`), add a method `findAccountsCreatedAfter(date: Date)` that returns paginated results.

## Expected behavior (before writing code)

1. Claude invokes the `nja-architecture` skill.
2. The skill's routing table matches `apps/api/src/features/**/*.repository.ts`.
3. Claude reads, in order:
   - `references/backend/03-repositories.md`
   - `references/anti-patterns.md`

## Pass criteria

- New method extends `AbstractRepository` patterns.
- Query begins with `buildDefaultMatch(...)` (company filtering auto-injected).
- Pagination uses the `{CURSOR}` placeholder — no manual `SKIP`/`LIMIT`.
- Date parameter is passed via parameterized query, not interpolated into the Cypher string.
- `initQuery()` is called with `serialiser`.
- Results returned via `readMany()` — never raw `result.records`.

## Fail signals

- String concatenation building the Cypher query.
- Manual `SKIP $skip LIMIT $limit` instead of `{CURSOR}`.
- Repository called directly from a controller (must go through service).
