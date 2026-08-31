# Fleet hazards

Hazards that exist ONLY when upgrading several nja monorepos as one unit.
Single-repo hazards live in `nja-update-dependencies/references/hazards.md`
and still apply in full — this file does not repeat them.

## §1 — The one-way door is F4, and only F4

Everything before F4 is local and discardable: `git checkout -- .` and
`git clean -fd` in each member restores it exactly. F4 pushes to a library's
`master`, and both libraries release via semantic-release on push
(`.github/workflows/release.yml`, `on: push: branches: [master]`). There is no
PR gate.

After F4:

- The release is **published and permanent**. It is, however, a *valid*
  release — rollback is per-member `git checkout -- . && git clean -fd` plus
  resetting each submodule to its pre-run SHA, and the library version simply
  stands unused until a later run pins it.
- `nja-update-dependencies`'s promise that "HEAD is the rollback point" no
  longer covers the libraries. Say so in the report, in those words.

**Push authority is granted per run.** It never defaults on. Ask every time.

## §2 — Apps pin the CI-produced commit, not the local one

semantic-release runs `@semantic-release/git` with
`message: "chore(release): ${nextRelease.version} [skip ci]"`, committing
`CHANGELOG.md` and `package.json` back to `master`. **The SHA an app must pin
does not exist until CI finishes.**

Fanning a locally-created library commit out to the members pins every app one
commit behind its own release. Always: push → poll CI for the pushed SHA →
`git fetch && git reset --hard origin/master` → pin *that* SHA.

If semantic-release decides no release is warranted, there is no release
commit and the SHA to pin is the sweep commit itself. Handle both; never
assume the release commit exists.

## §3 — `nja-dev-boot.sh` exit 4 aborts the boot queue

Exit 4 means teardown could not be verified and a process group may still be
live. The next member's boot would then fail on a port that is not free, and
that failure is **indistinguishable** from a dependency break.

In single-repo mode exit 4 is an emergency to report. In fleet mode it is
also a **stop**: `nja-fleet-waves.sh` returns 4 and runs no further member.
Continuing manufactures false failures and destroys the attribution signal
in §4.

The standing rules are unchanged and absolute: no `pkill`, `killall`,
`pgrep`, or any name- or pattern-based kill, ever — several nja repos run at
once on this machine with byte-identical command lines. A busy port is never
freed; it is not ours. Teardown is only ever by the process group
`nja-dev-boot.sh` created.

## §4 — Differential attribution replaces the reflexive baseline

With identical targets fleet-wide, the *pattern* of failures is evidence:

| Pattern | Verdict | Action |
|---|---|---|
| N−1 green, one red | the member's own code, not the sweep | run the lazy-baseline dance **for that member only** |
| All red | the sweep | bisect the ledger — cheaper than N baselines |
| A subset red | a shared trait of the failing members | group by what they share (app layout, an optional package, a third app like `a360ai`'s `corpus`) — usually names the culprit with no baseline run at all |

The expensive stash / reinstall / re-boot / restore baseline is a **targeted
tool**, not a reflex. Running it N times is the mistake this table exists to
prevent.

## §5 — Caret-less means different things on different surfaces

Two members can hold **contradictory** deliberate pins — `bullmq 6.0.2` in one
and `6.3.1` in another, both caret-less. N independent sweeps each honour
their local pin and never notice. The ledger classifies this as a `conflict`,
**refuses to pick**, and routes it to the user.

`nja-deps-sweep.sh --ledger` enforces the rule mechanically, but only where
exactness actually carries meaning — and the distinction is load-bearing:

| Surface | A caret-less entry means | Ledger mode |
|---|---|---|
| a manifest (`package.json`) | a deliberate pin — the rule of thumb recorded in every app's `scripts/update.sh` | **refuses**, exit 4 |
| `overrides:` | a deliberate forced resolution, usually with an incident comment beside it | **refuses**, exit 4 |
| `catalog:` | nothing — exact versions are the NORM there | moves freely |

The catalog exception is not a loophole. `react`, `react-dom`,
`@types/react`, `@types/react-dom`, `next` and `react-hook-form` are all
caret-less in every member's catalog *precisely so* the workspace resolves to
one copy. Refusing those would mean the fleet could never take a routine
React or Next bump.

A refusal writes **nothing at all**, not even the packages that would have
succeeded. A half-applied fleet is worse than an unapplied one: the diff
stops being reviewable.

(`nja-deps-sweep.sh` exit 4 and `nja-dev-boot.sh` exit 4 are unrelated.
Always name the script alongside the code.)
