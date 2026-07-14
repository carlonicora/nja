---
id: frontend-05-typography
title: "Typography Roles (text styling)"
applies_to: frontend
layer: frontend
depends_on:
  - frontend-04-components
source_files:
  - "apps/web/docs/UI.md"
  - "packages/nextjs-jsonapi/src/components/typography/"
related_docs:
  - frontend-04-components
enforcement: critical
last_updated: "2026-07-14"
---

# Typography Roles — one recipe per text role

---

## WHEN TO USE
Read this file when:
- Styling ANY text in `apps/web` or `packages/nextjs-jsonapi` (headings, labels, captions, errors, links, numbers)
- Adding a heading, title, section header, or uppercase label
- Choosing a text size, weight, or color class

The app-local copy of this system lives at `apps/web/docs/UI.md` — if the two disagree,
the app copy wins (its token values track the app's `globals.css`).

---

## CRITICAL RULES

1. **Every piece of text belongs to exactly one of the 17 roles below.** Recipes are verbatim class strings; do not invent variations.
2. **NEVER use raw palette colors on text** (`gray/neutral/slate/zinc/red/green/emerald/yellow/amber/orange/blue`) — always tokens (`text-muted-foreground`, `text-primary`, `text-destructive`, `text-success`, `text-warning`). Marketing pages are the sole exemption.
3. **NEVER write a raw `<h1>`** — page titles go through `ContentTitle` (lists/top pages) or `RoundPageContainerTitle` (detail heroes). Settings/admin sub-pages rendered inside a settings pane use the muted eyebrow pattern instead (see role 3 note).
4. **Anything STYLED as a header must BE a heading element** — use `SectionHeader` / `MicroLabel` (from `@carlonicora/nextjs-jsonapi/components`), never a styled `div`/`span`.
5. **NEVER use `font-mono`** (no monospace font is loaded) — numeric data uses `tabular-nums`, right-aligned in tables.
6. **`/relaxed` line-height ONLY where text wraps**; single-line chrome is plain `text-xs`. Worked example: Tabs — trigger (single-line) `text-xs`, panel (wrapping) `text-xs/relaxed`.
7. **Field labels/help/errors ONLY via `FormFieldWrapper`** — never a raw `<Label>` with size overrides. Required marker: `<span className="ml-1 text-destructive">*</span>`.
8. **Status pills use `Badge`** (soft variants — `softGreen`, `softRed`, `softBlue`, `softYellow`, `softGray`, `softOrange`, `softAmber` — for pastel looks); never hand-rolled `bg-*-100 text-*-800` spans.
9. **The Input/Textarea `text-sm md:text-xs/relaxed` pair is the ONLY sanctioned responsive text.**

---

## THE 17 ROLES

| # | Role | Recipe | Enforced by | Use when |
|---|------|--------|-------------|----------|
| 1 | Page title | `text-primary text-3xl font-semibold` | `ContentTitle` (package) | The single main title of a list or top-level page. |
| 2 | Hero title | `text-primary text-xl font-semibold` | `RoundPageContainerTitle` | The entity name in a detail page's hero header. |
| 3 | Page eyebrow | `text-muted-foreground text-xl font-light` | same components | The muted kicker line above a page/hero title. ALSO the title style for settings/admin sub-pages rendered inside a settings pane (do NOT give those a role-1 title — the pane's breadcrumb/table already carries the name). |
| 4 | Section header | `text-lg font-semibold` on a real `h2`/`h3` | `FormSection` / `SectionHeader` | A heading that opens a section or group within a page or form. |
| 5 | Panel title | `text-sm font-medium` | Card/Dialog/Sheet/Alert/EmptyState primitives | The title slot of a contained surface. |
| 6 | Micro-label | `text-muted-foreground text-xs font-semibold tracking-wider uppercase` | `MicroLabel` | A tiny uppercase label that categorises the content beneath/beside it. |
| 7 | Body | `text-sm` (+ `leading-relaxed` long-form) | inline | Default running text — paragraphs, descriptions, content. |
| 8 | UI chrome | `text-xs` single-line; `text-xs/relaxed` only where text wraps | primitives | Menu items, tab triggers, tooltips, metadata rows. |
| 9 | Field label | `text-xs/relaxed font-medium`; asterisk `ml-1 text-destructive` | `Label`/`FieldLabel` via `FormFieldWrapper` | The label above/beside a form input. |
| 10 | Helper text | `text-muted-foreground text-xs/relaxed` | `FieldDescription` | Guidance under a form field. |
| 11 | Error text | `text-destructive text-xs/relaxed` | `FieldError` | A validation error attached to a field. |
| 12 | Caption / detail-label | `text-muted-foreground text-xs` | inline / `DetailField` | The muted label of a read-only detail pair, or any small caption. |
| 13 | Detail value | `text-sm` | `DetailField` | The value half of a read-only label/value pair. |
| 14 | Link | `text-primary font-medium hover:underline` | package `Link` | Any inline navigational text link. |
| 15 | Numeric | `text-xs tabular-nums text-right` | inline | Numbers, currency, durations in table cells or aligned columns. |
| 16 | Semantic status | `text-success` / `text-warning` / `text-destructive` | tokens | Text whose color conveys state. |
| 17 | Input text | `text-sm md:text-xs/relaxed` | Input/Textarea | Text the user types inside an input/textarea. |

Component APIs (all from `@carlonicora/nextjs-jsonapi/components`):

```tsx
SectionHeader: React.ComponentProps<"h3"> & { level?: 2 | 3 }              // default h3
MicroLabel:    React.ComponentProps<"h4"> & { as?: "h3" | "h4" | "span" }  // default h4
DetailField:   { label: string; value?: ReactNode; horizontal?: boolean; labelWidth?: string }
```

---

## TEXT-COLOR TOKENS

Reference values (a360ai `apps/web/src/app/globals.css`; per-app values may differ — check the app's `docs/UI.md`):

| Token | Class | Light | Dark |
|-------|-------|-------|------|
| `foreground` | (default via `body`) | `oklch(0.145 0 0)` | `oklch(0.985 0 0)` |
| `muted-foreground` | `text-muted-foreground` | `oklch(0.556 0 0)` | `oklch(0.708 0 0)` |
| `primary` | `text-primary` | `oklch(0.61 0.11 222)` | `oklch(0.71 0.13 215)` |
| `destructive` | `text-destructive` | `oklch(0.58 0.22 27)` | `oklch(0.704 0.191 22.216)` |
| `success` | `text-success` | `oklch(0.52 0.13 155)` | `oklch(0.72 0.15 155)` |
| `warning` | `text-warning` | `oklch(0.6 0.13 70)` | `oklch(0.78 0.14 80)` |

---

## COMMON MISTAKES

| Mistake | Correct approach |
|---------|------------------|
| Styled `div`/`span` doing a header's job | `SectionHeader` / `MicroLabel` (real heading elements) |
| Raw `<h1 className="text-2xl font-bold">` | `ContentTitle` / `RoundPageContainerTitle`; role-3 eyebrow for settings sub-pages |
| Role-1 page title on a settings/admin sub-page | Role-3 eyebrow (`text-muted-foreground text-xl font-light`) — the giant primary title triples up with breadcrumb + table title |
| `text-gray-500` / `text-green-600` / `text-red-600` on text | `text-muted-foreground` / `text-success` / `text-destructive` |
| `font-mono` for IDs/amounts | `tabular-nums` (no mono font is loaded) |
| Hand-rolled pastel pill `bg-green-100 text-green-800` | `<Badge variant="softGreen">` |
| Raw `<Label className="text-sm">` in a form | `FormFieldWrapper` (label renders `text-xs/relaxed font-medium`) |
| Ad-hoc `<p className="text-sm text-destructive">` error | `FieldError` / `text-destructive text-xs/relaxed` |

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [04-components.md](04-components.md) | Base UI composition rules for the components these roles live in |
| `apps/web/docs/UI.md` | The app-local source of truth (token values track globals.css) |
| `packages/nextjs-jsonapi/src/components/typography/` | SectionHeader / MicroLabel / DetailField source |
