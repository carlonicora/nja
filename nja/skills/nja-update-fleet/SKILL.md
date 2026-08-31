---
name: nja-update-fleet
description: Use when updating dependencies across MULTIPLE nestjs-neo4jsonapi + nextjs-jsonapi monorepos at once — a fleet-wide sweep that produces ONE release of nestjs-neo4jsonapi and ONE of nextjs-jsonapi instead of one per app. Triggers include "update all my projects", "upgrade the fleet", "sweep every repo", "bump deps everywhere", "update the libraries once and roll them out", or any dependency request naming two or more nja repos. For a single repo, use nja-update-dependencies instead.
---

# Fleet dependency sweep

Upgrade every nja monorepo on this machine as one unit: one decision round,
**one release per shared library**, one verification pass per app.

Sweeping repos one at a time derives the libraries' peer floors from whichever
app happened to go first. Every later app that disagrees costs another library
commit and another release, so the number of releases per upgrade is unbounded
and decided by sweep order. This skill inverts that: decide once, validate the
library state against every member **before** it is pushed, release once.

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/` — that variable resolves to
the installed plugin root at runtime, never to a path inside a member.

## Core principle

**The scripts own everything mechanical; the model owns only judgment calls.**
`nja-fleet-survey.sh`, `nja-deps-sweep.sh --ledger` and `nja-fleet-waves.sh`
are deterministic — they discover the roster, compute eligibility, apply one
version set to N repos, and schedule verification. The model owns exactly
four things: which members to include, which majors and conflicts to take,
when to open the one-way door at F4, and how to read a failure pattern.
**Never re-derive a check a script already performed — read its exit code.**

## Phases

| Phase | Action | Gate |
|---|---|---|
| F0 | `${CLAUDE_PLUGIN_ROOT}/scripts/nja-fleet-survey.sh --json`; report changes since the last run; confirm the roster | **ASK** — never infer membership; **STOP** on exit 3 (forked fleet) or 2 (no members) |
| F1 | Union `nja-deps-sweep.sh --dry-run --root <r>` across members + both libraries; reconcile holds; write `ledger.json` | **ASK** on every major, conflict, and cleared hold |
| F2 | Sweep both libraries in the canonical checkouts; derive peer + catalog floors; `pnpm build` | **STOP** if canonical is dirty, not at `origin/master`, or fails to build |
| F3 | Patch the library diff into every member; `--ledger` each member; install → doctor → build | **STOP** on any member failing — loop back to F1/F2; nothing is pushed |
| F4 | Confirm; commit; **push both libraries**; poll CI for the pushed SHA; pull the release commit | **ASK** before pushing; **STOP** and report as an incident on CI failure |
| F5 | Reset submodules to the exact released SHA in every member; `pnpm install`; doctor | **STOP** on doctor failure |
| F6 | `nja-fleet-waves.sh` lint → build → test; then `--stage boot` | fail-fast within a member, never across; **STOP** on exit 4 |
| F7 | Rewrite `DEFERRED MAJOR BUMPS` from the ledger; write the fleet report; print commit sequences | — |

## F0 — the roster is discovered, never remembered

Run the survey and show the user its table. Then confirm the roster through
`AskUserQuestion`. Because that tool caps at four options and the fleet grows,
shape the question to scale — *all eligible* / *all eligible except ones I
name* / *I'll list them* — with the table above it carrying the detail.

`--roots` **replaces** the default scan roots rather than adding to them. Omit
it to scan the parent of the invoking repo plus every persisted root; pass it
to scope a run to exactly what you name.

Eligibility is computed, not declared: clean root, both submodules clean, both
on `master`, both at the fleet-common SHA. A member can be force-included
after failing the gate; that is **always loud and never automatic**, and its
failing criteria are restated in the report.

Not every discovered repo is a fleet member. A template or generator repo can
match the nja detector without consuming the libraries as submodules; it will
surface as ineligible with "submodule not initialised". Report it and move on
— do not initialise submodules to make it fit.

Exit 3 means the fleet has forked — no strict-majority SHA. **Do not pick a
base.** Show the SHA groups and ask which is intended.

Report what changed since the last run (a new repo, a member that vanished)
from the previous state file, but never infer membership from it.

## F1 — one ledger, one decision round

The ledger at `~/.claude/nja-fleet/<date>/ledger.json` is the single source of
truth. Write it **before any manifest is touched**, show it, and never
re-derive it — a fleet run spans npm publishes, and re-deriving per member is
exactly how lockstep breaks silently.

Its shape, per package: `current` (per member), `latest`, `target`, `kind`,
`surfaces`, `seen_in`, `decision` (`take` | `hold`), plus `held_by`, `reason`
and `unblock` for a hold. Only `decision: "take"` entries are applied.

Holds come from `nja-update-dependencies/references/hazards.md` §2 plus every
member's `DEFERRED MAJOR BUMPS` block. Under lockstep a hold anywhere is a
hold everywhere, but record `held_by` so the right repo can be re-tested when
it clears. **Re-test each hold's stated unblock condition once per run, not
once per member** — that is where most of the saving comes from. Unblock
conditions are not interchangeable: a hold whose break is a runtime failure
demands exercising that runtime, not a `peerDependencies` lookup.

A package present in only some members stays scoped to them via `seen_in`.
Nothing is ever *added* to a member that does not have it.

Contradictory deliberate pins across members are a `conflict`. **Refuse to
pick** — see `references/fleet-hazards.md` §5.

`AskUserQuestion` caps at four questions per call, so ask in consecutive calls
of up to four, ordered by blast radius: conflicts, then majors on packages the
libraries declare as peers, then remaining majors, then cleared holds. Print
the full decision table first so batching never hides an item.

## F3 — validate before the door, not after

This is the phase that makes a single release correct rather than lucky.
Install, doctor and build on **every** member, against the un-pushed library
state. Lint, tests and boots are deliberately excluded: F3 may loop, and this
is the cheap-but-decisive gate.

Propagate the library change by patch — `git -C <canonical> diff`, then
`git apply --check` before `git apply` in each member's submodule. A
`--check` failure means a member is not at the expected base, which the
eligibility gate already ruled out: stop, do not force.

## F4 — the one-way door

Read `references/fleet-hazards.md` §1 and §2 before doing anything here.
Push authority is per run and never defaults on. Apps pin the **CI-produced**
release commit, not the local sweep commit. A CI failure is an incident: stop,
report the run URL, touch no app repo.

## F5 — reset the submodules, keep the members' own edits

Discard the F3 patch **inside the two submodule worktrees only** —
`git checkout -- . && git clean -fd` run with `-C <member>/packages/<lib>`,
never at a member root. **The member's own manifest edits are kept**: they are
that app's sweep, already computed from the ledger and already validated. A
reset at a member root would silently discard the whole app-level sweep and is
the single most damaging mistake available in this phase.

Check out the **exact released SHA**, never `master`, so every member pins
identically even if someone pushes to the library mid-run.

## F6 — waves, then a queue

Boots are serial because the members share one Neo4j and one Redis and two of
them claim the same ports. `nja-fleet-waves.sh --stage boot` exit 4 aborts the
queue — see §3. Read a failure through the attribution table in §4 before
reaching for the lazy baseline.

## F7 — the report

Eight required items: (1) roster with exclusions and reasons; (2) ledger
summary split taken / held / conflicts resolved; (3) both library releases —
version, SHA, CI run URL; (4) the per-member verification matrix; (5)
failures with their attribution verdict; (6) the per-member commit sequence,
**not run**; (7) per-member rollback including the note that the releases
stand; (8) the manual test list.

Each member is one flat commit — the two gitlinks, the manifests,
`pnpm-workspace.yaml`, `pnpm-lock.yaml`, `scripts/update.sh`. There is nothing
to commit inside the submodules: they are already at a pushed, released SHA,
so the submodules-first ordering of the single-repo skill does not apply here.

Rewrite each member's `DEFERRED MAJOR BUMPS` block from the one ledger, so
they stop drifting apart. Create `scripts/update.sh` minimally where absent.

## Hands-off

**This skill never commits or pushes an app repo.** It pushes exactly two
things, exactly once, only at F4, and only with per-run permission: the two
libraries' `master`. Everything else is printed for the user to run after
manual testing.

## Failure modes — STOP if you catch yourself doing any of these

| Failure mode | Why it's wrong |
|---|---|
| "I'll sweep wyrdli first and push the libraries, then do the rest." | That is the workflow this skill replaces. The peer floors would again be derived from one app, and every later disagreement costs another release. |
| "I'll fan the library commit I just made out to the members." | Apps must pin the **CI-produced** release commit. A local commit pins every app one commit behind its own release — §2. |
| "CI went red, I'll push a fix and carry on." | A red `master` on a library six apps depend on is an incident. Stop, report the run URL, touch no app repo — §1. |
| "phlow is ineligible, I'll quietly leave it out." | Exclusions are always explicit and always in the report. Silent roster changes are how a repo goes six months unswept. |
| "The fleet has three different SHAs; I'll use the most common." | Exit 3 means forked. Picking a base for the user is exactly what F0 forbids. |
| "bullmq is 6.0.2 here and 6.3.1 there, I'll take the newer." | Both are caret-less deliberate pins. That is a `conflict`: refuse and ask — §5. |
| "The catalog pins react exactly, so I must not bump react." | Caret-less means different things per surface. In `catalog:` it is the norm and moves freely; in a manifest or `overrides:` it is a deliberate pin — §5. |
| "Member 3's boot exited 4, I'll keep going and check it after." | Exit 4 aborts the queue. The next boot would fail on a port that may still be held, and that failure looks identical to a dependency break — §3. |
| "The port is busy, I'll free it first." | That process is not ours. Abort and tell the user. Never free a busy port, never kill by name. |
| "Four members failed, I'll run the lazy baseline on each." | Read the pattern first — §4. All-red means the sweep; bisect the ledger instead of running N baselines. |
| "I'll re-run the dry-run per member, it's the same answer." | It is not: a fleet run spans npm publishes. Apply the ledger — that is what `--ledger` is for. |
| "F5 says discard the patch, so I'll clean the member." | Only the two submodule worktrees. A reset at the member root destroys that app's entire sweep — see F5. |
| "The tree was dirty, I'll work around it." | A dirty member fails the eligibility gate. Never stash on the user's behalf. |
| "All six are green, I'll commit them." | This skill never commits an app repo. |
