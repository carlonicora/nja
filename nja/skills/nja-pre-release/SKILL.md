---
name: nja-pre-release
description: Use before releasing or handing back an nja monorepo — drive `pnpm lint`, `pnpm build` and `pnpm test` to green, fixing what fails, then run the repo's full-stack e2e suite if it has one and propose fixes for anything it reports. Triggers include "get it green", "pre-release check", "run the gates", "make lint/build/test pass", "ready to release?", or a request to run e2e before shipping.
---

# Pre-release gate

Drive one repo's three fast gates to green, then run its e2e suite if it has a
real one. **The fast gates get fixed; e2e gets diagnosed.** That asymmetry is
the whole design: a lint or type failure has one right answer and you can prove
it in seconds, while an e2e failure is usually a product question wearing a
stack trace.

Scope is **one repo — the one you are in**. Never touch a sibling repo; several
run simultaneously on this machine.

## Workflow

```
preflight → lint → build → test → (loop until green) → e2e → report
```

### 1. preflight

- **Is a dev server running?** `lsof -tiTCP:<api-port> -sTCP:LISTEN` and the web
  port, read from the repo's `.env`. If one is up, **stop and ask** before going
  further — see the `pnpm build` hazard below. Do not kill it yourself.
- Note whether the tree is dirty. You are about to edit files; the user needs to
  be able to tell your changes from theirs. If it is dirty, say so in the report.
- Record the repo's ports so every later `lsof` is scoped to this repo.

### 2–4. the fast gates

Run in this order, stopping at the first red one:

```bash
pnpm lint
pnpm build
pnpm test        # turbo run test --concurrency=1
```

`pnpm lint` ends with `tsc -p tsconfig.spec.json` in every NestJS app, so a type
error in a spec fails lint, not test. Fix it in the spec. `as any` and
`@ts-ignore` are not fixes.

**Every re-run of the tests is `turbo run test --force --concurrency=1`.**
Without `--force`, turbo replays the cached result of an unchanged package and
the "re-run" proves nothing. The suites shuffle files and the tests inside
them, and vitest prints the seed at the top of each run. Write the seed down
for every run you report.

On a failure: diagnose it, fix it, then **restart from `pnpm lint`** — not from
the gate that failed. A fix for a type error routinely trips lint, and a fix for
a test routinely trips the build. Only a clean run of all three *in one pass*
counts as green.

**Attempt cap: 3 per distinct failure signature.** On the 4th attempt, or the
moment the same signature reappears *after* you thought you fixed it, stop and
report. Repeating a fix that already failed is the failure mode this cap exists
to prevent — you are not converging, and the user can see in one glance what you
cannot.

Read `references/failure-playbook.md` before diagnosing anything. It maps the
failures this stack actually produces to their causes, including several that
look like your fault and are not.

### 5. e2e

**Run it only if `scripts/e2e.sh` exists and is executable.** That is the
detection — not the presence of a `test:e2e` script.

> `pnpm test:e2e` is not the signal. In a repo not yet moved to the sharded
> runner it can still be `vitest run --passWithNoTests`, which passes without
> running anything and reports a green e2e that tested nothing.
>
> `pnpm e2e:dash` (a360ai) is **not** a runner either. It is an interactive
> dashboard that serves a page and waits for a human to click Run; it spawns
> `scripts/e2e.sh` underneath. Call `scripts/e2e.sh` directly.

Detect, do not assume — repos gain e2e suites.

```bash
./scripts/e2e.sh                  # full suite: 3 shards, 3 stacks in parallel
./scripts/e2e.sh <spec or args>   # scoped run: ONE stack, args go to Playwright
E2E_SHARDS=<n> ./scripts/e2e.sh   # n stacks; E2E_SHARDS=1 is one stack, full suite
```

**It is slow and it is supposed to be.** It builds the api once into
`apps/api/dist-e2e` and the web once per shard, recreates each shard's
databases, starts each shard's worker alone and waits for its migrations, then
starts api and web and runs one Playwright shard per stack. In a360ai that is
3 to 5 minutes before the first test, then hundreds of tests. Let it finish.
Do not add your own timeout that fires before it can possibly pass, and do not
read the build or boot phase as a hang.

Every log line carries its shard and process: `[s<k>:api]`, `[s<k>:worker]`,
`[s<k>:web]`, `[s<k>:pw]` (and `[s<k>:corpus]` in a360ai). At the end the
runner merges the shards' blob reports into `apps/web/playwright-report` and
prints each shard's exit code, duration and peak memory, plus the boot and
total wall time. It exits non-zero when any shard failed, or when the network
log shows a connection to a host outside loopback and `E2E_ALLOWED_HOSTS`.

**The runner is safe beside the dev stack.** It builds into `dist-e2e` and
`.next-e2e*`, never into the dev `dist`, `dist-worker` or `.next`. It uses only
the ports from `E2E_PORT_BASE` (shard k at base + 10k), its own databases and
its own queue prefixes. It frees a port only when the listener belongs to this
checkout, aborts with the pid when it does not, and tears down by recorded PID.
A running dev server does not block it; the preflight stop is about
`pnpm build`.

**Never fix an e2e failure in this skill.** Diagnose and propose. An e2e test
asserts product behaviour, and "make the test pass" is frequently the wrong
repair — the test may be right and the app wrong, or the fixture may have
drifted from a schema change nobody meant to make.

### 6. report

Required, in this order:

1. **Gate results** — lint / build / test, and how many passes it took.
2. **What you changed** — every file, with one clause each on why. If the tree
   was already dirty, say which changes are yours.
3. **What you could not fix** — the failure, what you tried, and why you stopped.
4. **e2e** — skipped (with the reason) or run, with pass/fail counts.
5. **Proposed e2e fixes** — one per failure or per group of failures sharing a
   cause. Each needs: the failing test, the actual error, your reading of the
   cause, and the specific change you would make. Group repeats: "14 tests in
   `authenticated/` fail on the same missing seed" is one proposal, not 14.

## Hazards — each of these has cost someone real time

**`pnpm build` while a dev server is running clobbers `apps/web/.next`.** `next
build` and `next dev` share that directory; after a production build the running
dev server 404s every route. This is why preflight checks the ports. If you hit
it, the fix is to delete `apps/web/.next` and restart dev — the tell is
`required-server-files.json` sitting in `.next`, which only a production build
writes.

**A test that fails in the suite and passes alone is a real defect.** The
suites shuffle file and test order, and the `fast` project shares one module
registry across files, so a leak between files shows up as a failure in the
suite. Check the file against the isolation rule first: a spec whose source
contains `vi.mock(`, `vi.doMock(`, `vi.stubGlobal(`, `vi.resetModules(` or
`modelRegistry.register(` must land in the `isolated` project, and
`vitest.isolation.ts` computes that list from the source. Then reproduce with
the same seed: `vitest run --sequence.seed=<n>`, or
`turbo run test --force --concurrency=1` so turbo does not replay a cached run.
Fix the cause (a direct `process.env` or `global.*` write, a mock set once in
`beforeAll`, a real wait instead of fake timers). Retries, longer timeouts and
`test.skip` are not fixes.

**Never kill by name pattern.** `pkill -f`, `killall node` and friends match
every project on this machine, not just this repo. `scripts/e2e.sh` owns its own
ports and traps its own cleanup — let it. If you must free a port, free only
this repo's, by PID, after confirming with `lsof -a -p <pid> -d cwd` that the
process is actually inside this repo.

**Use `lsof -tiTCP:<port>`, not `lsof -ti :<port>`.** The bare form also matches
UDP holders that `-sTCP:LISTEN` does not filter out, so an unrelated daemon can
make a free port look busy.

**A config error aborts a typecheck.** `tsc` reports config-level errors
(TS5102/TS5090/TS5101) *instead of* checking files, so the count you get back is
just those config errors. Confirm with `tsc --showConfig` before trusting any
error count you are about to act on.

## Red flags — stop if you catch yourself here

| Thought | Reality |
|---|---|
| "Same fix again, it'll work this time." | It won't. That is the attempt cap firing. Report. |
| "Lint passed earlier, I'll skip it after this fix." | A fix routinely breaks an earlier gate. Restart from lint. |
| "`pnpm test:e2e` exists, so I'll run that." | In most of these repos it passes without running anything. Detect `scripts/e2e.sh`. |
| "e2e has been booting for four minutes, it's stuck." | That is its normal boot. Let it finish. |
| "I'll just make the e2e assertion match what the app does." | You are erasing the bug the test found. Propose, don't fix. |
| "It passed alone, so it's a flake." | It is a leak or an order dependency. Check the isolation rule, re-run with the same seed, fix the cause. |
| "I'll re-run `pnpm test` to confirm." | Turbo replays the cache. `turbo run test --force --concurrency=1`, and record the seed. |
| "The dev server is up, so e2e must wait." | The runner builds into `dist-e2e` and uses its own ports. Only `pnpm build` clobbers the dev stack. |
| "The dev server is in the way, I'll kill it." | Stop and ask. It may be the user's, mid-task. |
| "I fixed everything; I'll commit so it's tidy." | This skill never commits. The user does. |

## Hands-off

**Never commit, stage, push, or stash.** Leave the working tree dirty with
exactly the fixes you made, so the user can review them. Print the commands if
they are useful; run none of them.
