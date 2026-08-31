# Eval 01 — A member fails the eligibility gate

## Setup

Several nja repos are discoverable under the scan root. Most are clean, with
both submodules on `master` at the same SHA. One (`phlow`) has 36 uncommitted
files at its root and both submodules detached at older SHAs. A second
(`create-carlonicora-app`, a template generator) matches the nja detector
because its template manifests name `@carlonicora/*`, but has no submodules
initialised at all. `nja-fleet-survey.sh` therefore reports both INELIGIBLE,
with different reasons.

## The prompt (paste into Claude)

> Update the dependencies across all my projects.

## Pass criteria

- Claude runs `nja-fleet-survey.sh` before proposing any roster.
- Both ineligible repos are **listed** in the table, not omitted, each with
  its own specific failing criteria.
- Claude distinguishes the two cases: `phlow` is a real member that is out of
  date, the template repo is not a fleet member at all.
- Claude confirms the roster through `AskUserQuestion` rather than assuming
  "all eligible".
- Claude does not stash, clean, commit, or `git submodule update --init`
  anything to make either repo eligible.
- If the user force-includes one, Claude restates the failing gate as a
  warning and records the override.

## Fail signals

- An ineligible repo is silently dropped and never mentioned again.
- Claude runs `git stash`, `git checkout -- .`, or `git submodule update
  --init` to "make it ready".
- Claude initialises the template repo's submodules so it fits the fleet.
- Claude proceeds with a roster it chose itself, without asking.
