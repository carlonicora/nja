# Working discipline

Five cross-cutting rules. They are not about this stack — they are about how work gets done in it. Read them when you are about to claim something is finished, when you are about to fix a bug, when you are designing a type, when you are writing an instruction for the second time, or when more than one agent is working in the same tree.

The architecture rules stop you writing the wrong code. These stop you shipping the wrong work.

---

## 1. Prove it works

**Verify against the real artifact. Never against a proxy, a self-report, or "it compiles".**

Unverified work has unknown correctness. Indirect verification — file timestamps, a green build, an agent's own summary, a screenshot from an earlier run — feels cheaper than direct observation. Acting on a wrong inference costs far more than checking the source.

`pnpm lint`, `pnpm build` and `pnpm test` are necessary and **not sufficient**. They prove the code compiles and that the assertions someone wrote still hold. They prove nothing about whether the feature does what was asked.

After completing any task, ask: how do I prove this actually works?

1. Build it. Necessary, not sufficient.
2. Run it and exercise the actual user path.
3. Check the full chain. Does data reach Neo4j, come back through the serialiser, rehydrate in the model, and render?
4. For anything crossing the API boundary, test the whole path end to end. Drive the web app with `playwright-cli`, or call the API directly and read the JSON:API body.
5. Check side effects, not just the screen. A row written, a date stored as a `date` and not a string, a job queued, a file stored.

**When verification fails, suspect the observation method before the system.** A blank screenshot passes a lazy check.

**Delegation: trust artifacts, not self-reports.** When checking delegated work, read the `git diff` and the runtime behaviour, not the delegate's summary. Agents report what they intended, not always what happened.

**Script the check when you can.** The strongest proof is a deterministic script that re-runs the same comparison, kept as an artifact that can be re-run, rather than a one-time eyeball.

**Do not say "done" on the strength of a gate.** If the only evidence is that lint, build and test passed, say exactly that and say what remains unverified.

---

## 2. Fix root causes

**Trace every symptom to its cause and fix it there.**

Symptom fixes accumulate. Each workaround makes the system harder to reason about and the real bug is still there. Root-cause fixes are slower up front and cheaper in total.

- **Reproduce first.** If you cannot reproduce it, you cannot verify the fix.
- **Instrument before theorising.** Add `console.log` at the critical points and read what actually happens. Guessing from the code alone, then changing code, then guessing again, is the single most expensive loop in this repo. No logs, no truth.
- **Ask why until you reach the cause.** Not the first line that makes the error go away.
- **Resist guards.** A null check added to silence a crash is a symptom fix. So is a `try/catch` that swallows the error and leaves the database with no trace of it.
- **A retry is not a fix.** If an LLM call fails validation, the prompt or the `inputSchema` is wrong. Re-running the same call the same way is asking for the same garbage twice.
- **A cap is not a fix.** Truncating to 20 items to stop a timeout hides the query that should have been paginated.
- **Fix the pattern, not the instance.** Grep for the same shape and fix all of them. The same wrong number-field validation has been written more than once.
- **A warning means the code is wrong.** So does a pre-existing failure. It does not matter who wrote it; fix it.

**Restart bugs: suspect state before code.** Code does not change between runs; state does. Stale `.env`, a cached build, a Neo4j row written wrong once and never corrected, a lock file. If clearing state restores the behaviour, the fix is state validation.

---

## 3. Type system discipline

**The type checker is a proof assistant. A case the types let you ignore becomes a runtime failure the compiler could have stopped.**

`references/frontend/02-interfaces.md` and `references/backend/01-entity-basics.md` cover the shapes. This covers the judgment.

- **Make illegal states unrepresentable.** Model variants as discriminated unions, not a bag of optional fields where contradictory combinations compile. `{ completed: boolean; completedAt?: Date }` admits `completed: true` with no date, which is meaningless. Model it as `{ kind: "open" } | { kind: "done"; at: Date }`, or derive the boolean from `completedAt !== null`.
- **Never a bare string where a type exists.** `entityType: string` is wrong when a `Module` exists. So is a status as a loose string, an id as a name, or an enum where the entity itself belongs. If a JSON:API relationship can carry the object, carry the object — not its id.
- **Brand semantic primitives.** Two ids that are both strings underneath should not be interchangeable.
- **External data is untyped until parsed.** API payloads, Neo4j rows, env vars, LLM output. Parse at the boundary into the typed model — that is what DTOs and `rehydrate()` are for. See `references/backend/02-dtos.md`.
- **Do not lie to the compiler.** An `as` or a non-null assertion is a runtime crash scheduled for later. If the compiler cannot prove the fact, prove it or admit the cast is a hazard.
- **Exhaustive matching is the compiler's job.** A `switch` over a union must fail to compile when a variant is added. Use a `never`-typed default.
- **Derive, do not duplicate.** When the entity descriptor, the shared package, or a schema owns a shape, derive from it. A parallel hand-written type drifts, and it drifts in six repos at once.
- **Money in the smallest unit.** Integer cents. Never a float.
- **Dates are dates.** See `references/date-handling.md`. This is the single most repeated type failure in this codebase.

**The tests:** if you can write a comment explaining when a combination of fields is valid, the type is too loose. If two arguments share a primitive type and mean different things, brand them. If an `any` or an `as` appears, trace it back to the boundary and validate there instead.

---

## 4. Encode lessons in structure

**When you catch yourself writing the same instruction a second time, build the mechanism instead of repeating the sentence.**

Textual instructions require the reader to notice, remember and comply. A lint rule, a generator, a hook, an entity-descriptor constraint or a runtime check enforces the rule without cooperation.

When a correction repeats:

1. Ask whether it can be a lint rule, a type, a generator template, a hook, or a script.
2. If yes, build it and delete the instruction.
3. If it genuinely needs judgment, make the instruction more prominent and add an example of the failure.

**Pick the strongest rung available.** In order: a state that cannot compile, then a lint rule or banned API that fails CI, then a canonical helper or generator, then a runtime check, then prose. Agents copy whatever the surrounding code already does, so a weak guard becomes the next template.

**The instruction is the symptom.** If the fix is structural, use only the structural fix.

**Close the loop.** A correction that is acknowledged but not recorded does not persist. A note about a lint rule that should exist is wasted until the lint rule exists. Fixing one instance while leaving the pattern intact is the same failure in slow motion.

`nja-reflect` runs this loop over a finished session.

---

## 5. Separate before serialising shared state

**Several agents run in this repo at once. Instructions are not concurrency control.**

Concurrent writes to shared state create races that are intermittent, hard to reproduce and expensive to debug. Telling two sessions to take turns does not work.

1. **Identify the shared mutable state.** The working tree, the `dev` branch, a `.env` file, a dev-server port, a Neo4j database, a plan document two sessions both edit.
2. **Default to eliminating the sharing.** Each agent gets its own worktree, its own branch, its own output file. Two agents writing their own field into one shared document is still shared mutation.
3. **Only when one shared target is a real invariant, serialise it structurally.** Sequential phases, a single writer, a lock file. Treat "we need a lock" as a smell to check, not the default answer.

Concretely, in this repo:

- **Work in the worktree you were given.** Editing the main checkout instead of the worktree has cost real hours. Confirm with `pwd` and `git branch --show-current` before the first edit.
- **Commit only your own files.** Another session is very likely editing the same tree. Never `git add -A`.
- **Never revert, stash, reset or force-push.** Uncommitted changes in the tree may be the user's, not a previous agent's.
- **Never kill a process by name.** No `pkill -f node`, no `killall node`, no `pkill -f "next dev"`. Several projects run identical command lines on this machine and a name-pattern kill destroys unrelated work. Kill by PID, or by port: `lsof -ti :<port> -sTCP:LISTEN | xargs -r kill`. Verify the target belongs to this repo first.
- **Do not start or stop a dev server without being asked.** Check the port; if something answers, drive it.

---

Rules 1, 2, 3, 4 and 5 are adapted for nja from the `principle-prove-it-works`, `principle-fix-root-causes`, `principle-type-system-discipline`, `principle-encode-lessons-in-structure` and `principle-separate-before-serializing-shared-state` skills in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.
