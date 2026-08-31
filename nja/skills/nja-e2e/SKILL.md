---
name: nja-e2e
description: Use when adding end-to-end test coverage for a page or route in an nja monorepo — read the page's real behaviour, enumerate the tests it needs as Given/When/Then entries with coverage IDs, then write the Playwright specs that satisfy them. Triggers include "write e2e tests for /accounts", "cover this page with e2e", "what e2e tests does this page need", "add coverage for the settings page", or a request to expand the e2e suite one page at a time.
---

# E2E coverage for a page

Turn one page into a reviewed test list, then into passing Playwright specs.

**Two passes, and the gap between them is the point.** Pass 1 writes only
documentation — the page's behaviour and the tests it needs, as Given/When/Then.
You read that list and correct it while it is still prose. Pass 2 turns the
approved list into specs. Enumerating tests is where the thinking is; writing
them is transcription. Doing both in one breath means every correction to the
list costs a rewrite of the code.

The coverage document says this itself: a ❌ entry's *"Given/When/Then is the
implementation spec"*.

---

## Before anything: read the repo's own guide

`apps/web/tests/README.md` is the authority on conventions — selector strategy,
support helpers, the seeding model, serial-vs-isolated, and a "traps we already
paid for" section. It ships in the template, so every nja repo has one. **Read
it before pass 2**, and do not restate its rules from memory.

This skill covers only what that guide does not: how to go from a page to the
list of tests it needs. That method lives in `references/discovery.md`.

---

## Pass 1 — discover

Writes documentation only. Touches no `.spec.ts`, no app source.

### 1. Resolve the page

The user names a route (`/accounts`) or a file. Map one to the other under
`apps/web/src/app/[locale]/…/page.tsx`. If the route is dynamic
(`/proceedings/[id]`), say which concrete instance the tests will use and where
that instance comes from — a seeded fixed id, not whatever happens to be in the
database.

### 2. Read the code, in full

Not skim. The page, the components it renders, the data it fetches, the API
entity/DTO behind that data, and the i18n messages any assertion will match.

This is the standard the existing suite already holds itself to — its spec
files carry a literal `Sources read in full:` list naming every component
consulted. An assertion written without reading the component is a guess, and it
will be a `getByText` guess, which is the selector of last resort.

`references/discovery.md` says what to read and in what order.

### 3. Enumerate the tests

Each candidate becomes one Given/When/Then. Write behaviours, not clicks — the
test proves something is true, and the title has to say what.

Decide explicitly what is **out of scope** rather than silently omitting it: the
coverage doc has a ⛔ status for external SSO/OAuth, live LLM calls, real email
and similar. An unlisted behaviour reads as an oversight; a ⛔ entry reads as a
decision.

### 4. Allocate IDs

The format is `<PREFIX>-<NN>`, e.g. `MKT-03`, `PRC-11`.

- **Prefix** — the page's domain. Reuse the existing prefix for that domain;
  a360ai has ~20 (`SET FND MKT LAW ADM AUTH PRC CRM OPP TSK COM QTE DOC PRT` …).
  Propose a **new** prefix only when the page belongs to no existing domain, and
  say so in the report rather than inventing one silently.
- **Number** — the next free one for that prefix. **Scan every entry in the
  coverage document first.** There are hundreds; an id is a permanent citation
  key and reusing one corrupts the two-way link in both directions.
- One test may legitimately carry several ids (`ADM-04/05/08: …`) when it proves
  several catalogued behaviours in one pass.

### 5. Write the coverage entries

Into the repo's coverage document, under the page's own section:

```md
## `/route` — Page name

### Functionality
<what the page does, derived from the code you read>

### Tests

#### MKT-03 · FAQ accordion expands one answer at a time — ❌
- **Given** an anonymous visitor on `/` scrolled to "Domande frequenti"
- **When** they click the first question trigger, then a second question trigger
- **Then** the first answer becomes visible; after clicking the second, the
  second answer is visible and the first is collapsed (`multiple={false}`)
- _Seed:_ none

### Notes
<anything a future author needs: locale, fixture coupling, known product bugs>
```

Status starts ❌ (Missing). `_Seed:_` is required on every entry — `none`,
`existing`, or the specific seed module the test depends on.

### 6. Stop and report

List the proposed tests, their ids, and anything you marked ⛔. **Wait.** The
whole value of pass 1 is that the user corrects the list before it becomes code.

---

## Pass 2 — implement

Only after the list is approved.

### 7. Write the spec

Location follows the suite's own split: `tests/unauthenticated/`,
`tests/authenticated/`, `tests/smoke/`.

Test title is **exactly** `<ID>: <what it proves>` — this is enforced, and it is
the citation key. The file opens with a doc-comment carrying at minimum:

- what the file covers, and what deliberately lives elsewhere
- `Scope: e2e-coverage.md <the ids>`
- `Sources read in full:` — every component you actually read
- locale and isolation notes where they matter

### 8. Selectors — and the one thing you may not do

Priority is `getByTestId` → `getByRole` → `getByText`, per the repo guide.

When an element you must assert on has **no testid**, the guide says to add one
to the component. **This skill does not.** Collect them and report:

```
apps/web/src/features/x/components/FooTable.tsx
  <TableRow> for each account   →  data-testid="account-row"
```

Editing app source so a test can pass is how a suite starts shaping the product
instead of checking it, and it puts attributes into production markup on a
guess. Propose; let the user apply; then write the assertion.

If a testid is refused, fall back to `getByRole` with the caveats the guide
documents — never to a CSS class or DOM shape.

### 9. Close the two-way link

Flip each entry from ❌ to ✅ and append the citation:

```
#### MKT-03 · … — ✅ `tests/unauthenticated/marketing-interactions.spec.ts` › "MKT-03: Home FAQ accordion expands one answer at a time"
```

The quoted title must match the `test(...)` title **byte for byte**. A rename
updates both sides in the same change or the link silently breaks — nothing
fails loudly when it does.

### 10. Report

Tests written, ids closed, testids proposed but not applied, and how to run just
these tests against a stack that is already up (the repo guide documents the
fast inner loop). **This skill does not run the suite** — a full boot is minutes
and belongs to `nja-pre-release`.

---

## Bootstrap — a repo with no coverage document

Some repos have the tests and helpers but no coverage document. Create it before
pass 1 writes into it, with the same skeleton: title, the status legend
(✅ Covered / 🟡 Partial / ❌ Missing / ⛔ OOS / 🚧 Blocked), and the page section
shape above. Then proceed.

Do **not** retro-document the existing suite in the same run. Bootstrapping the
file is cheap; back-filling entries for every test already written is a separate,
much larger job — say so and let the user decide.

---

## Red flags — stop if you catch yourself here

| Thought | Reality |
|---|---|
| "I can see what the page does from the route name." | You cannot. Read the components; the assertions come from them. |
| "I'll write the entries and the specs together, it's one job." | Then the user reviews code instead of a list, and every correction is a rewrite. |
| "There's no testid, I'll match the visible text." | Text is the last resort and is locale-fragile. Propose the testid. |
| "I'll just add the `data-testid` myself, it's one attribute." | This skill does not edit app source. Propose it. |
| "This id looks free." | Scan the whole document. Ids are permanent citation keys. |
| "The title is close enough to the citation." | Byte for byte, or the link is broken and nothing will tell you. |
| "I'll skip the behaviours I'm not sure how to test." | Mark them ⛔ with a reason. Silence reads as an oversight. |
| "I should run the suite to prove these pass." | That is `nja-pre-release`. Report how to run them. |
| "The page has 40 behaviours, I'll cover them all." | Propose the list and let the user cut it. Volume is not coverage. |

## Hands-off

**Never commit, stage, push, or stash.** Never edit app source. Leave the
working tree dirty with exactly the documentation and specs you wrote.
