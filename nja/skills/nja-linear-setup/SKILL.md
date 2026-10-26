---
name: nja-linear-setup
description: Use once per repo to connect it to Linear — picks the team issues go into, appends LINEAR_TEAM_ID to the repo's .env after asking, and makes sure the Bug, Feature, Improvement, Brainstorm and Small labels exist. Triggers include "set up Linear", "connect this repo to Linear", "configure Linear", or another nja-linear skill reporting that no team is set.
---

# Linear setup

Connect the current repo to one Linear team. Run once per repo.

All Linear calls go through `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh`
(below: "the script"), run from the repo. Never write GraphQL or curl yourself.
Exit codes: `0` ok, `1` usage, `2` not configured, `3` API error; the error is
one sentence on stderr.

## Steps

1. **Check.** Run `the script check`.
   - Exit 2: show the script's message. If the key is missing, tell Carlo to
     add `LINEAR_API_KEY=<his key>` by hand to the `.env` the message names.
     Stop. Never ask for the key, never write it, never print it.
   - Exit 3: show the message and stop.
   - Exit 0 with `"team"` not null: a team is already set. Do not write
     `.env` again; go to step 4.
   - Exit 0 with `"teamError"`: the `LINEAR_TEAM_ID` in `.env` names no team
     this key can see. Show the message and go to step 2; the line appended in
     step 3 wins, because the script reads the last one.
2. **Pick the team.** Run `the script teams`.
   - One team: propose it (key and name).
   - Several: numbered list (key, name). Carlo picks.
3. **Write the team id.** Ask before touching `.env`: show the exact line,
   `LINEAR_TEAM_ID=<id>`, and the file path. The path is the `"env"` value
   from `check`, never a `.env` you pick yourself: in a worktree the key comes
   from the main checkout's `.env`, and a new `.env` in the worktree would hide
   it. Only on a yes, append that one line to the end of that file (add a
   newline first if the file does not end with one). Never rewrite, reorder or remove other lines. Then run
   `the script check` again and confirm the team comes back.
4. **Labels.** Run `the script ensure-labels`. It treats a label as present
   if the team or the workspace has it, and creates missing ones on the team.
5. **Report**, three lines: workspace user (`viewer`), team key, labels ready
   (name the ones created).

No commit. `.env` is never committed.
