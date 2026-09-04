---
name: nja-create-verifier
description: Use when a repo has no scripted way to prove UI or API behaviour by driving the real app — "make a verification skill", "make a control skill for this repo", "give me a way to prove this works before I test it", or when the user is being asked to hand-test something an agent could have driven itself. Generates a project-local verify-<app> skill plus a feature map, then proves it by running it once.
disable-model-invocation: true
---

# Create a verification skill

Every nja repo needs a scripted way to drive the real app and prove behaviour: launch it, exercise a feature the way a user would, and capture evidence. This skill generates that as a project-local skill (`.claude/skills/verify-<app>/`) tailored to the repo.

You write the generator's output for the next agent, not for a human. It will be read cold, mid-task, by an agent that has never seen the app.

> **Why this exists.** "It lints, it builds, it types" is not proof. The user is not the test harness. A verification skill is what lets an agent answer "does it work" before the user is asked to look.

## 0. nja defaults

In an nja monorepo you can skip most of the interview. Assume, then confirm against the repo:

- **Surface:** the Next.js web app (`apps/web`) is primary; the NestJS API (`apps/api`) is the secondary surface worth driving directly for data assertions.
- **Run:** `pnpm dev` from the repo root. **Read the ports; never assume them.** `API_PORT` in the repo-root `.env` is the API port and the web port is `API_PORT + 1`; `APP_URL` and `NEXT_PUBLIC_API_URL` give the real hosts, which do not follow one pattern (a360ai serves `avvocato360.test`, not its repo name).
- **Drive:** **`playwright-cli`**, never the Playwright library and never a browser MCP. Load the page twice and the session is already logged in. Ask the user for credentials once, then record in the generated skill **only where they live** — the `.env` variable names, or `.env.e2e` — never the values. `.claude/` is tracked in these repos, so a credential written into the generated skill is a credential committed.
- **Observe:** screenshots, the API's JSON:API response bodies, Cypher against Neo4j, and `docker compose` service logs.
- **Isolate:** worktrees run their own ports. Check what is already listening with `lsof -iTCP:<port> -sTCP:LISTEN` before starting anything.

**Never kill by process name.** No `pkill -f node`, no `killall node`. Several projects run on this machine with identical command lines. Kill only what this run started, by PID, or by port with `lsof -tiTCP:<port> -sTCP:LISTEN | xargs -r kill` (the bare `-ti :<port>` form also matches UDP holders — see `nja-pre-release`).

**Never start or stop a dev server the user is using.** Check first, and if something is already up on the port, drive that instead of restarting it.

## 1. Interview the repo, not the user

Answer these from the codebase and ask only what you cannot observe:

- **Surface:** what does a user actually touch? Confirm the nja defaults above against this repo.
- **Run:** the repo's own documented dev command. Note ports, env vars, seed data, auth.
- **Drive:** existing harnesses first. Specs live under `apps/web/tests/` when the repo has them, with `apps/web/tests/README.md` as the authority (`nja-e2e` owns that map). Read the existing selectors and login flow rather than inventing new ones. Not every repo has a suite — check before assuming one.
- **Observe:** what evidence can be captured? Screenshots, response bodies, Cypher results, logs, exit codes.
- **Isolate:** can two instances run side by side? If not, say so in the generated skill. Refusing to double-drive a shared instance beats corrupting the user's session.

If the checkout does not build or start as-is, fix that first, or report it precisely, before generating. A skill written against a broken base teaches wrong steps.

## 2. Generate the skill

Write `.claude/skills/verify-<app>/SKILL.md` with YAML frontmatter (`name: verify-<app>` and a `description` naming the app, the surface, and when to reach for it — without frontmatter the skill never registers) and these sections, each grounded in what the interview actually found. No placeholders left:

- **Launch.** The exact command that starts the app for verification, and how to tell it is ready: a log line, a port answering, a prompt. Include teardown, port-scoped.
- **Doctor.** One read-only check answering "is this instance worth driving?" — process up, right build, port owned by us, auth valid. An agent runs this first whenever anything looks off.
- **Drive.** The harness recipe with real selectors and commands from this repo, not examples. Prefer stable handles (ARIA labels, `data-*` attributes, route paths) over coordinates and tab order. Name `playwright-cli` explicitly and include the load-twice login step.
- **Evidence.** What to capture for a proof and where it goes. State the proof standards: exercise the real user path, never an internal setter or a test-only endpoint; capture the action and the resulting state, not just the final screen; verify side effects (Neo4j rows written, files stored, jobs queued) alongside what is visible; mocks only where a production boundary already isolates the external system.
- **Cleanup.** How to tear down what the run created. Kill by PID or port, never by name. Cleanup removes instances and scratch state, never the evidence: proof artifacts survive teardown, in a location the skill names.
- **Helpers.** Any script the skill ships is executable and its invocation is shown in the skill body. A helper the reader has to reverse-engineer is not a helper.

## 3. Seed the feature map

Create `.claude/skills/verify-<app>/features/README.md` plus one file per user-facing feature you can identify. Aim for the top three to five to start, taken from routes under `apps/web/src/app`, the module list, or the nav.

Follow the shape in `references/feature-map-example/`: a README index and one file per feature. Each file answers, from the user's point of view: what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works. The four H2s are `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>`, and `Gotchas`.

The map is the repo's maintained verification source. A proof that drives one convenient entry point is incomplete when the map lists others.

## 4. Prove the generated skill before handing it over

Run its own instructions end to end once: launch, doctor, drive ONE mapped feature, capture evidence, clean up. One feature is enough; the map exists so later runs cover the rest.

After cleanup, confirm the evidence still exists at the named location. A cleanup that eats the proof fails this step.

Fix what fails, and run the generated cleanup after every failed iteration too, so broken attempts do not strand processes and ports.

**A generated skill that was never executed is a draft, not a deliverable.** Do not report this skill as done on the strength of the file existing.

## 5. Offer the maintenance loop

Point the user at `nja-maintain-verifier` for keeping the map honest as the app changes.

---

Adapted for nja from the `create-verification-skill` skill in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.
