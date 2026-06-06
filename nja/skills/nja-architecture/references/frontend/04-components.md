---
id: frontend-04-components
title: "UI Components (Base UI)"
applies_to: frontend
layer: frontend
depends_on:
  - core-principles
source_files:
  - "packages/nextjs-jsonapi/src/shadcnui/ui/"
related_docs:
  - anti-patterns
enforcement: critical
last_updated: "2026-03-30"
---

# UI Components — Base UI (NOT Radix)

---

## WHEN TO USE
Read this file when:
- Building any UI that uses Popover, Dialog, DropdownMenu, Select, Combobox, Tooltip, or similar interactive components
- Working with trigger components, floating elements, or component composition
- Integrating Button or other interactive elements inside trigger components

---

## CRITICAL RULES

1. **This project uses Base UI** — NOT Radix. All shadcn-style components wrap `@base-ui/react` primitives.
2. **NEVER use `asChild`** — Base UI does not support it. Use the `render` prop instead.
3. **NEVER wrap `<Button>` inside a trigger** — Triggers render their own `<button>` element. Wrapping creates nested `<button>` elements (invalid HTML, causes hydration errors).
4. **ALWAYS use `render` prop for element composition** — When a Base UI primitive needs to render as a different component, pass it via `render`.
5. **Floating elements require `Positioner`** — Base UI separates positioning (`Positioner`) from content (`Popup`). Both are required.

---

## ENFORCEMENT CHECKPOINT

> **STOP — Before writing any component that uses a trigger or floating element:**
> 1. Are you using `asChild`? If yes, **STOP** — replace with `render` prop.
> 2. Are you wrapping `<Button>` inside `<PopoverTrigger>`, `<DialogTrigger>`, `<DropdownMenuTrigger>`, or any trigger? If yes, **STOP** — use `render` prop or styled `<div>`.
> 3. Are you using Radix component names like `DialogContent`, `DialogOverlay`, `Sub`, `SubTrigger`? If yes, **STOP** — check the actual wrapper exports below.

---

## THE `render` PROP

Base UI's composition mechanism. Instead of Radix's `asChild`, Base UI uses `render` to replace the default element:

```typescript
// ❌ WRONG — Radix pattern (asChild does not exist in Base UI)
<DialogClose asChild>
  <Button variant="ghost">Close</Button>
</DialogClose>

// ✅ CORRECT — Base UI render prop
<DialogClose render={<Button variant="ghost" size="icon-sm" />}>
  <XIcon />
</DialogClose>
```

Real examples from this codebase:

```typescript
// Dialog close button (dialog.tsx)
<DialogPrimitive.Close
  render={<Button variant="ghost" className="absolute top-2 right-2" size="icon-sm" />}
>
  <XIcon />
  <span className="sr-only">Close</span>
</DialogPrimitive.Close>

// Combobox clear button (combobox.tsx)
<ComboboxPrimitive.Clear
  render={<InputGroupButton variant="ghost" size="icon-xs" />}
>
  <XIcon className="pointer-events-none" />
</ComboboxPrimitive.Clear>

// Select icon (select.tsx)
<SelectPrimitive.Icon
  render={<ChevronDownIcon className="text-muted-foreground size-3.5" />}
/>
```

---

## TRIGGER COMPOSITION

Trigger components (`PopoverTrigger`, `DialogTrigger`, `DropdownMenuTrigger`, `AlertDialogTrigger`, etc.) render their own `<button>` element. Putting a `<Button>` inside creates nested `<button>` — invalid HTML.

### Pattern A: Styled content inside trigger (most common)

Use when the trigger doesn't need Button styling:

```typescript
// ✅ CORRECT — div inside trigger, Base UI provides the <button>
<PopoverTrigger className="w-full">
  <div className="flex w-full items-center gap-2 rounded-md border px-3 py-2 text-sm">
    <SearchIcon className="size-4" />
    <span>Search...</span>
  </div>
</PopoverTrigger>
```

### Pattern B: Trigger with `render` prop

Use when you want the trigger itself to render as a Button:

```typescript
// ✅ CORRECT — render prop replaces the trigger's default <button>
<PopoverTrigger render={<Button variant="outline" size="sm" />}>
  <FilterIcon className="h-3 w-3" />
  Filter
</PopoverTrigger>
```

### What NOT to do

```typescript
// ❌ WRONG — nested <button> elements, causes hydration error
<PopoverTrigger>
  <Button variant="outline" size="sm">
    <FilterIcon className="h-3 w-3" />
    Filter
  </Button>
</PopoverTrigger>

// ❌ WRONG — asChild does not exist in Base UI
<PopoverTrigger asChild>
  <Button variant="outline" size="sm">Filter</Button>
</PopoverTrigger>
```

This applies to ALL trigger and close components:
- `PopoverTrigger`, `DialogTrigger`, `DialogClose`
- `AlertDialogTrigger`, `AlertDialogAction`, `AlertDialogCancel`
- `DropdownMenuTrigger`
- `ComboboxTrigger`
- `TooltipTrigger`
- `CollapsibleTrigger`
- `AccordionTrigger`

---

## FLOATING ELEMENT STRUCTURE

Base UI requires an explicit `Positioner` between `Portal` and `Popup`. This is different from Radix, where `Content` handles both positioning and rendering.

```
Root
├── Trigger
└── Portal
    └── Positioner  ← handles side, align, offset
        └── Popup   ← the visible content
```

This pattern is used by: Popover, DropdownMenu, Select, Combobox, Tooltip, ContextMenu, HoverCard, NavigationMenu.

Example from this codebase (popover.tsx):

```typescript
<PopoverPrimitive.Portal>
  <PopoverPrimitive.Positioner
    align={align}
    alignOffset={alignOffset}
    side={side}
    sideOffset={sideOffset}
  >
    <PopoverPrimitive.Popup className={cn("...", className)} {...props} />
  </PopoverPrimitive.Positioner>
</PopoverPrimitive.Portal>
```

> **Note:** The project's wrapper components (e.g., `PopoverContent`, `DialogContent`, `DropdownMenuContent`) already handle this structure internally. You only need to know this when reading or modifying the component definitions in `packages/nextjs-jsonapi/src/shadcnui/ui/`.

---

## DATA ATTRIBUTES FOR STYLING

Base UI uses `data-*` attributes for state-based styling, not `aria-*`:

```typescript
// Base UI state attributes
data-open          // element is open
data-closed        // element is closed
data-active        // element is active
data-checked       // checkbox/radio is checked
data-disabled      // element is disabled

// Positioning attributes
data-[side=bottom]
data-[side=top]
data-[side=left]
data-[side=right]

// Example usage in className
className="data-open:animate-in data-closed:animate-out data-[side=bottom]:slide-in-from-top-2"
```

---

## COMPONENT PRIMITIVE MAPPING

Each project wrapper maps to a Base UI primitive:

| Wrapper Component | Base UI Import | Primitive |
|---|---|---|
| Popover | `@base-ui/react/popover` | `Popover` |
| Dialog, Sheet | `@base-ui/react/dialog` | `Dialog` |
| AlertDialog | `@base-ui/react/alert-dialog` | `AlertDialog` |
| DropdownMenu | `@base-ui/react/menu` | `Menu` |
| ContextMenu | `@base-ui/react/context-menu` | `ContextMenu` |
| Select | `@base-ui/react/select` | `Select` |
| Combobox | `@base-ui/react` | `Combobox` |
| Tooltip | `@base-ui/react/tooltip` | `Tooltip` |
| Accordion | `@base-ui/react/accordion` | `Accordion` |
| Collapsible | `@base-ui/react/collapsible` | `Collapsible` |
| Tabs | `@base-ui/react/tabs` | `Tabs` |
| Checkbox | `@base-ui/react/checkbox` | `Checkbox` |
| Switch | `@base-ui/react/switch` | `Switch` |
| Slider | `@base-ui/react/slider` | `Slider` |
| Toggle | `@base-ui/react/toggle` | `Toggle` |
| NavigationMenu | `@base-ui/react/navigation-menu` | `NavigationMenu` |
| HoverCard | `@base-ui/react/preview-card` | `PreviewCard` |
| Button | `@base-ui/react/button` | `Button` |
| Input | `@base-ui/react/input` | `Input` |

**Non-Base UI components:** Command (`cmdk`), Calendar (`react-day-picker`), Carousel (`embla-carousel`), Chart (`recharts`).

---

## RADIX → BASE UI NAMING DIFFERENCES

If you catch yourself using these names, you're using Radix patterns:

| Radix Name | Base UI Equivalent |
|---|---|
| `asChild` | `render` prop |
| `DialogOverlay` | `Dialog.Backdrop` (wrapped as `DialogOverlay` in this project) |
| `DialogContent` (single component) | `Dialog.Popup` (wrapped as `DialogContent` which includes Portal + Backdrop) |
| `Sub` / `SubTrigger` | `SubmenuRoot` / `SubmenuTrigger` |
| `Content` (handles positioning) | `Positioner` + `Popup` (split concerns) |
| `ScrollArea` inside Select | `Select.ScrollUpArrow` / `Select.ScrollDownArrow` |
| `ItemIndicator` (inline) | Separate `CheckboxItemIndicator` / `RadioItemIndicator` components |

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [anti-patterns.md](../anti-patterns.md) | Common mistakes to avoid |
| [03-services.md](03-services.md) | API communication patterns |
| Component source | `packages/nextjs-jsonapi/src/shadcnui/ui/` |
