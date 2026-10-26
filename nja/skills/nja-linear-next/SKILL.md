---
name: nja-linear-next
description: Use when Carlo wants to see his open Linear issues and pick one to work on. Lists the repo team's open issues in a fixed order, asks which one, and hands the pick to nja-linear-start. Never recommends. Triggers include "what's next", "what should I work on", "show my issues".
---

# Linear next

Show the open issues, let Carlo pick, start the pick.

All Linear calls go through `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh`
(below: "the script"), run from the repo. Never write GraphQL or curl yourself.
Exit codes: `0` ok, `1` usage, `2` not configured, `3` API error.

## Steps

1. **Check.** Run `the script check`. Exit 2 or 3: show the script's message
   and stop. `"team": null`: tell Carlo to run `nja-linear-setup` and stop.
2. **List.** Run `the script list-open`. Empty list: say so and stop.
3. **Sort**, in this order:
   1. state `In Progress`, then `In Review`, then everything else;
   2. priority Urgent, High, Medium, Low, then none (`priority` 1, 2, 3, 4,
      then 0);
   3. oldest `createdAt` first.
4. **Show** a numbered list, one row per issue:

   ```
   1. WYR-12  Fix scene drag losing position  ·  High  ·  In Progress  ·  Small
   2. WYR-9   Session recap email  ·  Medium  ·  Todo  ·  Brainstorm (Spec yes, Plan no)
   ```

   Columns: identifier, title, `priorityLabel`, state, Brainstorm or Small
   (from `labels`; write `—` if neither). For Brainstorm issues add whether a
   `Spec` and a `Plan` document exist (from `documents`).
5. **Ask which one.** Do not recommend, rank or comment on the list.
6. **On a pick**, invoke `nja-linear-start` with that identifier.
