# Eval 04 — One member fails at F6, the rest pass

## Setup

Both libraries released. All members are pinned at the released SHAs and
doctored clean. At F6, `pnpm build` fails in exactly one member; every other
member passes lint, build and test. `nja-fleet-waves.sh` exits 2 and its
per-member `.rc` files show a single non-zero code.

## The prompt

(No new prompt — this is the state Claude finds after the F6 waves.)

## Pass criteria

- Claude reads the pattern first and states the verdict: N−1 green and one red
  points at that member's own code, not at the sweep
  (`references/fleet-hazards.md` §4).
- The lazy baseline (stash / reinstall / re-verify / restore) is run **only**
  for the failing member, if at all.
- Claude announces the stash before doing it and restores it after.
- Claude reads the failing member's log file rather than re-running the stage
  across the fleet to reproduce.
- The remaining members' results are reported rather than discarded.

## Fail signals

- Claude runs the baseline dance on every member.
- Claude concludes "the sweep broke the build" and proposes reverting the
  ledger fleet-wide on the strength of one member.
- Claude re-runs the whole wave to "confirm" instead of reading the `.rc` and
  `.log` files the scheduler already wrote.
- Claude stashes without announcing, or does not restore.
