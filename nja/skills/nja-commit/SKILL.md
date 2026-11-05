---
name: nja-commit
description: Use when Carlo wants a finished round of changes committed in an nja monorepo, library submodules included. Commits and pushes changed library submodules, waits for their GitHub release runs, pulls the released versions, runs pnpm sync:versions, then makes one commit in the main repo and stops. Triggers include "nja-commit", "commit everything", "commit the round", "commit and release the packages".
---

# nja commit

Calling this skill is the go-ahead to commit and push. Do not ask for
confirmation, do not show messages for approval. Stop only where a step below
says STOP.

Run every command from the main repo root (`git rev-parse --show-toplevel`).
In a worktree, that is the worktree root.

## 1. Survey

- Library submodules: `git config -f .gitmodules --get-regexp '\.path$'`.
  Only submodules whose path is under `packages/` count.
- For each one, run `git -C <path> status -sb` and `git -C <path> fetch`.
  - Not on branch `master` (detached HEAD, other branch): **STOP**, say which.
  - It has changes when its tree is dirty, or it is ahead of `origin/master`.
- Main repo: `git status --porcelain` (lists the submodule paths too).
- No library changes and a clean main repo: say "nothing to commit" and stop.
- No library changes: skip to step 4.

Report in one line what will happen, e.g. "committing nestjs-neo4jsonapi,
nextjs-jsonapi clean, then the main repo".

## 2. Commit and push each changed library

For each changed library:

1. Read the diff (`git -C <path> diff`, `git -C <path> status --porcelain`).
2. Stage by name: every modified, deleted and untracked file the status lists.
   Never `git add -A` or `git add .`.
3. Commit with a message drafted from the diff, in the style of
   `git -C <path> log -10 --format=%s`: a conventional type, then a plain
   sentence saying what now behaves differently for the user of the library.
   - `feat` releases a minor, every other type a patch.
   - Never `!` after the type, never a `BREAKING CHANGE` footer: the release
     tool would cut a major.
   - No `Co-Authored-By`, no session or Claude attribution lines.
   - Pass the message through `nja-unslop` before committing.
4. `git -C <path> pull --rebase` if it is behind `origin/master`. On a
   conflict: `git -C <path> rebase --abort` and **STOP**, naming the files.
5. `git -C <path> push`. Record the pushed SHA: `git -C <path> rev-parse HEAD`.

## 3. Wait for the releases, pull them

Each library releases from `.github/workflows/release.yml` on push to
`master`. The run takes up to 10 minutes, so wait in the background.

1. Repo slug: from `git -C <path> remote get-url origin` (`owner/name`).
2. Find the run for the pushed SHA; it can take a minute to appear:

   ```bash
   gh run list --repo <slug> --workflow release.yml --commit <sha> \
     --json databaseId,status,conclusion,url --limit 1
   ```

3. Watch it with `run_in_background: true`, one per library, all started
   together:

   ```bash
   gh run watch <databaseId> --repo <slug> --exit-status --interval 30
   ```

   Tell Carlo it is waiting and on which runs. Do not poll; the background
   task notifies when it ends.
4. A run that fails: **STOP**. Report the run URL. Touch nothing else: no
   pull, no `sync:versions`, no main repo commit. A red `master` on a shared
   library is an incident, never a retry with a fix commit.
5. On success: `git -C <path> pull --ff-only`. The release tool commits
   `chore(release): <version> [skip ci]` back to `master`; the new version is
   in `<path>/package.json`.
   - If the last commit is not a `chore(release):` one, no release was cut
     (for example a `[skip release]` commit). Say so; the version stays.
6. Do not check npm. Publishing takes about 10 minutes and the commit only
   needs the version in the repo: once `<path>/package.json` has the new
   version, go on to step 4.

## 4. Sync the versions

Run `pnpm sync:versions`. If the repo has no such script, **STOP** and say so.
Read its output: it lists each version change in `versions.production.json`.

## 5. Commit the main repo

1. `git status --porcelain`. Stage every listed path by name: app changes,
   the submodule paths (their new pointers), `versions.production.json`.
   Never `git add -A` or `git add .`.
2. One commit, on the current branch, message in the style of
   `git log -10 --format=%s`:
   - With app changes: a conventional type and a plain sentence on what
     changed for the user, ending with the library versions it now uses,
     e.g. `...; updates @carlonicora/nestjs-neo4jsonapi to version 8.19.2`.
   - Only version moves: `chore: update @carlonicora/<lib> to version <v>`,
     joined with ` and ` when both moved.
   - Same rules as step 2: no `!`, no `BREAKING CHANGE`, no attribution
     lines, `nja-unslop` before committing.
3. Do not push the main repo. Stop here.

## Report

Under ten lines: each library's new version (or "unchanged"), the main repo
commit's first line and SHA, and anything that stopped the run with its URL.
