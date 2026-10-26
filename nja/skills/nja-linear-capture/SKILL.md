---
name: nja-linear-capture
description: Use when something found or wanted during the current work should become a Linear issue instead of being done now. Drafts the title, description, priority and kind from the conversation and the code, asks one confirming question, then creates the issue in Todo. Triggers include "save this as a task", "add this to Linear", "create an issue for this", "log this for later".
---

# Linear capture

Turn a finding into a Linear issue with one question, then go back to what
you were doing. Never start work on the issue.

All Linear calls go through `${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh`
(below: "the script"), run from the repo. Never write GraphQL or curl yourself.
Exit codes: `0` ok, `1` usage, `2` not configured, `3` API error.

## Steps

1. **Check.** Run `the script check`. Exit 2 or 3: show the script's message
   and stop. `"team": null`: tell Carlo to run `nja-linear-setup` and stop.
2. **Draft** from the conversation and the code you have read:
   - **Title:** imperative, specific, under ~70 characters.
   - **Description**, markdown, these sections in this order:
     - `## What` — what was found or is wanted.
     - `## Where` — file:line, page URL or record, as relevant.
     - `## Why it matters` — the consequence of leaving it.
     - `## Reproduce` — numbered steps. Bugs only; omit otherwise.
     - `## Done when` — the observable outcome.
     - `## Found while` — one line on the task that surfaced it.
   - **Priority:** Urgent, High, Medium, Low or None, with a one-line reason.
   - **Kind:** `Bug`, `Feature` or `Improvement`.
3. **Ask one question.** Show the title, the full description, the priority
   with its reason, and the kind, and ask: Brainstorm or Small? Carlo
   confirms or edits in the same answer. Apply his edits; do not ask again.
4. **Create.** Write the description to a temp file (`mktemp`), then:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh" create-issue \
     --title "<title>" --description-file "<tmpfile>" \
     --priority <N> --label <Kind> --label <Brainstorm|Small>
   ```

   `N`: 1 Urgent, 2 High, 3 Medium, 4 Low, 0 None. The issue lands in Todo.
   Exit 3 naming an unknown label: tell Carlo to run `nja-linear-setup`.
5. **Report** one line: identifier and URL. Then resume the interrupted task.
