# Design: `nja-update-fleet`

A skill for the `nja` plugin that upgrades **every** nja monorepo on the machine
in one run: one set of version decisions, **one release of each shared library**,
and one verification pass per app. It replaces the manual choreography of
"upgrade one app, push the two libraries, then upgrade the rest".

- **Date:** 2026-08-28
- **Status:** approved design, not yet implemented
- **Plugin version target:** 1.13.0
- **Relationship to `nja-update-dependencies`:** additive. That skill is
  unchanged and remains the single-repo path.

---

## 1. Problem

### 1.1 The current sequence pays for the shared libraries N times

`@carlonicora/nestjs-neo4jsonapi` and `@carlonicora/nextjs-jsonapi` are git
submodules under `packages/` in every nja app, consumed as `workspace:*`. A
dependency sweep of one app edits **both** the app's manifests and the two
library worktrees (peer ranges, catalog floors).

Today that forces this sequence:

1. Sweep app A. The library edits are validated against **A only**.
2. Commit and push both libraries.
3. Sweep apps B…N, each pulling the new library SHA.

Step 1 is the flaw. A peer floor derived from app A may be wrong for app D — and
the only way to find out is to reach step 3, at which point fixing it means a
**second** library commit and a second release. The number of library releases
per fleet upgrade is unbounded and driven by sweep order.

### 1.2 The fleet is already in lockstep, and pays as if it weren't

Measured on 2026-08-28 across `a360ai`, `dreamer`, `neural-erp`, `only35`,
`phlow`, `wyrdli`:

- **Five of six pin identical library SHAs** — `c0f3ea0` (nestjs-neo4jsonapi)
  and `039738f` (nextjs-jsonapi), all on `master`.
- **Their pnpm catalogs are byte-identical** — 21 entries, zero diff across
  `a360ai`, `dreamer`, `neural-erp`, `only35`, `wyrdli`.
- **84 non-catalog dependencies are identical in all six.**

The staggered sweeps produce a synchronised result. What they don't produce is a
single *decision*: every major is answered once per repo, and every hold's
unblock condition is re-tested once per repo.

### 1.3 The drift that does exist is pure scheduling noise

Every observed divergence is explained by "swept on a different day":

| Package | Versions across the fleet |
|---|---|
| `next`, `eslint-config-next`, `@next/*` | `16.3.0` vs `16.3.3` |
| `ai` | `^6.0.238` vs `^7.0.79` |
| `framer-motion` | `^12.43.0` vs `^13.1.1` |
| `bullmq` | `6.0.2` vs `6.3.1` (both caret-less) |
| `@aws-sdk/*` | `^3.1100.0` / `^3.1117.0` / `^3.1119.0` |
| `@nestjs/*` (catalog) | `^11.1.28` vs `^11.2.3` |

The `bullmq` row is the interesting one. `scripts/update.sh` records the
rule-of-thumb that *a caret-less range is a deliberate pin*. Two repos therefore
hold two contradictory deliberate pins — and six independent sweeps each honour
their local pin and **never notice the contradiction**.

### 1.4 A bad library sweep breaks `master` with no gate

Both libraries release via semantic-release on push to `master`
(`.github/workflows/release.yml`, trigger `on: push: branches: [master]`). There
is no PR gate. The `2026-08-25` run titled `chore(deps): dependency sweep
2026-08-25` **failed**. A library sweep validated against one app can red the
default branch of a library six apps depend on.

CI is fast — nestjs-neo4jsonapi ~90s, nextjs-jsonapi ~3min — so waiting on it is
cheap. Validating *before* it is what's missing.

### 1.5 The SHA an app must pin does not exist until CI finishes

semantic-release runs `@semantic-release/git` with
`message: "chore(release): ${nextRelease.version} [skip ci]"` and assets
`CHANGELOG.md`, `package.json`. The commit an app should pin is therefore the
**release** commit created by CI, not the sweep commit pushed from the machine.
Any design that fans a locally-created library commit out to the apps pins every
app one commit behind its own release.

---

## 2. Goals and non-goals

**Goals**

1. Exactly **one release per library** per fleet upgrade, validated against every
   participating app before it is pushed.
2. **One decision round.** Each major, conflict, and hold is answered once for
   the fleet, not once per repo.
3. **Lockstep versions.** One target version per package, fleet-wide.
4. A roster that is **discovered and confirmed at every run**, never stored in
   the skill.
5. Verification depth per app unchanged from single-repo mode: lint, build,
   test, and a real `pnpm dev` boot.
6. Resumability — a 2–3 hour run must survive an interruption.

**Non-goals**

- Committing app repos. That stays the user's call after manual testing.
- Reconciling a stale app's own code divergence (see §3.3, phlow).
- Replacing `nja-update-dependencies`. Single-repo runs keep using it.
- Migrating the libraries from submodule consumption to published npm
  consumption. That would make this design unnecessary, and costs live
  cross-app library editing. Named here so it is a choice, not an omission.

---

## 3. Roster discovery

### 3.1 Discovery runs fresh, every invocation

No member list lives in the skill. Scan roots are the parent directory of the
invoking repo, plus any additional roots persisted in
`~/.claude/nja-fleet/roots.json` (so a project outside the usual tree is found
on later runs without being hardcoded). Each candidate is tested with the
existing `nja_is_project` predicate from `nja-detect.sh` — an `nja.config.json`,
or a tracked `package.json` depending on `@carlonicora/nestjs-neo4jsonapi` or
`@carlonicora/nextjs-jsonapi`. A repo the plugin's hooks already consider nja is
automatically a fleet candidate the day it is created.

### 3.2 Identity is the origin remote

Members are keyed by `git remote get-url origin`, not by path. A moved or
renamed directory is recognised as the same member; two checkouts of one repo
are reported as a duplicate rather than swept twice.

### 3.3 Eligibility is computed, not declared

A discovered repo is **fleet-eligible** when all hold:

1. Root working tree clean.
2. Both submodule worktrees clean.
3. Both submodules on `master`.
4. Both submodules at the fleet-common SHA.

The **fleet-common SHA** is the modal SHA across discovered members, computed per
library. If no SHA holds a strict majority — the fleet has genuinely forked —
criterion 4 cannot be evaluated, and the run stops at F0 with the SHA groups
printed and asks which one is the intended base. It never picks for the user.

Failures are reported with their specific reason. On 2026-08-28, `phlow` fails
all four (root at `2026-06-27`, both submodules detached at `763a2f7` /
`783023a`, 36 dirty files). That is an outcome of the gate, **not** a property of
the design: if `phlow` is cleaned up it joins with no skill change, and if
`wyrdli` is mid-feature next month `wyrdli` is the one that sits out.

### 3.4 Change since the last run is reported, never acted on

The state file records the previous run's participants. This run reports:
members seen before, members newly discovered ("include it?"), and members that
participated previously and are no longer found ("moved or deleted?"). Membership
is never inferred from history.

### 3.5 Selection is the user's, every run

The full discovered table is printed — member, last commit date, both submodule
SHAs, eligibility, reason if not — then the roster is confirmed via
`AskUserQuestion`. Because that tool caps at four options and the fleet grows,
the question is shaped to scale: *all eligible* / *all eligible except ones I
name* / *I'll list them*, with the table above carrying the detail. An ineligible
repo can be force-included by naming it, with its failing gate restated as a
warning. Inclusion of an ineligible repo is always loud and never automatic.

---

## 4. The decision ledger

### 4.1 Why it must exist

Lockstep cannot be achieved by running the sweep N times and trusting the
answers to match. A fleet run takes 2–3 hours; if npm publishes `next 16.4.2`
ninety minutes in, the last repo swept lands a different version than the first
and lockstep breaks with nothing in the diff to show it. The ledger pins the
moment the fleet was surveyed.

It is also what makes the run resumable: a failure at member 4 of 5 re-enters
from the ledger instead of re-deriving a now-different target.

### 4.2 Location and shape

`~/.claude/nja-fleet/<YYYY-MM-DD>/ledger.json`, written **before any manifest is
touched**, shown to the user, and read (never re-derived) by every later phase.

```json
{
  "run": "2026-08-28",
  "roster": [{ "name": "wyrdli", "path": "…", "origin": "…" }],
  "libraries": {
    "nestjs-neo4jsonapi": { "canonical": "<member>", "released": null },
    "nextjs-jsonapi":     { "canonical": "<member>", "released": null }
  },
  "packages": {
    "next": {
      "current":  { "wyrdli": "16.3.3", "only35": "16.3.3" },
      "latest":   "16.4.1",
      "target":   "16.4.1",
      "kind":     "minor",
      "surfaces": ["catalog", "overrides", "apps/web",
                   "nextjs-jsonapi:devDependencies"],
      "seen_in":  ["…"],
      "decision": "take"
    },
    "framer-motion": {
      "latest": "13.2.0", "target": "^12.43.0",
      "kind": "major", "decision": "hold",
      "held_by": ["only35"],
      "reason": "…", "unblock": "…",
      "retested": "2026-08-28 — still fails"
    },
    "bullmq": {
      "current": { "wyrdli": "6.0.2", "neural-erp": "6.3.1" },
      "kind": "conflict", "decision": null
    }
  }
}
```

### 4.3 How it is computed

`nja-deps-sweep.sh --dry-run --root <r>` runs across every roster member **and**
both library checkouts, in parallel, and results are unioned per package.

- A package present in only some repos stays scoped to those repos via
  `seen_in`. Nothing is ever *added* to a repo that does not have it.
- Where repos disagree on the current version, one target is chosen and the
  laggard takes the larger jump. The report shows this explicitly: a two-minor
  jump is a different review than a patch.

### 4.4 Holds are unioned, attributed, and re-tested once

Sources: `references/hazards.md` §2 (stack-invariant) plus every member's
`DEFERRED MAJOR BUMPS` block in `scripts/update.sh`.

- Under lockstep a hold anywhere is a hold everywhere.
- `held_by` records the originating repo, so when the blocker clears it is known
  which repo to test against.
- Each hold's **stated** unblock condition is re-tested **once per run**, not
  once per repo. This is where most of the wall-clock saving comes from. The
  existing rule stands: unblock conditions are not interchangeable, and a hold
  whose break is a runtime failure (eslint's `FlatESLint` relocation) demands
  exercising that runtime, not a `peerDependencies` lookup.
- A hold naming a package its originating repo no longer has is flagged **stale**
  and not propagated to the fleet.

### 4.5 Conflicts

Two members holding contradictory deliberate pins (`bullmq 6.0.2` vs `6.3.1`)
are classified `kind: "conflict"`. The ledger **refuses to pick** and routes them
into the question round. This class of finding is invisible to per-repo sweeps.

### 4.6 One question round

Everything needing judgment — majors, conflicts, and holds whose unblock
condition now passes — is batched and asked once. Everything else (minors,
patches, packages where all members already agree) is applied without asking,
exactly as in single-repo mode.

`AskUserQuestion` caps at four questions per call, and a full sweep can surface
more than four decisions. They are therefore asked in **consecutive calls of up
to four**, ordered by blast radius: conflicts first (they block the ledger), then
majors on packages the libraries declare as peers (they determine the release),
then remaining majors, then cleared holds. Each call is preceded by the full
decision table in chat, so the batching never hides an item. "One round" means
one uninterrupted decision pass before any manifest is written — not literally
one tool call.

### 4.7 Applied, not recomputed

New mode: `nja-deps-sweep.sh --ledger <file>`. It writes all three surfaces
(manifests, `catalog:`, `overrides:`) to exactly the ledger's targets and **does
not consult the registry**. If a repo's declared range cannot accept its target —
a `~4.1.0` range against target `4.2.0`, meaning the range itself needs widening
— it refuses with a **new `nja-deps-sweep.sh` exit code 4**, because widening a
range is a decision, not a mechanical step. That code is currently unused by this
script; existing codes are unchanged (`1` usage/environment, `3` override below a
declared floor). It is unrelated to `nja-dev-boot.sh`'s exit 4 (§6.1), which
means unverified teardown — the spec always names the script alongside the code
for that reason.

---

## 5. The library cycle

### 5.1 F2 — Sweep the libraries once

Each library exists in N submodule worktrees. One is designated **canonical** —
the first eligible member in **roster order** (the order the survey printed,
which is alphabetical by member name), named in the ledger and reported. Since
every eligible member sits at the same SHA by §3.3 criterion 4, the choice is
arbitrary; it is made deterministic only so that a resumed run picks the same
checkout it started with.

Before editing: `git fetch origin`, then verify the canonical checkout is clean
and **at** `origin/master`. If origin has moved ahead of the SHA the fleet pins,
that is surfaced as a fact — otherwise the sweep silently carries someone else's
commits into all N apps under the label "dependency sweep".

Then: apply the ledger to the library's own manifests; derive its
`peerDependencies` floors and the catalog floors from the ledger (one correct
value each, now that targets are fleet-wide); run `pnpm build` in the canonical
checkout. CI runs exactly `pnpm install && pnpm build`, so a local build failure
predicts the CI failure — the shape of the red `2026-08-25` run.

### 5.2 F3 — Validate against the whole fleet, with nothing pushed

The canonical checkout's **working-tree diff** is propagated to every other
member's submodule by patch: `git -C <canonical> diff`, then `git apply --check`
followed by `git apply` in each member's submodule. No commits anywhere;
rollback is `git checkout -- .` per submodule.

A `--check` failure means a member's submodule is not at the expected base — the
eligibility gate already ruled that out, so it is an anomaly that **stops the
run** rather than being forced.

Then per member: ledger applied to its own manifests → one
`CI=true pnpm install --no-frozen-lockfile` → `nja-deps-doctor.sh` →
`pnpm build`. **All must pass.**

Lint, tests and dev boots are deliberately excluded here. F3 answers only "does
this library state break a consumer", and it may loop several times as the ledger
is adjusted; keeping the loop to install/doctor/build is what makes iterating
affordable. The full pipeline runs later against the real released SHA.

**This phase is the reason the redesign is worth building.** Today the peer
floors are validated against whichever app was swept first, and every other
app's disagreement costs another library release.

### 5.3 F4 — The one-way door

Everything before F4 is local and discardable. F4 is not.

One explicit confirmation gate, showing both library diffs, the members that
validated them, and the exact commit messages. **Push authority is granted per
run and never defaults on.** The skill asks every time.

- Commits: `chore(deps): dependency sweep YYYY-MM-DD`, matching `79276ef` and
  resolving to a patch release under the `.releaserc` `releaseRules`.
- Both libraries push to `master`. CI runs in parallel.
- The skill polls for the run **matching the pushed SHA**, not merely the latest
  run for the repo.

**If either CI fails, that is an incident, not a retry.** `master` is broken. The
run stops, reports the run URL, and touches no app repo. Member working trees
still hold uncommitted F3 changes; the report gives the per-member
`git checkout -- . && git clean -fd` to discard them. A library whose CI
succeeded has released — that release is valid and simply goes unpinned.

On success: `git fetch origin && git reset --hard origin/master` in the canonical
checkout picks up the `chore(release): X.Y.Z [skip ci]` commit; the released
version and SHA go into the ledger. If semantic-release determines no release is
warranted there is no release commit, and the SHA to pin is the sweep commit
itself. **Both cases are handled explicitly rather than assumed.**

### 5.4 F5 — Fan out the released SHA

Per member: discard the F3 patch **inside the two submodule worktrees only** —
`git checkout -- . && git clean -fd` run with `-C <member>/packages/<lib>`, never
at the member root — then `git fetch origin && git checkout <release-sha>`: the
**exact SHA**, never `master`, so every member pins identically even if someone
pushes to the library mid-run. Then `pnpm install` (the gitlink moved), then
`nja-deps-doctor.sh` as the gate.

**The member's own manifest edits from F3 are kept.** They are that app's sweep,
already computed from the ledger and already validated; re-deriving them here
would reintroduce exactly the drift §4.1 exists to prevent. Only the submodule
worktrees are reset. A reset at the member root would silently discard the whole
app-level sweep and is the single most damaging mistake available in this
phase — the implementing script must scope every reset with `-C` and must never
run one at a member root.

### 5.5 What rollback means after F4

`nja-update-dependencies` promises "HEAD is the rollback point". That promise no
longer covers the libraries: the release is published and permanent. It is,
however, a *valid* release. Rollback is per-member
`git checkout -- . && git clean -fd` plus resetting each submodule to its
pre-run SHA; the library version stands unused until a later run pins it. The
report states this in those words, because it is the one place the run's
reversibility story genuinely changed.

---

## 6. Verification and landing

### 6.1 F6 — Waves, then a queue

Per member: `lint → build → test`, fanned out across members in parallel waves.
Parallelism is **script-owned, not agent-owned** — background jobs with a
per-member log file under the run's state dir, matching the plugin's principle
that scripts own everything mechanical. Wave width defaults to **3** (Next.js
builds are memory-hungry and the pnpm store is shared) and is overridable via
`NJA_FLEET_WIDTH`.

Fail-fast applies **within** a member (lint red skips that member's build and
test) but never **across** members: a failure must not abort the others, because
the comparison between them is the diagnostic (§6.2).

Then the dev boots, strictly serialized through `nja-dev-boot.sh --root <r>` in
roster order. Serialization is required, not preferred: all members share one
Neo4j (`bolt://localhost:7687`) and one Redis, and `phlow` and `wyrdli` both
claim ports 3950/3951.

**Fleet-specific rule: an exit 4 aborts the remaining boot queue.** Exit 4 means
teardown could not be verified and a process group may still be live; the next
member's boot would then fail on a port that is not free, and that failure looks
identical to a dependency break. In single-repo mode exit 4 is an emergency to
report; in fleet mode it is also a **stop**, because continuing manufactures
false failures.

All standing rules carry over unchanged: a busy port is never freed, no
`pkill` / `killall` / `pgrep` or any name-pattern kill ever, teardown only by the
process group `nja-dev-boot.sh` created.

### 6.2 Differential attribution

With identical targets fleet-wide, the *pattern* of failures is evidence:

| Pattern | Verdict | Action |
|---|---|---|
| N−1 green, one red | the member's own code, not the sweep | run the lazy-baseline dance **for that member only** |
| All red | the sweep | bisect the ledger — cheaper than N baselines |
| A subset red | shared trait of the failing members | group failures by what they share (app layout, optional package, `apps/corpus`) — usually names the culprit with no baseline run at all |

This demotes the expensive stash/reinstall/re-boot/restore baseline from a
reflex to a targeted tool, and is what makes fleet mode *faster* than N single
runs rather than merely more convenient.

### 6.3 F7 — Landing

Each member's `DEFERRED MAJOR BUMPS` block is rewritten **from the one ledger**,
so the blocks become identical across the fleet plus a short per-member notes
section. Today those N blocks drift independently and the next run must reconcile
them. Where `scripts/update.sh` does not exist it is created minimally, as in
single-repo mode.

The commit sequence gets **simpler**, for a reason worth naming: the
submodules are already at a pushed, released SHA, so there is nothing to commit
inside them. The submodules-first ordering that `nja-update-dependencies` has to
choreograph disappears. Each member is one flat commit — the two gitlinks, the
manifests, `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `scripts/update.sh`.

**Printed, not run.** The skill never commits an app repo.

### 6.4 The fleet report

Written to the run's state dir:

1. Roster, with exclusions and their specific reasons.
2. Ledger summary, split into taken / held / conflicts resolved.
3. Both library releases: version, SHA, CI run URL.
4. Per-member verification matrix across lint / build / test / boot.
5. Failures with their attribution verdict (§6.2).
6. Per-member commit sequence, not run.
7. Per-member rollback, including the explicit note that the library releases
   stand (§5.5).
8. The manual test list.

The state file is retained after the run: it is what makes `--resume` work after
an interruption, and what lets the next run report roster changes (§3.4).

---

## 7. Phase table

| Phase | Action | Gate |
|---|---|---|
| F0 | Discover roster; compute eligibility; report changes since last run; confirm selection | **ASK** — never infer membership |
| F1 | Union `--dry-run` sweeps + hold reconciliation → write `ledger.json`; one question round | **ASK** on every major, conflict, and cleared hold |
| F2 | Sweep both libraries in the canonical checkouts; derive peer/catalog floors; `pnpm build` | **STOP** if canonical is dirty, not on `origin/master`, or fails to build |
| F3 | Patch the library diff into every member; apply ledger; install → doctor → build | **STOP** on any member failing; loop back to F1/F2 — nothing pushed |
| F4 | Confirm; commit; **push both libraries**; poll CI for the pushed SHA; pull the release commit | **ASK** before push; **STOP** and report as an incident on CI failure |
| F5 | Reset submodules to the exact released SHA in every member; `pnpm install`; doctor | **STOP** on doctor failure |
| F6 | Waves of lint/build/test; then serialized dev boots | fail-fast within a member, never across; **exit 4 aborts the boot queue** |
| F7 | Rewrite `DEFERRED MAJOR BUMPS` from the ledger; write the fleet report; print commit sequences | — |

---

## 8. Deliverables

**New skill** — `nja/skills/nja-update-fleet/SKILL.md`, with
`references/fleet-hazards.md` for the fleet-specific rules (exit-4 boot-queue
abort, post-F4 rollback semantics, conflict class, differential attribution).

**Skill interface** — `nja-update-fleet` takes no required arguments.
`--resume` re-enters the most recent run in `~/.claude/nja-fleet/` at its last
completed phase, reusing `ledger.json` unchanged; it refuses if the roster on
disk no longer matches the one the ledger recorded, since a changed roster
invalidates the lockstep targets. `--roots <path,…>` adds scan roots and persists
them to `roots.json` (§3.1).

**New scripts**

- `nja/scripts/nja-fleet-survey.sh` — discovery, identity, eligibility, and the
  roster table. Deterministic; the model only asks the selection question.
- `nja/scripts/nja-fleet-waves.sh` — background-job wave scheduler with
  per-member logs, `NJA_FLEET_WIDTH`, and the serialized boot queue.

**Changed scripts**

- `nja-deps-sweep.sh` — add `--ledger <file>` (apply exactly, no registry
  lookup) and **exit 4** for a target a declared range cannot accept.

**Unchanged** — `nja-deps-doctor.sh`, `nja-dev-boot.sh`, `nja-detect.sh`,
`nja-deps-lib.sh`, and the whole of `nja-update-dependencies`.

**Evals** — mirroring the four existing `nja-update-dependencies` scenarios:

1. Ineligible member in the roster (dirty tree / detached submodule).
2. Conflicting deliberate pins (`bullmq 6.0.2` vs `6.3.1`).
3. Library CI fails after push — incident handling, no app repo touched.
4. One member's dev boot fails while the rest pass — differential attribution.
5. Boot exits 4 mid-queue — the remaining boots must not run.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| A member is force-included while ineligible and poisons the ledger | Force-inclusion is explicit, restates the failing gate, and is recorded in the report |
| The F3 patch does not apply to a member | `git apply --check` first; failure stops the run rather than forcing |
| CI reds `master` after push | F2's local `pnpm build` and F3's fleet-wide build catch the known failure shape before F4 |
| A run is interrupted mid-fleet | `ledger.json` plus per-phase state make `--resume` re-enter from the last completed phase |
| The fleet grows past what one question can list | Roster selection is table-plus-shaped-question, not one-option-per-member (§3.5) |
| A leaked process group makes later boots fail spuriously | Exit 4 aborts the boot queue (§6.1) |
