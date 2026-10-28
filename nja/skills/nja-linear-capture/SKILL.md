---
name: nja-linear-capture
description: Use when something found or wanted during the current work should become a Linear issue instead of being done now. Drafts the title, description, priority and kind from the conversation and the code, asks one confirming question, then creates the issue in Todo, attaching the spec and plan as documents when the work already has them. Triggers include "save this as a task", "add this to Linear", "create an issue for this", "log this for later".
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
   - **Documents:** a spec or plan file this work already has: one written or
     read in this conversation, or one Carlo names (for example "use the
     current spec and plan"). Only files that exist on disk. When there is a
     spec or plan, the issue is Brainstorm; do not ask.
   - **Images:** every image Carlo gave with the request (a pasted screenshot's
     file path, or one he names). Each one is attached; never skip one.
3. **Ask one question.** Show the title, the full description, the priority
   with its reason, the kind, and the files that will be attached as `Spec`
   and `Plan` (if any), the images to attach (if any), and ask: Brainstorm or Small? (Skip that part when
   there are documents.) Carlo confirms or edits in the same answer. Apply his
   edits; do not ask again.
4. **Create.** Write the description to a temp file (`mktemp`), then:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh" create-issue \
     --title "<title>" --description-file "<tmpfile>" \
     --priority <N> --label <Kind> --label <Brainstorm|Small>
   ```

   `N`: 1 Urgent, 2 High, 3 Medium, 4 Low, 0 None. The issue lands in Todo.
   Exit 3 naming an unknown label: tell Carlo to run `nja-linear-setup`.
5. **Attach documents**, if step 2 found any. For each file, write a temp
   file whose first line is `Source: <repo-relative path>`, then a blank line,
   then the file's content verbatim, and run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh" upsert-doc <ID> \
     --title <Spec|Plan> --content-file "<tmpfile>"
   ```

   A plan still being written is attached as it stands; `nja-writing-plan`
   replaces it when the plan is saved, because the identifier is now in
   context.
6. **Attach images**, if step 2 found any. For each one:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/nja-linear.sh" attach-image <ID> \
     --file "<path>" --alt "<what it shows>"
   ```

   It uploads the file and appends it to the end of the description. Only
   png, jpeg, gif and webp are accepted; exit 1 on another type: tell Carlo
   the file was not attached and why.
7. **Report** one line: identifier, URL, and the documents and images attached. Then
   resume the interrupted task. Capturing never starts or delegates the work.
