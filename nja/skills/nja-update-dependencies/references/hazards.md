# Dependency upgrade hazards

Distilled from the `narr8`-family `DEPENDENCY_UPGRADE_GUIDE.md` playbook
(dreamer / neural-erp / only35 / phlow). Its procedure — tagging, the `ncu`
walkthrough, committing and pushing — is replaced here by the skill's phase
table and its three scripts (`nja-deps-sweep.sh`, `nja-deps-doctor.sh`,
`nja-dev-boot.sh`); committing is out of scope for this tool. What's kept is
every failure story: each rule below exists because a specific incident
produced it, and a rule list without the incident invites skipping the rule
next time it looks inconvenient.

Section numbers are an interface: `nja-deps-doctor.sh` and `nja-dev-boot.sh`
both print "hazards.md §1" on failure. §1 is, and must stay, the
dual-instance peer-fingerprint failure.

---

## 1. The dual-instance peer-fingerprint failure

This is the single most likely landmine in any sweep, and the one both
scripts point at when they see trouble.

### Symptoms

- **Backend:** `UnknownDependenciesException` at startup for a service whose
  module is `@Global()` — the dependency it can't find often comes from
  another `@Global()` module (e.g. `ConfigService`), which makes the error
  look impossible. **Every unit test passes**, because unit tests mock DI
  and never exercise the real module graph.
- **Frontend:** a `UseFormReturn` / `UseFormSetValue` type mismatch in a file
  that mixes an app-defined hook with a library-exported component. Lint
  passes. `next dev` compiles fine. Only a production type-check catches it.
- **Both:** `pnpm peers check` shows nothing either way. The bug is invisible
  to pnpm's own peer warnings — it only shows up as a runtime or type-check
  failure downstream.

### Mechanism

pnpm keys a package's instance by its fully resolved set of peers, not just
its own version. When an app and a library it depends on see *different*
versions of one shared peer, pnpm materialises the *same* package twice —
once per peer context. Two `@nestjs/common@11.1.28` directories can exist
side by side in `.pnpm/`, each built against a different `class-validator`.
NestJS DI is class-identity-based, so a module registered against one copy
is invisible to a service resolved through the other.

### Detection and fix

`nja-deps-doctor.sh` runs two checks after every install and exits 2 on
either: (1) **single resolution per critical peer** — lists `.pnpm/`
entries for each peer it watches (`@nestjs/common`, `@nestjs/core`,
`react`, `react-dom`, `next`, `next-intl`, `class-validator`,
`class-transformer`, `zod`) and fails if more than one version-string shows
up; (2) **workspace link agreement** — resolves every workspace's
`node_modules/<peer>` symlink to its real target and fails if two
workspaces disagree.

Fix: add an **exact**-version override for the offending package in
`pnpm-workspace.yaml` (exact, not a caret range — a range can still resolve
to two values across contexts), run `CI=true pnpm install
--no-frozen-lockfile`, then re-run the doctor and confirm exit 0.

### The `.pnpmfile.cjs` case

`supports-color` is an *optional* peer of `debug`, and that optionality
still propagates into the peer fingerprint of everything above `debug` in
the graph — `@nestjs/common`, `bullmq`, `@nestjs/bullmq`, `@nestjs/core`.
The engine submodule's devDependencies (a release-tooling chain that pulls
in an old `chalk`) supply `supports-color` in its resolution context; the
apps' own dependency graphs don't. Left alone, that split fingerprint
double-resolves `@nestjs/core` and crashes NestJS boot on any *fresh*
install with `UnknownDependenciesException` — stale `node_modules` can mask
it, which is why the failure feels intermittent.

The fix lives in `.pnpmfile.cjs`'s `readPackage` hook: it deletes
`supports-color` from any package's `peerDependenciesMeta` /
`peerDependencies` before pnpm resolves the tree, removing the fingerprint
variance at the root. `debug` still colors its output via its own runtime
`require`, so nothing user-visible changes.

**Never remove that hook without re-running the check it exists for:**

```bash
ls -d node_modules/.pnpm/@nestjs+core*   # must list exactly ONE directory
```

More than one line means the hook was load-bearing and something upstream
of `debug` just split again.

### Known limit of the doctor's duplicate check

Check 1 normalises pnpm's peer-fingerprint suffix out of each version
string before comparing — e.g. `react@19.2.8_types+react@19.2.18` becomes
`19.2.8`. That's necessary: without it, the check would false-positive on
nearly every install, since pnpm routinely encodes harmless peer variance
into that suffix. The cost: two instances that share a version but carry
*different* fingerprint suffixes pass check 1 silently, since after
normalisation they look identical.

Check 2 (workspace link agreement) catches that case only when two
workspaces' `node_modules/<peer>` symlinks point at different targets. A
split that is purely *transitive* — no workspace directly links to the
second instance, some nested dependency pulls it in on its own — can sit in
`.pnpm/` undetected by both checks. Treat a clean doctor run as strong
evidence, not proof, when the graph is deep.

---

## 2. Stack-invariant hold-backs

These packages are pinned below their latest major for the whole
`narr8`-family stack, independent of any single repo's per-app deferrals
(those live in that repo's `scripts/update.sh`, under the `DEFERRED MAJOR
BUMPS` comment block — not here).

| Package | Kept at | What breaks | What unblocks it |
|---|---|---|---|
| `eslint` | `^9.x` | `@typescript-eslint` v8's transitive `@typescript-eslint/utils@8.49.0` crashes at runtime on ESLint 10 — `FlatESLint` was removed/relocated, so `TypeError: Class extends value undefined is not a constructor or null`. | A `@typescript-eslint` release whose *runtime* (not just its peer ranges) supports ESLint 10. Verify by running ESLint directly against a TS file before bumping the whole repo. |
| `typescript` | `^6.0.x` — **no longer held**, see §7 | — | Done fleet-wide 2026-08-30/31. TypeScript **7** is now the held major, and it is held on third parties, not on this stack: `typescript@7` deleted the JavaScript compiler API, so `@typescript-eslint` (peer `>=4.8.4 <6.1.0`; tracking issue open, labelled "blocked by external API") and `tsup`'s `--dts` cannot load it. Unblocks with **TypeScript 7.1**, which is to ship the stable programmatic API. Microsoft publishes `@typescript/typescript6` as a compat shim for embedders in the meantime. |
| `class-validator`, `class-transformer`, `rxjs`, `reflect-metadata` | whatever version the `nestjs-neo4jsonapi`-equivalent library declares | Each is part of `@nestjs/common`'s peer fingerprint (§1). Drifting the app past the library's declared version spawns the dual-instance failure. | Bump the library and the app in the same change set — never independently. |
| `react`, `react-dom` | whatever version the frontend JSON:API library declares | Same hazard as above, applied to the frontend — `react-hook-form` and JSX runtime typing go incoherent across two React instances (§1). | Bump in lockstep with the frontend library. |

---

## 3. The three dependency surfaces

A dependency lives in up to three places, and a tool that reads only one of
them sees a fraction of the picture:

1. **Manifest ranges** — the `dependencies`/`devDependencies` a
   `package.json` declares.
2. **The catalog** — `pnpm-workspace.yaml`'s `catalog:` block, the single
   source of truth a manifest can point at with the literal string
   `catalog:` instead of a range.
3. **Overrides** — `pnpm-workspace.yaml`'s `overrides` block, which forces a
   resolution regardless of what any manifest or the catalog declares.

### `ncu` only sees surface 1 — verified

A manifest containing `"eslint": "catalog:"` and `"zod": "^4.0.0"` produces
`ncu` output listing only `zod`. Silently — `ncu` doesn't warn that it
skipped `eslint`; `catalog:` simply isn't a semver range it knows how to
check, so it's invisible to the tool.

In dreamer this hides real breadth: 21 catalog entries and 16 concrete
overrides (of 29 override entries total — the other 13 are themselves
`catalog:` references, resolving the override to whatever the catalog
says). Together that's 37 packages under version control outside any
manifest range, including react, next, all six `@nestjs/*`, typescript,
class-validator, bullmq, yjs, jotai, openai, and five `@floating-ui/*`
packages. None of those show up in a plain `ncu` pass.

### The floor rule

An override **replaces** a manifest's declared range — it does not
intersect with it. An override set below a manifest's floor resolves under
that floor with no warning from pnpm. This is exactly how `@nestjs/*` sat
at `11.1.24` while every manifest in the repo declared `^11.1.28`: the
override had gone stale below the floor the manifests themselves required,
and nothing flagged the gap.

**Floors frequently live in the catalog, not in a literal range.** A
manifest commonly declares `"@nestjs/common": "catalog:"`, and the catalog
in turn pins `'@nestjs/common': ^11.1.28`. A floor check that only reads
literal manifest ranges misses this — it has to resolve `catalog:`
references back to the catalog's value first, or it misses the very
incident (§3, above) it exists to catch.

---

## 4. pnpm 11

- `pnpm.*` fields in `package.json` are **no longer read**. Everything —
  `overrides`, `ignoredBuiltDependencies`, `peerDependencyRules`,
  `patchedDependencies` — must live in `pnpm-workspace.yaml`. A migration
  that misses this doesn't error; the old config just silently stops
  applying.
- `onlyBuiltDependencies` (a list of strings) became `allowBuilds` (a map of
  `pkg: true|false`). On the **first** install after upgrading, pnpm 11
  writes a stub `allowBuilds:` block with placeholder strings (something
  like `"set this to true or false"`) instead of real booleans — those must
  be hand-edited to actual booleans before the next install, or the
  placeholders themselves are treated as truthy/falsy garbage.
- `verifyDepsBeforeRun` now **defaults to `install`**, which shells out to
  `pnpm install` before every `pnpm run`/`pnpm exec`. In a production
  container this is wrong on every axis: it needs network access, it
  mutates an image meant to be immutable, and — because the implicit
  install carries no `--ignore-scripts` — it runs the root `prepare`
  script with `devDependencies` absent. **This is what crash-looped the
  a360ai web container on 2026-08-05**: `pnpm install --production` →
  `prepare$ husky` → husky is a devDependency → `sh: husky: not found` →
  exit 1. Only production images that start via `pnpm run` are affected;
  targets that run `node dist/main` directly are not. Set
  `verifyDepsBeforeRun: warn` instead — it keeps the "your node_modules is
  stale" signal without the implicit install.
- As of this writing, `phlow` is still on pnpm `10.28.2` while the other
  five repos in the family are on `11.18.0`. Don't assume every repo in the
  family is on the same major.

---

## 5. Published-version drift (report-only)

The workspace builds and tests submodule **source**. The production image
installs whatever npm version is pinned in `versions.production.json`
(`scripts/apply-production-versions.js` substitutes that pinned version in
for `workspace:*` at build time). When a submodule's checkout has moved
past the release tag matching its declared `package.json` version, the
workspace and the production image are running **different code** — and
`check-dep-drift.js` rule 5 cannot see it, because it only compares
`versions.production.json` against the submodule's own `package.json`
version, and both hold the same (stale) number. This is why
`nja-deps-doctor.sh` treats this check as report-only: it warns, it never
fails the run, because the actual fix is publishing a library — out of
scope for this tool.

### Critical correction — use `git describe --tags`, not the default

Any check for this drift **must** call `git describe --tags`. Neither
`git submodule status` nor a bare `git describe` will do: both consider
only **annotated** tags, and these libraries release with **lightweight**
tags. An unqualified `git describe` walks back to the nearest unrelated
annotated tag, however distant, and reports the commit as many commits
"ahead" of it — which looks exactly like drift even when there is none.

This was misdiagnosed once during development of this skill: dreamer
appeared to be "26 commits past its tag," when `v3.2.2` is in fact a
lightweight tag pointing at exactly `HEAD`. Passing `--tags` includes
lightweight tags in the search and resolves correctly. Write any future
drift check this way the first time — the mistake is easy to repeat.

---

## 6. Gotchas

| Symptom | Likely cause | Section |
|---|---|---|
| `[ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY]` | No TTY for pnpm's confirmation prompt | Use `CI=true` |
| `[ERR_PNPM_LOCKFILE_CONFIG_MISMATCH]` | Lockfile predates an overrides/catalog change | Add `--no-frozen-lockfile` |
| `[ERR_PNPM_IGNORED_BUILDS]` (pnpm 11) | `allowBuilds` not configured, or still holding placeholder strings | §4 |
| Lint dies with `FlatESLint` undefined | Tried ESLint 10 against `@typescript-eslint` v8 | §2 |
| Build dies with TS5101 / TS5107 | A tsconfig still declares `baseUrl` or `moduleResolution: node10` | §7 |
| `dist/src/main.js` instead of a flat `dist/main.js`; `node dist/main` fails | TS 6 needs an explicit `rootDir` wherever `outDir` is set (TS5011) — and tsc **still emits** despite the diagnostic | §7 |
| tsup dts build reports TS5101 `baseUrl` though no tsconfig sets it | tsup injects `baseUrl` itself | §7 |
| `Debug Failure. False expression: position cannot precede the beginning of the file` | ts-node under TypeScript 6 | §7 |
| `pnpm start:worker` boots an API; no worker, no error | `nest start` swallowed `--mode` — the `--` separator is missing | §7 |
| DI resolves `undefined` for a dep the base class marked `@Optional()` | NestJS 12 reads optional-deps metadata with `getOwnMetadata` | §7 |
| `UnknownDependenciesException` at startup | Two `@nestjs/common` (or other peer-fingerprinted package) instances | §1 |
| Build: `UseFormReturn` type mismatch | Two `react` instances | §1 |
| Build seems to use a version you thought you reverted | Stale lockfile transitive resolution | Full clean install, then re-run `nja-deps-doctor.sh` |
| Override declared but not applied | pnpm 11 reading config from the wrong location (still in `package.json`, not `pnpm-workspace.yaml`) | §4 |
| `pnpm-workspace.yaml` has weird `allowBuilds:` placeholder strings | pnpm 11 wrote a stub on first install | §4 |
| Native build fails (e.g. rustc too old) | Underlying toolchain issue on this machine, not a real dependency problem | Set the package `false` in `allowBuilds`, or move it to `ignoredBuiltDependencies` |
| `ncu` output looks suspiciously short | It only reads manifest ranges — catalog and override entries are invisible to it | §3 |
| A version sits below what every manifest declares, with no warning | An override resolved below the manifest floor | §3 |
| Drift check reports a submodule "many commits ahead" of its tag | `git describe` without `--tags` missed a lightweight release tag | §5 |

---

## 7. The TypeScript 6 / NestJS 12 migration

Done fleet-wide on 2026-08-30/31 (wyrdli, a360ai, neural-erp, only35, dreamer,
plus `create-carlonicora-app`'s template). Everything below is a measured
failure from that run, not a prediction.

### The claim this section replaces

§2 used to hold `typescript` at `^5.9.x` and justify it like this: *"the backend
needs `module: commonjs`, and `bundler` is only legal under `module: preserve`
— so the backend can't move"*, with the unblock given as *"`module: node16` +
`.js`-extension refactor across every relative backend import"*.

**Both halves were wrong.** The move is `nodenext`, not `bundler`, and
`nodenext` is legal under CommonJS. `apps/api` stays CommonJS with **no**
`"type": "module"` and imports the ESM-only `@nestjs` v12 packages cleanly,
because `nodenext` models Node's `require(esm)` — `TS1479` is **zero**. No
`.js` extensions are needed anywhere.

The real cost was `import type` on a small set of **type-only symbols used in
decorated method signatures** (`TS1272`) — in wyrdli, 493 errors that reduced to
**10 distinct symbols across 52 files**, every one an `interface`/`type`
arriving via `@Req()`/`@Res()`, none constructor-injected. `create-carlonicora-app`'s
template had exactly **one**.

> `import type` is safe **only** once you have confirmed the symbol is not
> DI-injected. Erasing a constructor-parameter class turns its
> `design:paramtypes` entry into `Object` and breaks injection silently — no
> compile error, no test failure. Check each symbol; do not codemod blind.

### Removing `ignoreDeprecations` — the three causes, in order

`"ignoreDeprecations": "6.0"` buys one major and then stops existing: TypeScript
7 **removes** these options rather than deprecating them (TS5102/TS5108). Fix
the causes instead.

1. **`alwaysStrict`** — delete the explicit settings so it inherits from
   `strict`. **Order matters and the obvious move is wrong:** if the base sets
   `alwaysStrict: true`, deleting only an app's `false` override silently flips
   that app to `true` and emits `"use strict"` where it previously did not.
   Remove the base's setting too, and confirm with `tsc --showConfig`.
2. **`baseUrl`** — delete it; prefix every `paths` target with `./` so it
   resolves relative to the declaring tsconfig. **Verify against the emitted
   `dist`, not just `--noEmit`:** `nest build` rewrites path aliases, so a
   mistake surfaces as an unrewritten `require("src/…")` in the output rather
   than as a type error.
3. **`moduleResolution: node10` → `nodenext`.** node10 ignores `exports` maps,
   which is what deep-subpath `paths` mappings (`@langchain/*` and friends) were
   compensating for; `nodenext` honours them, so those mappings go.

### `TS5011` — the silent one

TypeScript 6 requires `rootDir` to be explicit wherever `outDir` is set. Without
it tsc emits `dist/src/main.js` instead of a flat `dist/main.js` — **and it
still emits despite the diagnostic**, so a failed build leaves a wrong-layout
`dist` behind and `node dist/main` (the production CMD) fails at runtime. Always
assert `test -f apps/api/dist/main.js` after building.

### tsup injects `baseUrl` itself

`tsup`'s dts build sets `baseUrl: compilerOptions.baseUrl || "."`
unconditionally, so it reports TS5101 even when no tsconfig in the repo declares
`baseUrl`. Scope the suppression to tsup's own `dts.compilerOptions`, never back
into a tsconfig:

```ts
dts: { compilerOptions: { composite: false, ignoreDeprecations: "6.0" } }
```

This is the only legitimate remaining use of the hatch. It is removable when
tsup stops injecting; tsup must be replaced before TypeScript 7 regardless.

### ts-node is dead — and it is what actually blocks TS 6

`ts-node`'s latest stable is **10.9.2 (2023-12-08)**; its only newer publish is
an `11.0.0-beta.1` that predates it. Under TypeScript 6 it crashes inside
TypeScript's own emitter:

```
Debug Failure. False expression: position cannot precede the beginning of the file
  computeLineOfPosition -> emitPos -> emitSourceMapsBeforeNode
```

`transpileOnly`, `sourceMap:false` and the swc transpiler do **not** avoid it.
Isolated by swapping only the compiler: ts-node + TS 5.9.3 boots; ts-node +
TS 6.0.3 crashes; `nest start` (tsc-based) + TS 6.0.3 boots and serves traffic.

Replacements, by script shape:

- **watch/dev** → `nest start --watch -- --mode=<api|worker>`
- **one-shot, no Nest bootstrap** → `tsx` (drop `-r tsconfig-paths/register`;
  tsx reads the tsconfig `paths` itself)
- **one-shot that boots a Nest context** → compile with `tsc` into a
  `dist-tools/`, run as plain JS with `NODE_PATH`. Only tsc emits the
  `design:paramtypes` metadata DI needs.

**Do not reach for `@swc-node/register` or `tsx` for Nest-bootstrapping
scripts.** tsx/esbuild cannot emit decorator metadata at all; `@swc-node/register`
gets past DI and then dies with `InvalidProcessorClassError` (WorkerHost),
because `@nestjs/bullmq` loads as ESM while the app's CJS requires it — two
`WorkerHost` classes, §1's class-identity failure arriving via module-format
duality rather than version duality.

If a `dist-tools/` output is placed at a different depth from its source, every
`__dirname`-relative path silently changes meaning (`.env` lookups resolve to
the wrong root, package-relative imports land outside the repo). Emit at a
depth-identical location, and carry **both** roots in `NODE_PATH` — an
out-of-package output loses the app's own `node_modules`.

### `nest start` swallows unknown flags

```bash
nest start --mode=worker        # boots an API. No error. No worker.
nest start -- --mode=worker     # correct
```

Measured in two repos independently. Every affected repo shipped a broken
`start:worker` for as long as the script existed, production unaffected only
because Docker runs `node dist/main --mode=worker` directly. **Assert on the
worker's own log line** (`Worker process started` or equivalent), never on "it
booted" — the api and worker are otherwise indistinguishable in a boot log.

### NestJS 12 drops inherited `@Optional()`

v12 reads `OPTIONAL_DEPS_METADATA` with `Reflect.getOwnMetadata`; v11 used
`Reflect.getMetadata`, which walks the prototype chain. `@Inject()` still seeds
from the chain — so a subclass keeps its base's injection **tokens** but loses
its base's **optional markers**, and the dependency resolves `undefined`.

**This is in neither the v12 release notes nor the official migration guide.**
It broke three sites in a360ai, one of which would have killed API boot rather
than a test. Suspect it for any class extending a package-provided class; the
fix is to re-declare `@Optional()` on the subclass.

### Two concurrent `nest start --watch` processes race over `dist`

`pnpm dev` runs api and worker together, and `nest-cli.json`'s `deleteOutDir`
fires at each one's startup, so one watcher wipes the directory the other is
loading from. Observed as `Cannot find module './load-env'` and, in a360ai's
corpus app, `CircularDependencyException` from a half-written tree. The window
is narrow — five consecutive clean boots did **not** reproduce it — so clean
runs do not disprove it. Design it out: give the worker its own `outDir` via a
`tsconfig.worker.json` selected with `nest start -p`, and drop the hardcoded
`outDir` from `nest-cli.json`'s asset entries so they follow whichever build
runs.

### Entrypoint env loading must be an import

`dotenv.config()` sitting *between* imports only works because TypeScript's
CommonJS emit preserves import/statement interleaving. Every ESM-correct
transpiler hoists imports above it, the library loads before any env var
exists, and bootstrap dies with `JwtStrategy requires a secret or key`. Move it
into a `src/load-env.ts` imported first for its side effect — ESM guarantees
import *order*, not statement position.

### Method note: a config error aborts the typecheck

`tsc` reports config-level errors (TS5102/TS5090/TS5101) **instead of** checking
files, so the file-level count comes back as whatever those few config errors
are. During this migration that produced two fabricated results: a phantom
"467 × TS1479, ESM migration required" from a probe whose `module: nodenext`
override never applied, and a 48 × TS6059 that masked the real count.

**Confirm with `tsc --showConfig -p <config>` that your options actually applied
before trusting any error count.** The same discipline applies to "it loads"
checks: a `require()` of an emitted file proves nothing about an `import type`
that tsc elided, or about a dynamic `import()` inside a function body.
