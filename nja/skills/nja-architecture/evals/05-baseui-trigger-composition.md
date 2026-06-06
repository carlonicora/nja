# Eval 05 — Base UI button-trigger composition

## Setup (paste into Claude)

> In any feature container under `apps/web/src/features/`, add a Popover whose trigger is a styled icon button. The button should be the Popover's anchor and respond to keyboard activation.

## Expected behavior (before writing code)

1. Claude invokes the `nja-architecture` skill.
2. The routing table matches `apps/web/src/features/*/components/**`.
3. Claude reads `references/frontend/04-components.md`.

## Pass criteria

- The trigger uses Base UI's `render` prop for composition — `<Popover.Trigger render={(props) => <IconButton {...props} />} />` or equivalent.
- No `asChild` prop appears anywhere in the diff.
- No `<Button>` (the styled component) is wrapped INSIDE a `<Popover.Trigger>` — the trigger renders into the button via `render`.
- Imports are from Base UI (`@base-ui-components/react/...`), not Radix.

## Fail signals

- `<Popover.Trigger asChild><Button /></Popover.Trigger>` (the Radix pattern, not the Base UI pattern).
- A nested `<Button>` inside `<Popover.Trigger>` without `render`.
- Imports from `@radix-ui/...`.
