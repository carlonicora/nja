# Discovery — from a page to the tests it needs

Pass 1's method. Conventions for *writing* the tests live in the repo's own
`apps/web/tests/README.md`; this file covers only the step that guide assumes
you have already done — knowing which tests to write.

The goal is a list a reviewer can correct in a minute. That means each entry
names a behaviour and its evidence, not a click sequence.

---

## 1. What to read, in order

Read all of it before writing a single entry. Stopping early is what produces
tests that assert the wrong thing confidently.

1. **The page** — `apps/web/src/app/[locale]/…/page.tsx`. Server or client?
   What does it fetch, and what does it pass down?
2. **The components it renders** — the real ones, not their names. This is where
   assertions come from: which element carries the state, whether a panel
   unmounts or merely hides, whether a control is a `<button>` with
   `aria-expanded` or a div.
3. **The data layer** — the model/endpoint behind the page, and the API entity
   and DTO behind that. It tells you the field names, which fields are optional,
   and what the server will reject. Half of a page's real behaviour is its
   validation.
4. **i18n messages** — any text an assertion touches. Copy the literal string
   from the messages file; do not retype it from the screenshot in your head.
   Check how many locales the app actually serves before writing a regex
   alternation for a locale that does not exist.
5. **Guards and routing** — what redirects an unauthenticated visitor, what a
   role gate hides. These are tests, and they are usually missing.
6. **Existing coverage** — search the coverage document for the route. Some
   behaviours may already be covered from a neighbouring page's section, and a
   duplicate entry is worse than a missing one.

Record what you read. The suite's spec files carry a literal
`Sources read in full:` list, and pass 2 will need it.

---

## 2. Turning code into a test list

Walk the page and ask, for each thing you found:

- **What does the user see when it loads?** The load-and-render check is one
  test, not one per element.
- **What can they change?** Each control that mutates state is at least one
  test. If it persists, the assertion is not "the UI updated" — it is that the
  data changed. Verify through the app's own database probe, not by re-reading
  the DOM you just clicked.
- **What can go wrong?** Empty states, validation rejections, permission
  denials, failed requests. These are the tests most often missing, and the ones
  most likely to be broken in the product.
- **What does the URL do?** Deep links, query parameters, tab state that
  survives a reload.
- **What is conditional?** Anything behind a role, a feature flag, or a subscription
  state is a branch, and each branch is a test.

**One behaviour, one entry.** If a Then has an "and also" in it that belongs to
a different feature, it is two tests.

**Volume is not coverage.** A page with forty assertions worth making does not
need forty tests; it needs the ones whose failure would mean something. Propose
the list and let the user cut it — but propose the risky ones, not the easy ones.

---

## 3. Writing a Given/When/Then that survives review

```md
#### PRC-11 · walks the happy status path with badge and DB assertions per transition — ❌
- **Given** a seeded proceeding in `draft` owned by the logged-in user
- **When** they advance it through each status via the detail-page action menu
- **Then** the badge reflects each new status, and the persisted `status`
  matches after every transition
- _Seed:_ `proceedings.seed.ts` (fixed id `PROCEEDING_1`)
```

- **Given** is state, not navigation. "on the page" is fine; "a seeded X in
  state Y owned by Z" is what makes the test reproducible.
- **When** is the user's action, in their language. Not `page.click(...)`.
- **Then** is the observable claim, and where possible the *persisted* one. A
  test that only asserts the DOM re-rendered proves the component, not the
  feature.
- **`_Seed:_` is required.** `none`, `existing`, or the module and fixed id.
  Deciding this during discovery is what stops pass 2 inventing fixtures.
- Cite the mechanism in parentheses when the behaviour is non-obvious
  (`multiple={false}`) — it tells the next reader why the assertion is what it is.

---

## 4. What not to test

Mark these ⛔ with a reason rather than omitting them:

- Third-party redirect flows the suite cannot complete — external SSO/OAuth,
  payment provider pages.
- Live model calls, real email delivery, external crawlers or sync jobs.
- Anything whose failure would be the third party's, not yours.

And simply do not propose:

- **Framework behaviour.** That a Next.js link navigates is not your test.
- **Pure presentation.** Spacing, colour, copy that no logic depends on.
- **A unit test wearing a browser.** If it needs no page, it belongs in vitest —
  the suite boots a full stack, and every e2e test spends that budget.

---

## 5. Dynamic routes and fixtures

A page like `/proceedings/[id]` needs a concrete instance, and it must be a
**fixed seeded id**, never "whatever the list returns first". The suite keeps
fixed ids in `tests/support/ids.ts` precisely so assertions can name them.

If the page needs data that no seed provides, say so in pass 1's report as a
prerequisite — a new seed module is its own piece of work with its own review,
and discovering it during pass 2 is what turns a test-writing task into a
fixture-building task nobody scoped.

---

## 6. Report shape for pass 1

```
/route — Page name

Proposed (N):
  PRC-12  advances a draft proceeding through the happy status path
  PRC-13  rejects an advance when the user lacks the role
  …
Out of scope (M):
  PRC-14  ⛔ SPID login — external IdP, cannot complete in-suite
Prerequisites:
  seed: no fixture for an archived proceeding — needs a new seed module
  testids: 3 elements have none (listed in pass 2)

Nothing written to specs yet. Say which to keep.
```

Ids reserved, entries written to the coverage document, no `.spec.ts` touched.
