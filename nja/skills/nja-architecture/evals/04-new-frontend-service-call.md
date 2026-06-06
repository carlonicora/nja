# Eval 04 — Add a new frontend service call

## Setup (paste into Claude)

> In the Account service at `apps/web/src/features/crm/account/data/AccountService.ts` (or any existing `*Service.ts`), add a method `fetchClientAccounts()` that GETs `/accounts?role=client` and returns the rehydrated Account models. (Note: in this codebase, "clients" are Accounts with `AccountRole='client'` — there is no separate Client entity.)

## Expected behavior (before writing code)

1. Claude invokes the `nja-architecture` skill.
2. The routing table matches `apps/web/src/features/*/data/*Service.ts`.
3. Claude reads, in order:
   - `references/frontend/03-services.md`
   - `references/anti-patterns.md`

## Pass criteria

- The method calls `callApi()` — never `fetch()` directly.
- The `callApi()` call passes `type: Modules.X` (correct module enum).
- The URL is built via `EndpointCreator` — no hardcoded `/accounts` string in the service.
- No manual JSON:API parsing — the model's `rehydrate()` handles it.

## Fail signals

- A bare `fetch('/api/accounts?role=client')` call.
- A hardcoded URL string.
- Manual `response.data.attributes` access on the JSON:API payload.
