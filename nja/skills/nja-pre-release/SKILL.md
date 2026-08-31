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
pnpm test
```

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

> `pnpm test:e2e` exists in every nja repo and in most of them is
> `vitest run --passWithNoTests` — it passes without running anything and
> reports a green e2e that tested nothing. Do not use it as the signal.
>
> `pnpm e2e:dash` (a360ai) is **not** a runner either. It is an interactive
> dashboard that serves a page and waits for a human to click Run; it spawns
> `scripts/e2e.sh` underneath. Call `scripts/e2e.sh` directly.

As of 2026-08-31: a360ai and neural-erp have one; wyrdli, only35 and dreamer do
not. Detect, do not assume — repos gain e2e suites.

```bash
./scripts/e2e.sh          # streams its own [api] [worker] [web] logs
```

**It is slow and it is supposed to be.** It recreates a test database, boots the
full stack on its own dedicated ports, waits for migrations, then runs
Playwright — 3–5 minutes before the first test in a360ai, then hundreds of
tests. Let it finish. Do not add your own timeout that fires before it can
possibly pass, and do not interpret the boot phase as a hang.

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

**A test failure under full-suite load may not be real.** These suites flake
under contention. Before you treat a red test as a defect, re-run that package
alone. A failure that passes in isolation is a flake, not a fix target — say so
in the report rather than "fixing" it.

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
| "One test fails, I'll fix the test." | Re-run it in isolation first. It may be a flake. |
| "The dev server is in the way, I'll kill it." | Stop and ask. It may be the user's, mid-task. |
| "I fixed everything; I'll commit so it's tidy." | This skill never commits. The user does. |

## Hands-off

**Never commit, stage, push, or stash.** Leave the working tree dirty with
exactly the fixes you made, so the user can review them. Print the commands if
they are useful; run none of them.
