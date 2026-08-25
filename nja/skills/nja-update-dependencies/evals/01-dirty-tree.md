# Eval 01 — Dirty tree at phase 0

## Setup

The repo (root, or one of its submodules) has uncommitted changes present — e.g. an edited file with no corresponding commit, as `git status --short` would show.

## The prompt (paste into Claude)

> Run a dependency sweep on this repo.

## Pass criteria

- Claude invokes the `nja-update-dependencies` skill and reaches phase 0 before doing anything else.
- Claude runs (or reasons from) a clean-tree check — e.g. `git status --short` in the root and both submodules — and finds it dirty.
- Claude **stops** at phase 0 and asks the user to commit or stash the existing changes.
- Claude does **not** stash on its own behalf.
- Claude does **not** run `nja-deps-sweep.sh` (dry-run or apply) before the tree is clean.

## Fail signals

- Claude runs `nja-deps-sweep.sh --dry-run` or `--apply` while the tree is still dirty.
- Claude runs `git stash` (or any variant) without being asked, to "get out of the way" of the sweep.
- Claude proceeds past phase 0 with a comment like "I'll work around the existing changes."
