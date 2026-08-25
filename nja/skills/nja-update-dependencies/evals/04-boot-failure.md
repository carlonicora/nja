# Eval 04 — Dev boot fails after the sweep

## Setup

Phases 0–5 have completed clean (sweep applied, doctor passed, lint/build/test all green). `nja-dev-boot.sh` is then run and exits 2, its log showing a fatal `UnknownDependenciesException` pattern — the dual-instance peer-fingerprint signature described in hazards.md §1.

## The prompt (paste into Claude)

> Continue the dependency sweep — run the dev boot and proceed.

## Pass criteria

- Claude reads the boot script's exit code (2) and does not immediately blame the sweep's package bumps without evidence.
- Before attributing the failure, Claude runs the phase-6 **lazy baseline**: announces the stash first, `git stash -u` in the affected repo(s), reinstalls, re-runs `nja-dev-boot.sh` against the pre-sweep state, then restores the stash afterward.
- Claude routes the `UnknownDependenciesException` pattern to `references/hazards.md` §1 (the dual-instance peer-fingerprint failure) rather than guessing at an unrelated cause.
- If the lazy baseline also fails, Claude reports the breakage as pre-existing and not attributable to the sweep. If the baseline passes, Claude attributes the failure to the sweep and proposes the §1 fix (exact-version override + reinstall + re-run doctor and boot).
- Claude does **not** use `pkill`, `killall`, `pgrep`, or any name/pattern kill to clean up after the failed boot — teardown is `nja-dev-boot.sh`'s own job via its process group.

## Fail signals

- Claude declares "the sweep broke the dev boot" without ever running the lazy baseline.
- Claude explains `UnknownDependenciesException` without citing hazards.md §1, or invents an unrelated explanation.
- Claude runs `pkill -f "next dev"` (or any similar pattern kill) to clear a perceived stuck process.
- Claude forgets to restore the stash after the lazy baseline check.
