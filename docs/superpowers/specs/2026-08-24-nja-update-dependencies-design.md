# Design: `nja-update-dependencies`

A skill for the `nja` plugin that runs a full dependency update sweep across an
nja monorepo — root, apps, and the `packages/*` libraries — verifies it, and
leaves the result **uncommitted** for the user to test and commit themselves.

- **Date:** 2026-08-24
- **Status:** approved design, not yet implemented
- **Plugin version target:** 1.12.0

---

## 1. Problem

Six repos on this machine share one shape: `a360ai`, `dreamer`, `neural-erp`,
`only35`, `phlow`, `wyrdli`. Each has a pnpm workspace with `apps/*` and
`packages/*`, where `packages/nestjs-neo4jsonapi` and `packages/nextjs-jsonapi`
are git submodules that are also published npm libraries.

Updating dependencies across that shape is dangerous in ways that are not
obvious, and the current tooling has four concrete gaps.

### 1.1 The knowledge is a drop-a-file-and-hope artifact

`DEPENDENCY_UPGRADE_GUIDE.md` is 896 lines and byte-identical (`5fdf41d2…`) in
`dreamer`, `neural-erp`, `only35`, and `phlow`. It is **absent** from `a360ai`
and `wyrdli`. `create-carlonicora-app/template` ships it twice (root and
`docs/`). Its own preamble reads *"You are reading this because the user dropped
this file into the project and asked you to upgrade dependencies."* — it only
works if the user remembers it exists and points an agent at it.

It also tangles three kinds of content with different lifetimes: invariant
procedure, hazard knowledge, and per-app mutable state (the hold-back list).

### 1.2 `ncu` cannot see `catalog:` or `overrides:` — verified

Empirically confirmed with ncu 17.1.14: a manifest containing
`"eslint": "catalog:"` and `"zod": "^4.0.0"` produces output listing **only**
`zod`. `catalog:` is not a semver range, so ncu skips it silently — no warning,
no error.

In `dreamer` that means `scripts/update.sh` has never been able to see:

- **21 catalog entries** — `react`, `react-dom`, `@types/react`,
  `@types/react-dom`, `react-hook-form`, `next`, `zod`, `eslint`,
  `@typescript-eslint/eslint-plugin`, `@typescript-eslint/parser`,
  `eslint-config-prettier`, `eslint-plugin-prettier`, `ts-node`, `vitest`,
  `@vitest/coverage-v8`, and all six `@nestjs/*` peer floors
- **16 concrete `overrides:` ranges** in `pnpm-workspace.yaml` (of 29 entries;
  the other 13 are `catalog:` references, governed by the line above) —
  `typescript`, `class-validator`, `class-transformer`, `rxjs`,
  `reflect-metadata`, `sharp`, `bullmq`, `yjs`, `validator`, `jotai`,
  `openai`, and five `@floating-ui/*`

That is 37 packages, including React, Next.js and the entire NestJS core,
structurally outside every sweep run to date. They have been
hand-maintained.

### 1.3 The mechanical checks are expensive prose

Guide §7.2 and §4.5 are ~12 shell commands (`ls node_modules/.pnpm | grep …`,
`readlink` pair comparisons) whose output a model must read and compare by eye,
every run. They are 100% deterministic and belong in a script — the plugin
already established this pattern with `scripts/nja-lint.sh`.

### 1.4 There is a hazard nothing can currently detect

`dreamer`'s `packages/nestjs-neo4jsonapi` submodule is 26 commits past its last
tag (`pre-contextualiser-rework-26-g9a6a2e7`) while both its `package.json` and
`versions.production.json` say `3.2.2`. The production Docker build substitutes
`workspace:*` → npm `3.2.2` (`scripts/apply-production-versions.js`), so the
image ships code that is **not** what the workspace builds and tests.

Rule 5 of `scripts/check-dep-drift.js` compares `versions.production.json`
against the workspace `package.json` version — both say `3.2.2`, so it passes.
It is structurally unable to see this class of drift.

Relatedly: `phlow` is stranded on core libs `2.0.0` while the other five are on
`3.2.2`/`3.3.9`, and `dreamer`'s catalog comment still reads *"nestjs-neo4jsonapi
2.0.0 peer floors"* against an actual dependency of `3.2.2`.

---

## 2. Goals

1. One maintained copy of the upgrade knowledge, invoked automatically by
   relevance rather than by the user remembering a filename.
2. Sweep **all three** dependency surfaces: workspace manifests, `catalog:`,
   and concrete `overrides:`.
3. Make the mechanical verification deterministic and cheap.
4. Verify the result with `pnpm lint`, `pnpm build`, `pnpm dev` (boot check),
   `pnpm test`.
5. Leave the working tree **uncommitted, untagged, unpushed**.
6. Never kill a process by name pattern.

## 3. Non-goals

- **No commits, tags, or pushes.** The skill prints the commands; the user runs
  them after manual testing.
- **No publishing.** The library repos' own release process is out of scope.
- **No core-library version bumps.** Moving an app from
  `@carlonicora/nestjs-neo4jsonapi` 3.2.2 to a newer release is a different
  task. The doctor *reports* related drift (§6.4) but takes no action.
- **No changes to the six app repos or to `create-carlonicora-app`.** The
  duplicated `DEPENDENCY_UPGRADE_GUIDE.md` files stay where they are. (This was
  approach 3 and was explicitly not chosen.)
- **No hooks.** This skill is user-invoked, not ambient.

---

## 4. Deliverables

```
nja/skills/nja-update-dependencies/
  SKILL.md
  references/hazards.md
nja/scripts/
  nja-deps-sweep.sh
  nja-deps-doctor.sh
  nja-dev-boot.sh
```

Plus registration:

- `nja/.claude-plugin/plugin.json` → version `1.12.0`
- `.claude-plugin/marketplace.json` → version `1.12.0` in **both** the top-level
  block and the `plugins[0]` block
- `README.md` → one row in the Skills table

All three scripts:

- `#!/usr/bin/env bash`, `set -uo pipefail` (matching `nja-lint.sh`)
- source `nja/scripts/nja-detect.sh` and exit 0 with a notice when
  `nja_is_project` is false
- are `chmod +x`
- depend only on: `bash`, `git`, `pnpm`, `node`, `ncu`, `lsof`, `awk`, `sed`,
  `grep`. **No `jq`** — the existing repo scripts avoid external deps on
  purpose, and `node -e` is available for JSON.

---

## 5. `nja-deps-sweep.sh`

### 5.1 CLI

```
nja-deps-sweep.sh [--dry-run | --apply] [--root <path>] [--reject <pkg,pkg,…>]
```

- `--dry-run` (default): report only, write nothing
- `--apply`: write `package.json` files and `pnpm-workspace.yaml`
- `--root`: repo root; defaults to `git rev-parse --show-toplevel`
- `--reject`: comma-separated hold-back list, passed to `ncu --reject` and
  applied to catalog/override resolution

### 5.2 Surface 1 — workspace manifests

Discover from `pnpm-workspace.yaml`'s `packages:` globs rather than a hardcoded
path list. Only the `<dir>/*` form needs support (that is all six repos use);
reuse the parsing approach already proven in
`scripts/sync-production-versions.js`. This makes `a360ai` (three apps:
`api`, `corpus`, `web`; no `scripts/update.sh` at all) work with no repo change.

Include the repo root manifest, every discovered workspace package, and both
submodules.

Per manifest run `ncu` (dry-run) or `ncu -u` (apply), with
`--reject <holds>` so held packages are **never bumped** — replacing the
guide's §4.4 "bump everything then hand-revert" step.

**Do not run `pnpm install` per directory.** The current `scripts/update.sh`
does, and that is the sole source of the
`ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY` noise guide §4.3 tells the reader
to ignore. One root install happens in phase 2 instead.

### 5.3 Surface 2 — `catalog:`

Parse the `catalog:` block of `pnpm-workspace.yaml` (flat `key: value` pairs;
the parser in `scripts/check-dep-drift.js` handles the exact quoting used and
is the reference implementation).

For each entry not in the reject list, resolve the latest version with
`pnpm view <pkg> version`. Report `current → latest`, preserving the range
operator already in use (`^9.39.5` → `^9.40.0`; a pinned `19.2.8` stays pinned
and becomes `19.3.0`).

On `--apply`, rewrite **only the version token** on that line — comments,
ordering, quoting, and blank lines in `pnpm-workspace.yaml` must be preserved
byte-for-byte otherwise. The file carries substantial load-bearing commentary
(the `verifyDepsBeforeRun`, `autoInstallPeers`, and per-override rationale
blocks) and losing it would be a real regression.

### 5.4 Surface 3 — `overrides:`

Same parse-resolve-rewrite treatment, with one extra rule.

An override **replaces** a declared range rather than intersecting with it, so
an override below a manifest's floor silently resolves under that floor with no
peer warning — this is how `@nestjs/*` sat at 11.1.24 while every manifest
declared `^11.1.28`. Before writing any override the script must confirm the new
value is `>=` every declared range for that package across all manifests, and
refuse (non-zero exit, named package) if not.

Overrides whose value is `'catalog:'` are skipped here — they are governed by
§5.3.

### 5.5 Output

A table grouped by surface and workspace, marking each row `patch` / `minor` /
`major` / `HELD`. Majors are called out separately so the skill can gate on
them.

### 5.6 Exit codes

| Code | Meaning |
|---|---|
| 0 | success (dry-run reported, or apply completed) |
| 1 | usage / environment error (`ncu` missing, no `pnpm-workspace.yaml`) |
| 3 | refused to write an override that would lower a declared floor (§5.4) |

---

## 6. `nja-deps-doctor.sh`

### 6.1 CLI

```
nja-deps-doctor.sh [--root <path>]
```

Run after any install. Everything below is mechanical and produces one exit
code.

### 6.2 Single-resolution check

For each critical peer, `ls node_modules/.pnpm | grep -E '^<escaped>@'` must
yield exactly one version. Critical peers:

```
@nestjs/common  @nestjs/core  react  react-dom  next  next-intl
class-validator  class-transformer  zod
```

Two versions of any of these is the signature of the dual-instance
peer-fingerprint failure documented in `references/hazards.md`.

### 6.3 `readlink` pair equality

For each (workspace, critical peer) pair where the workspace actually has that
link, compare `readlink <workspace>/node_modules/<peer>` across workspaces. All
non-empty targets for a given peer must be identical. The canonical pairs from
guide §7.2 — `apps/web` vs `packages/nextjs-jsonapi` for `react`, `apps/api` vs
`packages/nestjs-neo4jsonapi` for `@nestjs/common` — fall out of this
generalisation, and it also covers `a360ai`'s third app for free.

### 6.4 Delegated and report-only checks

- Run `node scripts/check-dep-drift.js` if present; surface its output verbatim
  and propagate failure.
- Run `node scripts/sync-production-versions.js --check` if present; same.
- **Report-only — published-version drift.** For each submodule: compare
  `git -C <submodule> describe --tags` against the submodule's
  `package.json` version and against `versions.production.json`. If the
  submodule HEAD is not exactly at the tag matching its declared version, emit a
  WARN naming the gap (this is §1.4). Report-only: it never fails the run,
  because resolving it means publishing, which is out of scope.

### 6.5 Exit codes

| Code | Meaning |
|---|---|
| 0 | all checks pass (WARNs allowed) |
| 2 | a duplicate resolution or a `readlink` mismatch was found |
| 1 | a delegated script failed, or environment error |

The remedy for exit 2 is an exact-version override in `pnpm-workspace.yaml`,
reinstall, re-run. This is documented in `references/hazards.md`, not in the
script.

---

## 7. `nja-dev-boot.sh`

The safety-critical component. `pnpm dev` in these repos runs
`scripts/dev.sh` → `turbo run dev dev:worker`, starting **three** persistent
processes:

| Process | Command | Port |
|---|---|---|
| api | `nodemon` → `ts-node src/main.ts --mode=api` | `API_PORT` (3950) |
| worker | `nodemon` → `ts-node src/main.ts --mode=worker` | **none** |
| web | `next dev` | `PORT` (3951) |

### 7.1 Why process groups, not ports and not names

The worker listens on nothing, so a port-based kill cannot reach it. Killing by
name (`pkill -f "next dev"`, `pkill -f node`, `killall node`) is **forbidden** —
the user runs several of these repos concurrently with byte-identical command
lines, a name pattern cannot distinguish them, and doing so has already
destroyed unrelated work once. This rule lives in the user's global
`~/.claude/CLAUDE.md`.

`setsid` does not exist on macOS. Verified working alternative: enable job
control (`set -m`) and background a subshell — the job becomes its own process
group leader with `PGID == PID`, and `kill -TERM -- -$PGID` reaps the whole
tree. Confirmed by direct test on this machine (Darwin 25.5.0).

### 7.2 Procedure

```
1. Resolve API_PORT and PORT from .env, else .env.example, else 3950/3951.
2. If either port is already LISTENing, ABORT (exit 1).
   Never kill a process we did not start.
3. set -m; ( ${NJA_DEV_CMD:-pnpm dev} ) >"$LOG" 2>&1 &   PGID=$!
4. Poll every 2s up to --timeout (default 180s) for ALL of:
     - TCP LISTEN on API_PORT
     - TCP LISTEN on PORT
     - api ready line in $LOG
     - web ready line in $LOG   ("Ready in", Next.js)
     - worker ready line in $LOG
5. Scan $LOG throughout for fatal patterns:
     UnknownDependenciesException | Cannot find module |
     UnhandledPromiseRejection | ERR_MODULE_NOT_FOUND | ERR_PNPM_
   Any hit ends the wait immediately as a failure.
6. Teardown ALWAYS (trap EXIT INT TERM):
     kill -TERM -- -$PGID ; wait up to 20s
     if group survives: kill -KILL -- -$PGID   (still the group we started)
7. Verify: group gone, both ports free, apps/web/.next-dev.lock removed.
8. Print verdict + last 60 log lines on failure; keep $LOG and print its path.
```

**SIGTERM before SIGKILL is load-bearing.** `scripts/dev.sh` sets
`trap cleanup EXIT INT TERM` to remove `apps/web/.next-dev.lock`. A SIGKILL
skips the trap, the lock survives, and the *next* `pnpm dev` sees it as an
unclean exit and wipes `apps/web/.next` — a slow, confusing cold rebuild caused
by our teardown.

### 7.3 Readiness patterns

The api and worker ready lines are NestJS bootstrap output and may vary per app.
The script keeps them in one clearly-marked, overridable block near the top
(`NJA_READY_API`, `NJA_READY_WEB`, `NJA_READY_WORKER` environment overrides).
If the worker pattern does not match within the timeout but api and web are
ready and no fatal pattern appeared, the run is reported as **PASS with a
WARN** naming the unmatched signal, rather than a failure — an unmatched log
regex must not masquerade as a boot error.

### 7.4 Infrastructure precondition

`pnpm dev` needs Neo4j and Redis. Before starting, check that `REDIS_PORT`
(6379) is reachable; if not, ABORT with a message telling the user to start the
infra, rather than reporting a dependency-caused boot failure. The skill also
records this in phase 0.

### 7.5 Testability

`NJA_DEV_CMD` overrides the launched command so teardown can be tested against
a fast fake (a script spawning two children that ignore SIGINT) without a
three-minute real boot. This is the primary test seam for the whole script.

### 7.6 Exit codes

| Code | Meaning |
|---|---|
| 0 | booted cleanly and tore down cleanly (WARNs allowed) |
| 1 | precondition failure (port occupied, infra down, usage) |
| 2 | boot failed (timeout or fatal log pattern) |
| 4 | boot succeeded but teardown could not be verified — ports still bound or group alive after SIGKILL. **Must be surfaced loudly**; it means something is still running. |

---

## 8. `SKILL.md`

### 8.1 Frontmatter

```yaml
name: nja-update-dependencies
description: Use when updating, upgrading, or sweeping npm dependencies in a
  nestjs-neo4jsonapi + nextjs-jsonapi monorepo — the root, the apps
  (api/web/…), and the packages (nestjs-neo4jsonapi, nextjs-jsonapi, shared).
  Triggers include "update the packages", "upgrade dependencies", "dependency
  sweep", "bump the deps", or a request to check what is outdated. Runs the
  sweep, verifies with lint/build/dev-boot/test, and leaves everything
  uncommitted.
```

### 8.2 Phase table

| Phase | Action | Gate |
|---|---|---|
| 0 | Preflight: clean tree (root + both submodules); baseline `pnpm lint`, `pnpm build`, `pnpm test`; record submodule branches/SHAs; note infra availability | **STOP** if tree dirty or baseline red |
| 1 | `nja-deps-sweep.sh --dry-run`; load holds; re-test each hold's unblock condition | **ASK** on every major |
| 2 | `nja-deps-sweep.sh --apply --reject <holds>`; then one `CI=true pnpm install --no-frozen-lockfile` at root | — |
| 3 | Reconcile submodule `peerDependencies` and catalog floors against what the apps now resolve | — |
| 4 | `nja-deps-doctor.sh` | **STOP** on any non-zero exit |
| 5 | `pnpm lint` → `pnpm build` → `pnpm test` | **STOP** on error |
| 6 | `nja-dev-boot.sh` | **STOP** on any non-zero exit; exit 4 additionally means something is still running and must be reported first |
| 7 | Report; rewrite the `DEFERRED MAJOR BUMPS` block in `scripts/update.sh` | — |

### 8.3 Phase 0 — why clean-tree replaces tagging

Guide §2 mandates `pre-deps-update-<date>` tags in all three repos. With a
clean tree at entry, `HEAD` already *is* the rollback point
(`git checkout -- . && git clean -fd` in each repo), the final diff is exactly
the sweep and therefore reviewable, and no tags need cleaning up afterwards.
Requiring a clean start is the cheaper and stronger guarantee. If the tree is
dirty the skill stops and asks the user to commit or stash — it must not stash
on the user's behalf.

### 8.4 Phase 1 — hold-backs

Two sources, merged:

- **Stack-invariant holds** live in `references/hazards.md` with the failure
  mode for each: `eslint`, `typescript`, `class-validator`,
  `class-transformer`, `rxjs`, `reflect-metadata`, `react`, `react-dom`.
- **Per-app holds** stay where they already are: the `DEFERRED MAJOR BUMPS`
  comment block at the top of `scripts/update.sh`. The skill parses it on entry
  and rewrites it in phase 7 with the current date. Where the file does not
  exist (`a360ai`, and any freshly bootstrapped app) the skill creates a minimal
  `scripts/update.sh` containing only the block and a pointer to this skill.

Before proposing to keep any hold, re-test its stated unblock condition
(`pnpm view <pkg> version`, `pnpm view <pkg> peerDependencies`) so stale holds
surface instead of calcifying. Present each still-held major and each
newly-proposed major through `AskUserQuestion`. Minors and patches proceed
without asking.

### 8.5 Phase 3 — submodule peer reconciliation

If an app crossed a major on a package that is a `peerDependency` of its
library (e.g. `@fastify/multipart ^10 → ^11`), raise the library's peer range to
match and raise the corresponding catalog floor. Both edits stay uncommitted
inside the submodule worktree. `check-dep-drift.js` rules 1, 2 and 4 verify the
result in phase 4/5.

### 8.6 Phase 6 — lazy baseline

The baseline in phase 0 deliberately excludes a dev boot: it is slow, and most
runs never need it. If phase 6 fails, *then* attribute it — stash the sweep
(`git stash -u` in each repo), reinstall, re-run `nja-dev-boot.sh` on the
pre-sweep state, restore the stash. If the baseline also fails, the breakage is
pre-existing and the sweep is not at fault. This is the one place the skill may
stash, it must say so first, and it must restore.

### 8.7 Phase 7 — end state

Nothing committed, tagged, or pushed. The report contains:

1. What was bumped, grouped by surface (manifests / catalog / overrides) and
   workspace
2. What was held and why — one line each
3. Doctor findings, including report-only WARNs (§6.4)
4. Verification results: lint, build, dev boot, test
5. The exact rollback command per repo
6. The exact submodules-first `git add` / `git commit` sequence, **not run**
7. The manual test list for the user

### 8.8 Failure-mode table

Required in `SKILL.md`, in the style of `nja-verify`:

| Failure mode | Why it's wrong |
|---|---|
| "I'll `pkill -f "next dev"` to clean up." | Forbidden. Byte-identical command lines across the user's repos; a name pattern cannot tell them apart and has already destroyed unrelated work. Only the captured PGID. |
| "The port is busy, I'll free it first." | That process is not ours. Abort and tell the user. |
| "`ncu` reported nothing for react, so react is current." | `ncu` cannot see `catalog:`. Verified. The catalog is a separate surface. |
| "Tests pass, so the upgrade is safe." | Unit tests mock NestJS DI and will not catch the dual-instance failure. The dev boot is the real gate. |
| "I'll bump it and revert after, like the old script." | Holds are passed to `ncu --reject` so they are never bumped. Revert-after is how holds get missed. |
| "The tree was already dirty, I'll work around it." | Stop and ask. A dirty start makes the final diff unreviewable and rollback destructive. |
| "Build and test passed, I'll commit." | The skill never commits. That is the user's call after manual testing. |
| "SIGKILL is more reliable for teardown." | It skips `dev.sh`'s trap, orphans `.next-dev.lock`, and forces a `.next` wipe on the user's next dev run. TERM first, KILL only as escalation. |

---

## 9. `references/hazards.md`

Distilled from the 896-line guide — roughly 200–250 lines, keeping the failure
modes and dropping the procedure (which is now the phase table) and the
commit/push material (now out of scope).

Sections:

1. **The dual-instance peer-fingerprint failure** — symptoms (backend
   `UnknownDependenciesException` with passing tests; frontend `UseFormReturn`
   type mismatches at build), why it happens, detection (now
   `nja-deps-doctor.sh`), fix (exact-version override → reinstall).
2. **Stack-invariant hold-backs** — per package: what breaks, and the condition
   that unblocks it.
3. **The three surfaces** — why `catalog:` and `overrides:` are invisible to
   `ncu`, and why an override must never sit below a declared floor.
4. **pnpm 11** — `pnpm.*` in `package.json` is no longer read; `allowBuilds`
   replaced `onlyBuiltDependencies`; the placeholder stub written on first
   install. (`phlow` is still on pnpm 10.28.2; the other five are on 11.18.0.)
5. **`.pnpmfile.cjs`** — the `supports-color` optional-peer strip and why
   removing it re-creates duplicate `@nestjs/core`.
6. **Gotchas table** — symptom → cause → section, carried over from guide §12.

Every entry keeps its concrete failure story. The guide's value is that each
rule is paired with the incident that produced it; a rule list without those
stories invites rationalisation.

---

## 10. Testing

Shell scripts, so tests are shell-level and run against the six real repos in
read-only modes.

### 10.1 `nja-deps-sweep.sh`

- `--dry-run` against all six repos: discovers the right workspace set —
  notably `a360ai`'s three apps (`api`, `corpus`, `web`) with no
  `scripts/update.sh` present — and reports catalog and override rows.
- After every dry run, `git status --short` must be **empty** in the repo and in
  both submodules. Nothing is written in dry-run mode.
- `--apply` against a scratch copy of `dreamer` (`git clone --local` or a
  worktree): confirm `pnpm-workspace.yaml` keeps every comment, blank line and
  quoting style, with only version tokens changed. A `diff` of the file must
  show version-only hunks.
- Reject list honoured: with `--reject eslint,typescript`, neither appears in
  the applied diff, in manifests or in the catalog.
- Floor rule: a fixture where an override sits below a manifest's declared range
  must exit 3 and name the package.
- Non-nja directory: exits 0, writes nothing.

### 10.2 `nja-deps-doctor.sh`

- Against `dreamer` as-is: exits 0, and emits the published-version-drift WARN
  for `nestjs-neo4jsonapi` (§1.4) — this is a known-true positive available
  today.
- Synthetic duplicate: in a scratch copy, force a second `react` resolution and
  confirm exit 2 with both versions named.
- With `scripts/check-dep-drift.js` absent, the run still completes.

### 10.3 `nja-dev-boot.sh`

- **Teardown (primary test, via `NJA_DEV_CMD`)**: a fake dev command spawning
  two children, one of which ignores SIGINT. Assert: the group is created,
  SIGTERM reaches every member, the group is gone, both ports are free, and no
  process outside the group was signalled. Run a second, unrelated long-lived
  `node` process alongside it and assert it is **still alive** afterwards — this
  is the regression test for the name-pattern-kill rule.
- **Precondition**: with a port pre-bound by an unrelated process, exit 1 and
  leave that process running.
- **Timeout**: fake command that never becomes ready → exit 2 within the
  timeout, teardown still runs.
- **Fatal pattern**: fake command printing `UnknownDependenciesException` → exit
  2 immediately, teardown still runs.
- **Lock file**: after a real run against `dreamer`, `apps/web/.next-dev.lock`
  is absent.
- **One real run** against `dreamer` end to end.

### 10.4 Skill-level

An eval under `nja/skills/nja-update-dependencies/evals/`, following the
existing `nja-architecture/evals/` format, covering the highest-risk judgment
calls: dirty tree at entry (must stop), a major on a held package (must ask),
doctor exit 2 (must stop and not proceed to lint), and boot failure (must run
the lazy baseline before blaming the sweep).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| `pnpm-workspace.yaml` rewriting damages the load-bearing comments | Version-token-only substitution; diff assertion in the test suite (§10.1) |
| Ready-line regexes drift per app or per NestJS version | Overridable via env; unmatched worker signal degrades to PASS+WARN, never a false failure (§7.3) |
| A boot check leaves something running | Exit code 4 exists solely for this and must be surfaced loudly (§7.6) |
| `ncu` gains catalog support later and the surfaces double up | §5.3 resolves catalog entries directly via `pnpm view`, independent of `ncu`; if `ncu` later handles them, the sweep's catalog pass becomes redundant but not wrong |
| Six repos drift apart in shape | Everything is discovered from `pnpm-workspace.yaml`, not hardcoded |
| The 896-line guides now disagree with `hazards.md` | Accepted for now — approach 3 (deleting them) was explicitly not chosen. `hazards.md` states that it supersedes the repo copy |
