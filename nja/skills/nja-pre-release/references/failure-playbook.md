# Failure playbook

## Contents

- Gate 1 — `pnpm lint`
- Gate 2 — `pnpm build`
- Gate 3 — `pnpm test`
- e2e — diagnose, never fix

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

### `TS2xxx` in a `*.spec.ts` file, from `tsc -p tsconfig.spec.json`

Every NestJS app's `lint` ends with `&& tsc -p tsconfig.spec.json`, so spec
type errors fail lint. A common one after a package bump is a mock or an
expectation typed against an old return type. Fix the spec's types. Type mocks
with `Mocked<T>` (`import type { Mocked } from "vitest"`). Never `as any`, never
`@ts-ignore`.

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

### `Error occurred prerendering page "…"` with `digest: 'HTTP_503'`

The build called the API. A prerendered page (static, or a dynamic segment with
`generateStaticParams`) reads through the cached path (`cachedServerGet`), so
`next build` makes that call. With no API reachable the call fails, and the
prerender fails **even when the caller catches the error**: `cachedServerGet`
throws so Next does not store the result, and Next fails the page on that
throw. Any `HTTP_<status>` digest is the same failure.

Fix: move the read into a component that awaits `connection()` behind its own
`<Suspense>`; a route handler calls `connection()` first. The read is still
cached at run time. **Never fix it by starting the API for the build** — Docker
and CI build with no API, so the build only passes on your machine. Verify by
building with the API stopped.

Related, at run time: a cached page failing with `HTTP_404`, where calling the
API endpoint returns "Cannot GET", means the route is not mounted. That is a
server change (e.g. `bootstrap({ howTo: { publicRoutes: true } })`), not a web
one.

### ``Route "…": Next.js encountered URL data `useSearchParams()` in a Client Component outside of `<Suspense>` ``

Digest `CLIENT_HOOK_DYNAMIC`. Cache Components prerenders the page, and a client
component reading the URL has no boundary to suspend into, so it blocks the
shell. Often the hook is inside a library component, not in your code.

Fix: give the segment its own `loading.tsx` (the standard skeleton), or move the
consumer behind its own `<Suspense>`. **Never add `export const instant = false`**,
even though the error suggests it — it makes the route blocking to hide the
failure.

### ``Route segment config "revalidate" is not compatible with `nextConfig.cacheComponents`. Please remove it.``

`dynamic`, `revalidate`, `fetchCache`, `dynamicParams` and `runtime = 'edge'`
all error under Cache Components, re-exports included. Delete the export.
Caching is declared on the data instead: a module with `cache: "<profile or
tag>"` already goes through the cached path.

---

## Gate 3 — `pnpm test`

### A test that fails in the full suite and passes alone

A leak between files or an order dependency, not a flake. The suites run
`sequence.shuffle`, and the `fast` project runs `isolate: false`, so one file's
mocks, env or globals reach the next file in the same worker.

1. Check the file, and the files that ran before it, against the isolation
   rule. A spec whose source contains `vi.mock(`, `vi.doMock(`,
   `vi.stubGlobal(`, `vi.resetModules(` or `modelRegistry.register(` runs in the
   `isolated` project. `vitest.isolation.ts` computes the list when the config
   loads. A spec that reaches one of these through an alias the regex does not
   match is the bug: write the call plainly.
2. Re-run with the same seed: `vitest run --sequence.seed=<n>` with the seed the
   failing run printed, or `turbo run test --force --concurrency=1` so turbo
   does not replay a cached run.
3. Fix the cause. `process.env.X = …` becomes `vi.stubEnv`, `global.fetch = …`
   becomes `vi.stubGlobal`, a mock set once in `beforeAll` moves to the test,
   a real wait becomes fake timers.

No retries, no raised timeouts, no `test.skip`.

### The second `pnpm test` finishes in seconds

Turbo replayed the cached result: nothing ran. Every re-run is
`turbo run test --force --concurrency=1`.

### A suite reports green with fewer files than before

The `include` no longer matches. Vitest collects `*.spec.*` only, so a file
named `*.test.*` never runs, and a suite with no files fails because no config
sets `passWithNoTests`. Compare file and test counts before and after any
rename.

### Failures that were already there

Not everything red is yours. If you did not change the area and the failure
looks unrelated, check whether it fails on a clean tree before spending the
attempt budget on it. A pre-existing failure still blocks green — but the report
must say it predates this run, because that changes what the user does about it.

### `UnknownDependenciesException` at startup, in a test that boots a module

First case: the missing token is `ResponseLanguageService` (nestjs-neo4jsonapi
5.4 and later). An app that replaces the package `UserModule` with its own
`Extended*` user module must also exclude `ResponseLanguageModule`, because
that module imports the package `UserModule`. Loaded anyway, it mounts the
package user controller beside the extended one and Fastify crashes on the
duplicate route. Excluded, it takes the service with it, so the app's own user
module must provide `ResponseLanguageService`.

Second case: two instances of a peer-fingerprinted package (`@nestjs/common`,
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

The runner is `scripts/e2e.sh`. With no arguments it starts 3 stacks (shards)
and splits the spec files between them; with arguments it starts one stack.
Each shard gets its own databases, queue prefixes, ports
(`E2E_PORT_BASE + 10k`) and Playwright cwd. It recreates the databases, boots
the worker and waits for migrations, then starts api and web and runs
Playwright.

### Reading a failure

Separate the three things that look alike in the output:

- **Boot failure** — the stack never came up. Every test then fails, and the
  test names are noise. Read the `[s<k>:api]` / `[s<k>:worker]` /
  `[s<k>:web]` prefixed lines above the Playwright output; the cause is there,
  not in the assertions. A failure in one shard only points at that shard's
  stack.
- **Fixture / seed drift** — many tests failing on the same missing or changed
  data. One cause, one proposal. Usually a migration or seed changed and the
  fixture did not follow.
- **A genuine assertion failure** — few tests, unrelated names, specific
  assertions. This is the one that is actually telling you something.

Three runner failures that are not test failures:

- **A spec passes in a scoped run and fails in the sharded run.** It reads data
  another spec file wrote, and the shards split by file. The fix is a seed the
  file owns, not a pinned shard.
- **The runner stops before booting and prints a pid.** Something outside this checkout
  holds a port in the e2e range: another project, or a worktree under
  `.claude/worktrees/`. Report the owner (`ps -o args= -p <pid>`). Never kill it.
- **Exit 1 after green tests, listing remote addresses.** The network log
  (`net-<k>.log`) saw the api, worker or corpus connect outside loopback to a
  host not in `E2E_ALLOWED_HOSTS` (default `api.stripe.com`). A credential the
  runner does not override reached a real third party. Propose the override.

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
