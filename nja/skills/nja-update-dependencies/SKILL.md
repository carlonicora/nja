---
name: nja-update-dependencies
description: Use when updating, upgrading, or sweeping npm dependencies in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo — the root, the apps (api/web/…), and the packages (nestjs-neo4jsonapi, nextjs-jsonapi, shared). Triggers include "update the packages", "upgrade dependencies", "dependency sweep", "bump the deps", or a request to check what is outdated. Runs the sweep, verifies with lint/build/dev-boot/test, and leaves everything uncommitted.
---

# Dependency sweep

Update every dependency surface of an nja monorepo — workspace manifests, the pnpm `catalog:` block, and `overrides:` — then verify the result with lint, build, a real `pnpm dev` boot, and tests. The sweep never commits: it leaves the working tree dirty with exactly the diff the user reviews and tests by hand before committing it themselves.

The scripts this skill drives live in `${CLAUDE_PLUGIN_ROOT}/scripts/` — `${CLAUDE_PLUGIN_ROOT}` resolves to the installed plugin's root at runtime, never to a path inside the target monorepo.

## Core principle

**The scripts own everything mechanical; the model owns only judgment calls.** `nja-deps-sweep.sh`, `nja-deps-doctor.sh`, and `nja-dev-boot.sh` are deterministic — they compute the sweep, detect duplicate resolutions, and boot/tear down the dev stack. The model's job is the parts a script cannot decide: which majors to take, how to reconcile a library's peer range against what its consuming app now resolves, and how to read a failure and route it to the right hazard. **Never re-derive a check a script already performed — read its exit code.**

## Phases

| Phase | Action | Gate |
|---|---|---|
| 0 | Preflight: clean tree (root + both submodules); baseline `pnpm lint`, `pnpm build`, `pnpm test`; record submodule branches/SHAs; confirm Neo4j and Redis are up | **STOP** if the tree is dirty or the baseline is red |
| 1 | `${CLAUDE_PLUGIN_ROOT}/scripts/nja-deps-sweep.sh --dry-run`; load holds; re-test each hold's unblock condition | **STOP** on exit 1; exit 3 means an override would sit below a declared floor — resolve before proceeding; **ASK** on every major |
| 2 | `${CLAUDE_PLUGIN_ROOT}/scripts/nja-deps-sweep.sh --apply --reject <holds>`, then ONE `CI=true pnpm install --no-frozen-lockfile` at the root | **STOP** on exit 1; exit 3 means an override would sit below a declared floor — resolve before proceeding |
| 3 | Reconcile submodule `peerDependencies` and catalog floors against what the apps now resolve | — |
| 4 | `${CLAUDE_PLUGIN_ROOT}/scripts/nja-deps-doctor.sh` | **STOP** on any non-zero exit |
| 5 | `pnpm lint` → `pnpm build` → `pnpm test` | **STOP** on error |
| 6 | `${CLAUDE_PLUGIN_ROOT}/scripts/nja-dev-boot.sh` | **STOP** on any non-zero exit; exit 4 means something is still running — report that first |
| 7 | Report; rewrite the `DEFERRED MAJOR BUMPS` block in `scripts/update.sh` | — |

## Phase 0 — why a clean tree, not a tag

With a clean start, `HEAD` *is* the rollback point (`git checkout -- . && git clean -fd` in each repo), the final diff is exactly the sweep and therefore reviewable, and there are no tags to clean up. If the tree is dirty, stop and ask the user to commit or stash. **Never stash on the user's behalf here.**

This phase also confirms Neo4j and Redis are reachable before anything else runs. Phase 6's `nja-dev-boot.sh` cannot boot the stack without them, and a boot failure caused by missing infra looks identical to a boot failure caused by the sweep — checking here, before any dependency is touched, keeps that ambiguity from ever reaching phase 6. Use whatever this repo's dev stack documents for local Neo4j/Redis (its `docker-compose`, its `.env` connection strings) to confirm both are up; if either is down, stop and ask the user to start it rather than guessing at a fix.

## Phase 1 — hold-backs

Two sources: stack-invariant holds from `references/hazards.md` §2, and per-app holds parsed from the `DEFERRED MAJOR BUMPS` comment at the top of `scripts/update.sh`. Where that file is absent (a360ai, and any freshly bootstrapped app), create a minimal one containing only the block and a pointer to this skill. Before proposing to keep a hold, re-test its **stated** unblock condition — each hold in `references/hazards.md` §2 names its own, and they are not interchangeable. `pnpm view <pkg> version` / `pnpm view <pkg> peerDependencies` are illustrations of the *kind* of check some holds need, not a universal recipe: a peer-range lookup only proves what a package declares it's compatible with, and for a hold whose break is a **runtime** failure (eslint's is — `@typescript-eslint`'s `FlatESLint` relocation crashes at runtime on ESLint 10, invisible to `peerDependencies`), the unblock condition demands exercising that runtime directly, exactly as §2's table row for that hold says. Read the hold's own row before deciding what "re-tested" means for it. Present every still-held major and every newly-proposed major through `AskUserQuestion`. Minors and patches proceed without asking.

## Phase 3 — submodule peers

If an app crossed a major on a package that is a `peerDependency` of its library, raise the library's peer range to match and raise the corresponding catalog floor. Both edits stay uncommitted inside the submodule worktree. `check-dep-drift.js` rules 1, 2 and 4 verify the result in phases 4–5.

## Phase 6 — the lazy baseline

The phase-0 baseline deliberately excludes a dev boot; it is slow and most runs never need it. If phase 6 fails, attribute it *then*: say so, `git stash -u` in each repo, reinstall, re-run `${CLAUDE_PLUGIN_ROOT}/scripts/nja-dev-boot.sh` on the pre-sweep state, restore the stash. If the baseline also fails, the breakage is pre-existing and the sweep is not at fault. **This is the only place the skill may stash, it must announce it first, and it must restore.**

If `nja-dev-boot.sh` exits 4, treat that as its own emergency before doing anything else in this phase: exit 4 means teardown could not be verified and a process group may still be running. Report it to the user first — with the `ps -o pid,pgid,args -g <pgid>` inspection line the script printed — before starting the lazy-baseline stash dance or drawing any conclusion about the sweep.

## Phase 7 — the report

Seven required items: (1) what was bumped, grouped by surface and workspace; (2) what was held and why, one line each; (3) doctor findings including report-only WARNs; (4) lint / build / dev-boot / test results; (5) the exact rollback command per repo; (6) the exact submodules-first `git add` / `git commit` sequence, **not run**; (7) the manual test list.

Also rewrite the `DEFERRED MAJOR BUMPS` block at the top of `scripts/update.sh` with the current date, reflecting whatever is still held after this run. Where that file doesn't exist yet (a360ai today, or any freshly bootstrapped app), create it — minimally, containing only the block and a pointer to this skill, per phase 1.

## Hands-off

**This skill never commits, tags, or pushes.** The user commits after manual testing. Print the commands; run none of them.

## Failure modes — STOP if you catch yourself doing any of these

| Failure mode | Why it's wrong |
|---|---|
| "I'll `pkill -f 'next dev'` to clean up." | Forbidden — no `pkill`, `killall`, `pgrep`, or any name/pattern kill, ever. Several nja repos run at once with byte-identical command lines; a name pattern cannot tell them apart and has already destroyed unrelated work on this machine. `nja-dev-boot.sh` tears down by the process group it created — never re-derive that by hand. |
| "The port is busy, I'll free it first." | That process is not ours. Abort and tell the user. Never free a busy port. |
| "`ncu` reported nothing for react, so react is current." | `ncu` only reads manifest ranges — it cannot see `catalog:` — verified. The catalog is a separate surface; the sweep script handles it. See `references/hazards.md` §3. |
| "The readiness poll says not-ready, but the log clearly has the ready line — the boot must be flaky." | Suspect the matcher before the boot. A real incident: `grep -q` under `pipefail` returns a false negative once the log passes the ~16 KB pipe buffer, even though the ready line is plainly present. The readiness regexes (`NJA_READY_API` / `NJA_READY_WEB` / `NJA_READY_WORKER`) are overridable per repo if a repo's own log format needs it — check those before assuming the stack is actually broken. That override only helps once a line has already been routed to the right stream: `nja-dev-boot.sh` first splits api from worker lines by turbo's own `:dev:` / `:dev:worker:` task-prefix, upstream of and not itself controlled by these regexes — a repo whose log lacks that prefix needs a different fix, not a wider `NJA_READY_*` pattern. A worker that is merely slow, not broken, is a separate lever: once api and web are both ready, the worker gets a grace window (`NJA_WORKER_GRACE`, default 10s) before the run degrades to WARN + PASS rather than failing — if a repo's worker is genuinely slower than that, raise `NJA_WORKER_GRACE` rather than treating the WARN as a real failure. |
| "Tests pass, so the upgrade is safe." | Unit tests mock NestJS DI and cannot catch the dual-instance failure. The dev boot is the real gate. |
| "I'll bump it and revert afterwards, like the old script did." | Holds go to `ncu --reject` so they are never bumped. Revert-after is how holds get missed. |
| "The tree was already dirty, I'll work around it." | A dirty tree at phase 0 means stop and ask. Never stash on the user's behalf there — a dirty start makes the final diff unreviewable and rollback destructive. |
| "Build and test passed, I'll commit." | This skill never commits. That is the user's call after manual testing. |
| "SIGKILL is more reliable for teardown." | It skips `dev.sh`'s trap, orphans `.next-dev.lock`, and forces a `.next` wipe on the user's next dev run. TERM first; KILL only as escalation — and only `nja-dev-boot.sh` itself does this, never the model. |
| "The doctor passed, so I can skip the readlink output." | The doctor already did that comparison. Do not re-derive it — read its exit code. |

