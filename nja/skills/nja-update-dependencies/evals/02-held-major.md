# Eval 02 — A dry-run major matches a hold

## Setup

The tree is clean and the baseline (lint/build/test) is green. `nja-deps-sweep.sh --dry-run` proposes `eslint 9 → 10` as an update. `references/hazards.md` §2 lists `eslint` as a stack-invariant hold-back (kept at `^9.x` because `@typescript-eslint` v8's transitive `@typescript-eslint/utils@8.49.0` crashes **at runtime** on ESLint 10 — `FlatESLint` was removed/relocated, producing `TypeError: Class extends value undefined is not a constructor or null`). The hold's stated unblock condition, per that row, is: *"A `@typescript-eslint` release whose runtime (not just its peer ranges) supports ESLint 10. Verify by running ESLint directly against a TS file before bumping the whole repo."* A `peerDependencies` lookup (e.g. `pnpm view @typescript-eslint/parser peerDependencies`) cannot reveal this failure — it only shows declared compatibility ranges, not whether the runtime code path actually works, and hazards.md §2 exists precisely because peer ranges looked fine while the runtime crashed.

## The prompt (paste into Claude)

> Run a dependency sweep on this repo.

## Pass criteria

- Claude reaches phase 1 with the dry-run output in hand and recognizes `eslint` as a held major from `references/hazards.md` §2.
- Before proposing to keep (or lift) the hold, Claude re-tests the **runtime** unblock condition the hold's own row states — actually exercising ESLint's runtime against a TypeScript file with the candidate `@typescript-eslint`/ESLint versions (e.g. installing or dry-running the candidate versions in a scratch/temp setup and running `eslint` against a `.ts` file, or an equivalent concrete exercise of `@typescript-eslint`'s runtime), not a metadata lookup.
- A response that only runs `pnpm view @typescript-eslint/parser peerDependencies` (or any other peer-range/version lookup) **without also exercising the runtime** does not satisfy this criterion — that is the specific insufficient check hazards.md §2 warns against, and this scenario exists to catch an agent that substitutes it for the real one.
- Claude presents the eslint major — with the outcome of the runtime check, still held or newly unblocked — through `AskUserQuestion`, not as a passive report.
- Claude does **not** bump `eslint` to 10 unilaterally, whether via `--apply` without `--reject eslint` or by hand-editing a manifest.
- Any minors/patches in the same dry-run proceed without an `AskUserQuestion` prompt (only majors gate on asking).

## Fail signals

- Claude applies the sweep with eslint bumped, reasoning "the dry-run listed it, so it must be safe."
- Claude re-tests the hold using only `pnpm view <pkg> peerDependencies` (or `pnpm view <pkg> version`) and treats that alone as having "re-tested the unblock condition" — this is the exact insufficient check the scenario is designed to catch, since it would pass a hold whose actual failure is a runtime `TypeError` invisible to peer metadata.
- Claude keeps (or lifts) the hold without re-testing its unblock condition at all — citing hazards.md §2 from memory only.
- Claude asks about the hold conversationally instead of through `AskUserQuestion`.
