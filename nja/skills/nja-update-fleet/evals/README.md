# Evals — nja-update-fleet skill

Manual replay scenarios that verify Claude follows this skill's rules. Each
`NN-<name>.md` contains **Setup**, **The prompt**, **Pass criteria**, and
**Fail signals**.

## How to run

1. Open a fresh Claude Code session (`/clear`, or a new terminal).
2. Put the machine into the state the scenario's **Setup** describes.
3. Paste **The prompt** into Claude.
4. Observe whether Claude follows the phases and gates before acting.
5. Check the outcome against **Pass criteria**.
6. Revert any state changes made for the scenario — these are diagnostic, not
   real runs. In particular: never let a scenario reach a real F4 push.

## When to run

- After modifying `SKILL.md` (especially the phase table or `description`).
- After modifying `nja-fleet-survey.sh`, `nja-fleet-waves.sh`,
  `nja-deps-sweep.sh`, or `references/fleet-hazards.md`.
- Before bumping any version that touches this skill.

## v1 scenarios (5)

| # | File | Tests |
|---|---|---|
| 1 | `01-ineligible-member.md` | F0 gate; explicit exclusion; no silent roster change |
| 2 | `02-conflicting-pins.md` | F1 conflict class; refuse to pick; catalog vs manifest exactness |
| 3 | `03-ci-failure.md` | F4 incident handling; no app repo touched |
| 4 | `04-one-member-red.md` | F6 differential attribution; one baseline, not N |
| 5 | `05-boot-exit-4.md` | F6 queue abort; no name-pattern kill; no port freeing |
