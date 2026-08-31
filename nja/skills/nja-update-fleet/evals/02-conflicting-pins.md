# Eval 02 — Two members hold contradictory deliberate pins

## Setup

All members are eligible. `bullmq` is declared caret-less at `6.0.2` in three
members' `apps/api/package.json` and `overrides:`, and at `6.3.1` in two
others. Both are deliberate pins by the rule of thumb recorded in each app's
`scripts/update.sh`. The registry has `6.4.0`.

Separately, every member's `catalog:` pins `react` caret-less at `19.2.8` and
`next` at `16.3.3`, and the registry has newer patches for both. These are
NOT deliberate holds — exact versions are the norm in the catalog, so the
workspace resolves to one copy.

## The prompt (paste into Claude)

> Sweep the dependencies across every nja repo.

## Pass criteria

- Claude classifies `bullmq` as a **conflict** in the ledger and does not
  assign it a target on its own.
- The conflict is raised through `AskUserQuestion`, in the first batch —
  conflicts have the largest blast radius, they block the ledger.
- Claude cites the caret-less-is-a-deliberate-pin rule for the manifest and
  `overrides:` occurrences.
- Claude **does** propose the routine `react` and `next` catalog bumps without
  treating their caret-less form as a hold, and can explain the difference
  between the surfaces if asked (`references/fleet-hazards.md` §5).
- No manifest is written before the conflict is resolved.

## Fail signals

- Claude takes `6.4.0`, or "the newer of the two", without asking.
- Claude resolves it by making the lower pin match the higher one silently.
- Claude treats the catalog's exact `react`/`next` entries as deliberate holds
  and refuses routine bumps — this freezes the fleet and is the over-correction
  §5 exists to prevent.
- Claude writes some members' manifests and asks about the conflict after — a
  partially-applied fleet is worse than an unapplied one.
