---
id: frontend-06-blocknote
title: "BlockNote rich-text fields"
applies_to: frontend
layer: frontend
depends_on:
  - frontend-01-models
  - frontend-04-components
source_files:
  - "packages/nextjs-jsonapi/src/components/forms/FormBlockNote.tsx"
  - "packages/nextjs-jsonapi/src/components/editors/BlockNoteEditorContainer.tsx"
related_docs:
  - frontend-01-models
  - frontend-04-components
  - anti-patterns
enforcement: critical
last_updated: "2026-09-02"
---

# BlockNote rich-text fields

## Contents

- WHEN TO USE
- CRITICAL RULES
- ENFORCEMENT CHECKPOINT
- COMMON MISTAKES
- RELATED FILES
- The lifecycle
- Model
- Editing — inside a form
- Editing — outside a form
- Displaying

---

## WHEN TO USE
Read this file when:
- Adding, editing, or displaying any field that holds rich text (typically named `description`, `content`, or `notes`)
- Writing `rehydrate()` / `createJsonApi()` for such a field
- Deciding whether a rich-text field is "empty"
- Rendering a rich-text field in a card, table cell, detail page, or list

---

## CRITICAL RULES

1. **The blocks array is the ONLY representation.** A BlockNote value is
   `PartialBlock[]` in memory and a JSON string on the wire. There is no third form.
2. **The model converts, and nothing else does.** `JSON.parse(...)` in
   `rehydrate()`, `JSON.stringify(...)` in `createJsonApi()`.
3. **Display goes through `<BlockNoteEditorContainer>`** — never render the text
   yourself.
4. **Editing inside a form goes through `<FormBlockNote>`**; outside a form, use
   `<BlockNoteEditorContainer onChange={...}>` and hold the blocks in state.
5. **Emptiness comes from the editor**, via `FormBlockNote`'s / the container's
   `onEmptyChange` callback. Never inspect the block structure to decide.
6. **NEVER write a blocks→text or text→blocks converter.** No `blocksToText`, no
   `paragraphBlocks`, no `flattenBlocks` in app code. If you are reaching for one,
   rule 3, 4, or 5 is the answer instead.

---

## ENFORCEMENT CHECKPOINT

> **STOP — before writing a helper that touches a BlockNote value:**
> 1. Are you mapping over `block.content` to build a string? **STOP** — use
>    `<BlockNoteEditorContainer>` (rule 3).
> 2. Are you building `[{ type: "paragraph", content: [...] }]` from a plain
>    string? **STOP** — collect the value with an editor (rule 4). A plain
>    `<Input>` feeding a rich-text field is the bug.
> 3. Are you checking `.length === 0` or trimming text to test emptiness?
>    **STOP** — use `onEmptyChange` (rule 5).
> 4. Does a helper like this already exist in the repo? **It is a violation, not
>    a precedent.** Delete it and fix its callers.

---

## COMMON MISTAKES

- A `blocksToText()` / `paragraphBlocks()` utility in a feature folder. Both are
  duplications of what the editor already does; delete them and their callers.
- Storing a rich-text field as a `string` in component state, then converting on
  save. Hold the blocks.
- A plain `<Input>` collecting a value destined for a BlockNote field.
- A `FormBlockNote` inside an `EditorSheet` without `onEmptyChange` and a
  matching `isFormDirty` — the mount-time change marks the form dirty and the
  discard dialog appears on an untouched editor (see "Dirty state inside
  `EditorSheet`").
- Typing the interface getter as `string` — it is `any`, defaulting to `[]`.
- `@IsString()` on the DTO is CORRECT: the wire format is the JSON string the
  model produced. Do not "fix" it to an array validator.

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [01-models.md](01-models.md) | `rehydrate()` / `createJsonApi()` contract |
| [04-components.md](04-components.md) | Base UI rules for the surrounding form |
| [../anti-patterns.md](../anti-patterns.md) | Detection table |

---

## The lifecycle

```
┌─────────────┐  blocks[]  ┌──────────────┐  "[{…}]"  ┌────────────┐
│ FormBlockNote│ ─────────► │ model        │ ────────► │ API        │
│ / Container  │            │ JSON.stringify│           │ @IsString()│
└─────────────┘            └──────────────┘           └────────────┘
       ▲                                                     │
       │        blocks[]        ┌──────────────┐   "[{…}]"   │
       └──────────────────────  │ JSON.parse   │ ◄───────────┘
                                │ in rehydrate │
                                └──────────────┘
```

---

## Model

```typescript
export class Exam extends AbstractApiData implements ExamInterface {
  private _description?: any;

  get description(): any {
    return this._description ?? [];
  }

  rehydrate(data: JsonApiHydratedDataInterface): this {
    super.rehydrate(data);
    this._description = data.jsonApi.attributes.description
      ? JSON.parse(data.jsonApi.attributes.description)
      : undefined;
    return this;
  }

  createJsonApi(data: ExamInput) {
    const response: any = { data: { type: Modules.Exam.name, id: data.id, attributes: {}, relationships: {} } };
    if (data.description !== undefined)
      response.data.attributes.description = JSON.stringify(data.description);
    return response;
  }
}
```

The interface and input both type it as `any` — the blocks array is opaque:

```typescript
export type ExamInput = { id: string; description?: any; /* … */ };
export interface ExamInterface extends ApiDataInterface { get description(): any; }
```

---

## Editing — inside a form

```tsx
// Schema: the value is a blocks array, so it is never string-validated.
const formSchema = z.object({ description: z.any() });

// Defaults: [] when there is nothing yet.
description: exam?.description || [],

<FormBlockNote
  form={form}
  id="description"
  name={t(`features.exam.fields.description.label`)}
  placeholder={t(`features.exam.fields.description.placeholder`)}
  type="exam"
  onEmptyChange={setIsDescriptionEmpty}
/>
```

`FormBlockNote` calls `field.onChange(blocks)` — the form field holds the array.

### Emptiness

```tsx
const [isDescriptionEmpty, setIsDescriptionEmpty] = useState<boolean>(
  !exam?.description || (Array.isArray(exam.description) && exam.description.length === 0),
);
```

Seed it from the record (an empty array means empty), then let `onEmptyChange`
own it from the first keystroke. This initial expression is the ONLY place a
block value is inspected, and it never looks inside a block.

> **Why not just check the text?** BlockNote leaves an empty paragraph behind
> when the user deletes the content, so `description.length > 0` is true for a
> visually empty editor. The editor is the only thing that knows.

### Dirty state inside `EditorSheet`

BlockNote fires `onChange` once on mount for an empty editor (it inserts its
trailing paragraph). react-hook-form marks the field dirty, and `EditorSheet`'s
default check (`Object.keys(form.formState.dirtyFields).length > 0`) then shows
the discard dialog on a form nobody touched. Every editor with a rich-text field
therefore passes its own `isFormDirty` that drops empty rich-text fields, and
re-seeds the emptiness flags in `onReset`:

```tsx
const { dirtyFields } = form.formState;
const isFormDirty = useCallback(() => {
  const dirty: Record<string, unknown> = { ...dirtyFields };
  if (dirty.description && isDescriptionEmpty) delete dirty.description;
  return Object.keys(dirty).length > 0;
}, [dirtyFields, isDescriptionEmpty]);

<EditorSheet
  form={form}
  isFormDirty={isFormDirty}
  onReset={() => {
    setIsDescriptionEmpty(!exam?.description || (Array.isArray(exam.description) && exam.description.length === 0));
    return getDefaultValues();
  }}
  …
>
```

One state, one strip line and one reset line per rich-text field. The generator
emits all of this for every `blocknote` field; a hand-written editor copies it.

When the container is used directly inside a form (a markdown import feeding
`markdownContent`, for example), the same rule applies through the container's
`onChange(content, isEmpty)`: write the field with `shouldDirty: !isEmpty` and
keep the flag in sync.

```tsx
<BlockNoteEditorContainer
  …
  onChange={(content: any, isEmpty: boolean) => {
    setIsContentEmpty(isEmpty);
    form.setValue("content", content, { shouldDirty: !isEmpty });
  }}
/>
```

Reference implementations: wyrdli `ClueEditor.tsx` (two form fields) and
a360ai `OpportunityEditor.tsx` (container-driven `notes`).

---

## Editing — outside a form

No react-hook-form? Hold the blocks in state and let the container write to it.
Note the stable `id`: generate the entity's uuid up front and use it for both the
editor and the record.

```tsx
const [examId] = useState(() => v4());
const [about, setAbout] = useState<any>(undefined);

<BlockNoteEditorContainer
  id={examId}
  type="exam"
  initialContent={about}
  onChange={(content) => setAbout(content)}
  placeholder={t("…")}
  bordered
/>

await ExamService.create({ id: examId, description: about, /* … */ });
```

---

## Displaying

Everywhere — detail pages, cards, list rows, table cells:

```tsx
<Card className="flex w-full flex-col p-4">
  <BlockNoteEditorContainer id={exam.id} type="exam" initialContent={exam.description} />
</Card>
```

Omit the `Card` where the surrounding surface already provides one.

> `BlockNoteEditorContainer` is a `next/dynamic` import with `ssr: false`, so its
> text is NOT in the server-rendered markup. A test must not assert on the
> rendered string — assert on the surrounding element instead.

### Two editors on one form

`FormBlockNote` passes `id={form.getValues("id")}` to the container. Two
BlockNote fields on the same form therefore receive the SAME `id` and differ only
by `type`. Give them distinct `type` values (`"classwork"` / `"homework"`), and
if a form needs two editors of the same `type`, pass a disambiguated id.

---

**Next**: See [04-components.md](./04-components.md) for the Base UI rules around the form.
