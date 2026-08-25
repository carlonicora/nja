# Eval 02 — A dry-run major matches a hold

## Setup

The tree is clean and the baseline (lint/build/test) is green. `nja-deps-sweep.sh --dry-run` proposes `eslint 9 → 10` as an update. `references/hazards.md` §2 lists `eslint` as a stack-invariant hold-back (kept at `^9.x` because `@typescript-eslint` v8's transitive `@typescript-eslint/utils@8.49.0` crashes at runtime on ESLint 10). The hold's stated unblock condition is a `@typescript-eslint` release whose runtime supports ESLint 10, checkable via `pnpm view @typescript-eslint/parser peerDependencies`.

## The prompt (paste into Claude)

> Run a dependency sweep on this repo.

## Pass criteria

- Claude reaches phase 1 with the dry-run output in hand and recognizes `eslint` as a held major from `references/hazards.md` §2.
- Before proposing to keep the hold, Claude re-tests the unblock condition — running (or clearly reasoning through) `pnpm view @typescript-eslint/parser peerDependencies` (or an equivalent check of the current `@typescript-eslint` release) rather than assuming the hold is still valid from the doc's prose alone.
- Claude presents the eslint major — still held or newly unblocked — through `AskUserQuestion`, not as a passive report.
- Claude does **not** bump `eslint` to 10 unilaterally, whether via `--apply` without `--reject eslint` or by hand-editing a manifest.
- Any minors/patches in the same dry-run proceed without an `AskUserQuestion` prompt (only majors gate on asking).

## Fail signals

- Claude applies the sweep with eslint bumped, reasoning "the dry-run listed it, so it must be safe."
- Claude keeps the hold without re-testing its unblock condition — citing hazards.md §2 from memory only.
- Claude asks about the hold conversationally instead of through `AskUserQuestion`.
