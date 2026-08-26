---
id: backend-06-llm-calls
title: "Backend: LLM Calls"
applies_to: backend
layer: agent
depends_on:
  - core-principles
source_files:
  - "packages/nestjs-neo4jsonapi/src/core/llm/services/llm.service.ts"
  - "packages/nestjs-neo4jsonapi/src/agents/responder/nodes/responder.answer.node.service.ts"
  - "packages/nestjs-neo4jsonapi/src/agents/graph/tools/tool.factory.ts"
  - "apps/api/src/features/*/agent/**"
related_docs:
  - backend-04-services
  - anti-patterns
enforcement: critical
last_updated: "2026-08-26"
---

# Backend: LLM Calls

---

## WHEN TO USE
Read this file when:
- Writing ANY `LLMService.call` or `LLMService.streamCall`
- Creating an agent node (LangGraph or otherwise) that talks to a model
- Writing or editing prompt files
- Designing Zod schemas for model input or output

---

## CRITICAL RULES

1. **EVERY call passes BOTH `inputSchema` AND `outputSchema`.** `inputParams`
   without `inputSchema` is a defect, not a style choice: the framework then
   renders each field as a bare `name: value` blob and the model has no way to
   know what any field IS. With `inputSchema`, each field renders as
   `name (description): value` — the meaning travels inline with the data.
2. **Every schema field carries `.describe()`** — input and output alike. The
   description is the contract: for inputs it states the field's epistemic
   status (established fact vs preparation vs candidate list vs instruction);
   for outputs it states exactly what the model must produce there.
3. **System prompts are static doctrine.** No `${}` interpolation — every
   dynamic value travels through `inputParams`. No backtick anywhere in the
   template literal, including comments — a backtick terminates the string and
   crashes the app at import time.
4. **Keep output schemas structurally shallow.** Never nest a complex optional
   object (especially one containing arrays of objects) inside an array item:
   provider-side constrained decoding can stall on it indefinitely — the call
   hangs to timeout across retries and provider fallbacks. Carry a complex
   optional payload as a JSON **string** field and validate it in code with
   `schema.safeParse(JSON.parse(...))`, falling back safely on mismatch.
5. **Attribute every call.** `tokenUsageType` names the feature's cost
   category; `relationshipId`/`relationshipType` pin the spend to an entity;
   `metadata: { agentName, nodeName, ... }` labels dumps and telemetry so two
   calls are never indistinguishable in the logs.
6. **Choose the model knobs deliberately, per call.** `modelWeight`
   (Lite/Normal/Large), `temperature` (low for judgement, higher for
   creation), `timeout`, and — on reasoning-capable models — `reasoningEffort`
   or `disableThinking` for structured calls that must return promptly. Never
   let one call's economy setting leak into a quality-critical call.
7. **Prompt text lives backend-side only,** and prompt examples are abstract —
   never real user data, never entity names from a real tenant.
8. **Degrade gracefully where the product allows it.** A judging/enriching
   call that fails should not always kill the request: catch, log a warning
   with the node name, and return the unenhanced result — but make that a
   conscious, documented choice, not a silent default.
9. **Retry FAILURES, never QUALITY.** A retry is legitimate only when no
   usable output exists: 429/5xx, a timeout, an empty response, a truncated
   or schema-invalid emission. Re-calling because a gate disliked the
   CONTENT of a valid output is banned — if the content is wrong, the
   `inputSchema`, `outputSchema`, or prompt is weak, and THAT is what gets
   fixed. See "Retries — failures yes, quality never" below.

---

## ENFORCEMENT CHECKPOINT

> **STOP — Before committing any `llm.call`, verify:**
> 1. Is `inputSchema` present, with every `inputParams` key present in it and
>    described? If no, **STOP** — the model is reading unlabeled blobs.
> 2. Does any output schema nest an optional object with its own nested
>    structure inside an array? If yes, **STOP** — flatten to a JSON-string
>    field validated in code.
> 3. Does the system prompt contain a backtick or `${`? If yes, **STOP**.
> 4. Are `tokenUsageType`, `relationshipId`/`relationshipType`, and
>    `metadata.agentName`/`metadata.nodeName` set? If no, **STOP**.
> 5. On a reasoning-capable model tier: is `reasoningEffort` a deliberate
>    choice for THIS call? If it was inherited from another call, **STOP**.
> 6. Does any code path re-issue this call because a check disliked the
>    CONTENT of a valid response? If yes, **STOP** — turn the check into a
>    logged detector and move its rule into the schema or prompt (rule 9).

---

## DECISION MATRIX

### Which call

| Question | Answer |
|----------|--------|
| Structured result, request/response? | `call` with `outputSchema` |
| Structured result, streamed to a UI? | `streamCall` (Vercel AI SDK `streamObject`; caller drains `partialObjectStream`) |
| Same prompt + params likely repeated? | add `cacheable: true` (Redis-keyed; a hit skips the provider entirely) |

### Schema design

| Question | Answer |
|----------|--------|
| Field is dynamic data the model reads? | `inputSchema` field with `.describe()` stating what it is and how binding it is |
| Field is a rule or doctrine? | System prompt, not input |
| Output item needs an optional complex payload? | JSON-string field + code-side `safeParse` (rule 4) |
| Output field constrains to a closed set? | `z.enum([...])`, never a described string |

### Input description content

| The field carries… | The description MUST say… |
|----------|--------|
| Recorded fact (history, timeline, state) | that it is established reality and what it is authoritative FOR |
| Authored/prep material (templates, plans, scenario data) | that it is preparation — plans, not events; forbid inferring world-state from it |
| Candidate ids for the output | that ids are copied verbatim or the field omitted; what the list does NOT tell the model |
| A user instruction | what it outranks and what it never overrides |

### Tools

| Question | Answer |
|----------|--------|
| Model needs to look up entities before writing? | Bind the graph catalog tools: inject the tool builders, `.build(ctx, recorder)` each with a `UserContext` (companyId, userId, userModuleIds, scopeId, scopeType), pass `tools` + a bounded `maxToolIterations` |
| User has no readable modules / identity missing? | Skip tools and proceed on static grounding (mirror the responder's `skipped_no_modules` path) — never fail the request for it |
| Timeout with tools bound? | Raise it: one call now spans several model rounds plus tool executions |

---

## Retries — failures yes, quality never

Two things wear the name "retry", and they must never be confused.

**A FAILURE retry re-asks a question that was never answered.** The provider
returned a 429 or a 5xx, the call timed out, the response was empty (no
tokens, no finish reason), or the emission was truncated / failed schema
decoding. No usable output exists; re-issuing the SAME input is correct,
because the input was never the problem. Bound the attempts, log every one
(a silently-absorbed empty response is how a provider outage hides for
fourteen rounds), and fall through to the degraded path of rule 8 when the
budget is spent.

**A QUALITY retry re-rolls an answer someone disliked.** The call returned a
valid, schema-conforming output; a gate inspected the content, judged it
wrong (an echoed direction, a contradiction, a rule violation), and the code
called the model again hoping for better. THIS IS BANNED. Same input, same
model, same weak contract — the same class of output comes back, and the
product pays twice for a lesson it refuses to learn. A quality gate that
triggers a re-call is an admission, in code, that the schemas and the prompt
do not hold — so fix THEM:

- **Field contracts inline with the data.** A rule in a `.describe()` sits
  next to the value it governs; a rule in the system prompt sits 2,000
  tokens away and loses.
- **Scaffold fields, in schema order.** Constrained decoding fills an object
  in order: a required field placed BEFORE the answer forces the model to
  articulate the constraint before it may commit (state the `condition`
  before the verdict, name the one `act` before the direction). Measured:
  the scaffold held 3/3 where the written prohibition held 1/3.
- **Shapes that make the failure unrepresentable.** Required fields (an
  optional field is a field the grammar cannot force), enums for closed
  sets, flat array items, bounded arrays, explicit `maxTokens`.
- **Code-side merges that survive a bad emission.** An omission carries
  forward instead of deleting; a malformed section is dropped alone while
  the others apply.

**What becomes of the gate?** It survives as a DETECTOR: it logs the
violation with the evidence, counts it as a degradation the operator can
see, and ships the output anyway. The counter is the measurement the
philosophy needs — a non-zero count says a contract is still weak, and the
fix is the contract, never a second call. A detector that quietly re-rolls
is not a detector; it is the weak prompt's life-support machine.

**The boundary case:** an output that is structurally unusable — a required
beat missing, an array short of its contract, an id that resolves to nobody
— is a FAILURE (nothing downstream can consume it), and re-asking is
legitimate. When such a retry re-issues the call, it carries the rejection
back as a named negative example in the input ("beat 2 was empty") — a
byte-identical re-ask teaches the model nothing.

---

## COMMON MISTAKES

| Mistake | Consequence | Correct approach |
|---------|-------------|------------------|
| `inputParams` without `inputSchema` | Model conflates fields — reads prep data as world-state, candidate lists as facts | Always pass both; describe every field (rule 1) |
| Semantics only in the system prompt | Rules 2000 tokens from the data get ignored or parroted | Put the field's meaning in its `.describe()`, inline with the value |
| Nested optional object inside an output array item | Constrained decoding stalls; call hangs to timeout across provider fallbacks | JSON-string field + code-side validation |
| Backtick in a prompt template literal (even a comment) | String terminates; app crashes at import | No backticks anywhere in prompt files; guard with a test |
| `${}` in a system prompt | Untracked injection of dynamic data; cache-buster | All dynamic values via `inputParams` |
| Missing attribution/metadata | Indistinguishable calls in dumps, unattributed spend | `tokenUsageType` + relationship + `metadata.agentName/nodeName` |
| Economy `reasoningEffort` left on a quality-critical call | Rule-following and judgement degrade silently | Set the knob per call, on purpose |
| Real tenant data as prompt examples | Leaks user content into every future call | Abstract examples only |
| Re-calling because a gate disliked valid content | Pays twice for the same weak contract; the model returns the same class of output | Fix the schema/prompt (describes, scaffold fields, shapes); demote the gate to a logged, counted detector |
| Swallowing failure retries silently | An empty-response streak or provider outage hides behind "eventual success" | Log and count every failure retry; bound attempts; degrade loudly (rule 8) |
| Byte-identical re-ask after a structural rejection | The model repeats the mistake it was not told about | Carry the rejection back as a named negative example in the input |

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [04-services.md](04-services.md) | The service/node that owns the call |
| [../anti-patterns.md](../anti-patterns.md) | General review checklist |

---

## The canonical call

Mirrors `agents/responder/nodes/responder.answer.node.service.ts` (the
reference implementation) and the app-side agent nodes that follow it.

```typescript
// 1. The input contract — every field the model reads, typed and described.
//    Descriptions carry the field's EPISTEMIC STATUS, because the model
//    cannot tell reality from preparation on its own.
const inputSchema = z.object({
  history: z
    .string()
    .describe(
      "ESTABLISHED REALITY. What actually happened, oldest first. The end of the last entry is the ONLY source of the current position.",
    ),
  prepared_material: z
    .string()
    .describe(
      "PREPARATION DATA. Authored plans, not events that occurred. Never infer anyone's current state or whereabouts from this.",
    ),
  candidate_ids: z
    .string()
    .describe("Ids and names ONLY. States nothing else about these entities — look them up before writing about them."),
  steer: z.string().describe("Optional operator instruction; outranks preferences, never the rules."),
});

// 2. The output contract — .describe() on every field; enums for closed sets;
//    complex optional payloads as JSON strings (see rule 4).
const outputSchema = z.object({
  items: z.array(
    z.object({
      title: z.string().describe("Short label shown to the user"),
      kind: z.enum(["primary", "secondary"]),
      correctionJson: z
        .string()
        .optional()
        .describe("Only when correcting: the corrected item as ONE JSON object string with every field present"),
    }),
  ),
});

// 3. The call — schemas + params + static prompt + knobs + attribution.
const result = await this.llm.call<z.infer<typeof outputSchema>>({
  inputSchema,
  inputParams: { history, prepared_material, candidate_ids, steer },
  outputSchema,
  systemPrompts: [STATIC_DOCTRINE_PROMPT], // no backticks, no ${} — ever
  temperature: 0.7,                        // judgement passes: ~0.2
  timeout: 90_000,
  modelWeight: ModelWeight.Large,
  reasoningEffort: "low",                  // deliberate, per call
  tokenUsageType: "my_feature",
  relationshipId: campaignId,
  relationshipType: "Campaign",
  metadata: { agentName: "my-feature", nodeName: "propose" },
});

// 4. Code-side validation of any JSON-string payload.
const corrected = parseWith(itemSchema, result.items[0]?.correctionJson); // safeParse + fallback
```

### Binding lookup tools

```typescript
const ctx: UserContext = { companyId, userId, userModuleIds, scopeId, scopeType: "campaigns" };
const recorder: ToolCallRecord[] = [];
const tools = [
  this.resolveTool.build(ctx, recorder),
  this.readTool.build(ctx, recorder),
  this.traverseTool.build(ctx, recorder),
];
// userModuleIds empty → run WITHOUT tools rather than failing (responder precedent).
await this.llm.call({ ...params, ...(tools.length ? { tools, maxToolIterations: 6 } : {}) });
```

### Guard tests every prompt file gets

```typescript
it("contains no backticks (template-literal safety)", () => {
  expect(PROMPT.includes("`")).toBe(false);
});
it("contains no dynamic placeholders (data travels via inputParams)", () => {
  expect(PROMPT).not.toMatch(/\$\{/);
});
```

---

**Next**: [template.md](./template.md) for entity scaffolding; [04-services.md](./04-services.md) for the owning service.
