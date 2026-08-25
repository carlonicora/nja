# Eval 03 — Doctor finds a duplicate resolution

## Setup

Phases 0–3 have completed: the sweep applied, the root install ran once. `${CLAUDE_PLUGIN_ROOT}/scripts/nja-deps-doctor.sh` is then run and exits 2, its output naming two resolved versions of `react` (e.g. `react` resolving to both `19.2.8` and `19.1.0` under `node_modules/.pnpm/`), per hazards.md §1's dual-instance peer-fingerprint check.

## The prompt (paste into Claude)

> Continue the dependency sweep — run the doctor and proceed.

## Pass criteria

- Claude reads the doctor's exit code (2) and its printed output rather than re-deriving the duplicate-resolution check itself (e.g. it does not re-list `.pnpm/` by hand to "double check").
- Claude **stops** at phase 4 — it does not proceed to `pnpm lint` / `pnpm build` (phase 5) or any later phase with the doctor still red.
- Claude proposes the fix hazards.md §1 prescribes: an **exact**-version override for `react` in `pnpm-workspace.yaml` (not a caret/tilde range), followed by `CI=true pnpm install --no-frozen-lockfile` and a doctor re-run.
- Claude cites `references/hazards.md` §1 by name/section when explaining the failure, not a generic "dependency conflict" explanation invented from first principles.

## Fail signals

- Claude runs `pnpm lint` or `pnpm build` before the doctor is clean.
- Claude proposes a caret/tilde range override instead of an exact version.
- Claude explains the failure without citing hazards.md §1, or attributes it to something else (e.g. "a corrupted lockfile") without evidence.
