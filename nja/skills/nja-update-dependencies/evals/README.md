# Evals — nja-update-dependencies skill

Manual replay scenarios that verify Claude follows this skill's rules. Each `NN-<name>.md` file contains:

- **Setup** — the state of the repo (and any tools) before the prompt is given
- **The prompt** — a one-line task to give Claude in a fresh Code session
- **Pass criteria** — concrete checks against what Claude does and says

## How to run

1. Open a fresh Claude Code session in the repo (`/clear` an existing one or open a new terminal).
2. Put the repo into the state the scenario's **Setup** describes.
3. Paste the **the prompt** text into Claude.
4. Observe whether Claude follows the skill's phases and gates before acting.
5. Check the outcome against **Pass criteria**.
6. Revert any repo state changes made for the scenario after replay (these are diagnostic, not real runs).

## When to run

- After modifying `SKILL.md` (especially the phase table or `description`).
- After modifying any of `nja-deps-sweep.sh`, `nja-deps-doctor.sh`, `nja-dev-boot.sh`, or `references/hazards.md`.
- Before bumping any version that touches this skill.

## v1 scenarios (4)

| # | File | Tests |
|---|---|---|
| 1 | `01-dirty-tree.md` | Phase 0 gate; no self-service stashing; no sweep runs on a dirty tree |
| 2 | `02-held-major.md` | Phase 1 hold re-testing; `AskUserQuestion` before any major; no unilateral bump |
| 3 | `03-doctor-duplicate.md` | Phase 4 gate; exact-version override proposal; hazards.md §1 citation |
| 4 | `04-boot-failure.md` | Phase 6 lazy baseline; routing a fatal boot pattern to hazards.md §1 |
