# Failure playbook

What the three fast gates actually fail with in this stack, and what each
failure means. Every entry here is a failure that was observed and diagnosed,
not a category invented for completeness.

The value of this file is in the entries that tell you **not** to fix
something — a failure you did not cause, or one where the obvious repair is
wrong. Reach for it before you start editing.

---

## Gate 1 — `pnpm lint`

### `ConfigError: Key "plugins": Cannot redefine plugin "@typescript-eslint"`

Two copies of the `@typescript-eslint` plugin in one config. `eslint-config-next`
depends on the `typescript-eslint` **meta-package**, which bundles its own parser
and plugin; when the catalog moves `@typescript-eslint/parser` and
`.../eslint-plugin` ahead of what the meta-package resolves, ESLint loads both.

Fix in `pnpm-workspace.yaml`, not in the eslint config: pin `typescript-eslint`
alongside the two individual packages so all three agree.

### `TypeError: Class extends value undefined is not a constructor or null`

ESLint 10 with `@typescript-eslint` v8. `FlatESLint` moved, and v8's transitive
`@typescript-eslint/utils` crashes at runtime on it — the peer ranges do not
show this. ESLint is held at `^9.x` for exactly this reason; if someone bumped
it, that is the bug. See the dependency-sweep hazards, §2.

### Lint passes but reports a file path from another checkout

Turbo replayed a cached result produced in a different worktree. Harmless when
the content is identical, but if you are trying to prove a change works, re-run
with `--force`.

---

## Gate 2 — `pnpm build`

### Every route 404s afterwards, or the dev server dies

You ran a production build over a live dev server's `.next`. See the hazard in
`SKILL.md`. Not a code failure — delete `apps/web/.next` and restart dev.

### `TS5011: rootDir must be explicit when outDir is set`

TypeScript 6. Add `"rootDir": "./src"` to the app's `tsconfig.build.json`.

**Check the emitted output even after the error goes away.** `tsc` still *emits*
while reporting TS5011, so a build that "failed" can leave a wrong-layout `dist`
behind — `dist/src/main.js` instead of a flat `dist/main.js`, which breaks
`node dist/main` at runtime with a green-looking build. Assert
`test -f apps/api/dist/main.js` before believing the build.

### `TS5101` / `TS5107` — `baseUrl` or `moduleResolution: node10` deprecated

TypeScript 6 turned these into hard errors. The repo-wide fix has already been
done (relativised `paths`, `nodenext`); if you are seeing it, something
reintroduced one. Do **not** add `ignoreDeprecations` back to a tsconfig — it is
removed entirely in TypeScript 7 and buys nothing.

The one exception: `tsup`'s dts build injects
`baseUrl: compilerOptions.baseUrl || "."` itself and reports TS5101 even when no
tsconfig declares it. That suppression belongs in the package's
`tsup.config.ts` under `dts.compilerOptions`, scoped to the tool that causes it.

### `TS2307: Cannot find module '@<name>/shared'`

`packages/shared` has not been built. Its consumers resolve through the
workspace symlink to `dist`, which does not exist yet. Run the build through
turbo so the dependency order is respected, rather than invoking `tsc` directly
in one app.

### `TS1272: a type referenced in a decorated signature must be imported with 'import type'`

TypeScript 6 with `isolatedModules` + `emitDecoratorMetadata`. Almost always a
type-only symbol in a decorated **method** parameter — `@Res() reply:
FastifyReply`, `@Req() req: AuthenticatedRequest` — where `import type` is the
correct fix.

**Confirm the symbol is not DI-injected before converting it.** If it is a class
in a *constructor* parameter, `import type` erases the runtime binding, its
`design:paramtypes` entry becomes `Object`, and injection breaks **silently** —
no compile error, no test failure, a wrong object at runtime. Check each symbol;
never codemod this one blind.

---

## Gate 3 — `pnpm test`

### A test that fails in the full suite and passes alone

A flake under contention, not a defect. Re-run the package in isolation before
touching anything. If it passes there, report it as a flake — do not "fix" it,
and do not let it burn your attempt cap.

### Failures that were already there

Not everything red is yours. If you did not change the area and the failure
looks unrelated, check whether it fails on a clean tree before spending the
attempt budget on it. A pre-existing failure still blocks green — but the report
must say it predates this run, because that changes what the user does about it.

### `UnknownDependenciesException` at startup, in a test that boots a module

Two instances of a peer-fingerprinted package (`@nestjs/common`,
`@nestjs/core`, `class-validator`, `react`…) in the tree. Unit tests usually
mock DI and miss it; when one surfaces here it is real. Confirm with the
dependency doctor — exactly one directory per package under `node_modules/.pnpm`
— rather than editing the test.

### DI resolves `undefined` for something the base class marked `@Optional()`

NestJS 12 reads optional-deps metadata with `Reflect.getOwnMetadata`, where v11
walked the prototype chain. A subclass keeps its base's injection **tokens** but
loses its base's **optional markers**. Re-declare `@Optional()` on the subclass.

Documented in neither the v12 release notes nor the migration guide, so nobody
will find it by searching — suspect it for any class extending a package class.

---

## e2e — diagnose, never fix

The runner is `scripts/e2e.sh`. It recreates a dedicated test database, boots
the stack on its own ports, waits for migrations, then runs Playwright.

### Reading a failure

Separate the three things that look alike in the output:

- **Boot failure** — the stack never came up. Every test then fails, and the
  test names are noise. Read the `[api]` / `[worker]` / `[web]` prefixed lines
  above the Playwright output; the cause is there, not in the assertions.
- **Fixture / seed drift** — many tests failing on the same missing or changed
  data. One cause, one proposal. Usually a migration or seed changed and the
  fixture did not follow.
- **A genuine assertion failure** — few tests, unrelated names, specific
  assertions. This is the one that is actually telling you something.

### Why you propose rather than fix

An e2e assertion encodes intended product behaviour. When it fails, either the
app is wrong or the expectation is out of date, and only the person who owns the
behaviour can say which. Editing the assertion to match current behaviour
deletes the finding — the test stops failing and the bug ships.

So: state the failing test, the actual error, your reading of the cause, and the
specific change you would make. Then stop.

### What a good proposal contains

- The test, by name and file.
- The error, quoted — not paraphrased.
- Which of the three categories above it falls into, and the evidence for that.
- The change you would make, specific enough to act on.
- If several failures share a cause, one proposal covering all of them, with the
  count.
