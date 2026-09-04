---
name: nja-blast-radius
description: Use before a change to a shared package (nestjs-neo4jsonapi, nextjs-jsonapi, shared) or any edit whose effects reach past its own diff — "blast radius of X", "what could this break", "will this break the other apps", "is this safe to release", or reviewing a small diff you do not trust yet. Finds the breakage grep will not show, then proves the one fact the change is safe because of by running code.
---

# Blast radius

Find what a change breaks somewhere else, before it ships.

Listing the callers is not the job. An agent can grep those in a second. The job is the breakage grep will not show you.

## Why this matters more here than in a normal repo

`nestjs-neo4jsonapi` and `nextjs-jsonapi` are consumed by every nja app: `a360ai`, `wyrdli`, `neural-erp`, `only35`, `dreamer`, `adhstudy`, and `create-carlonicora-app`'s template. A package change is released once and pulled by all of them. There is no staging step between "commit" and "six apps are on the new version".

So a package diff is never done when the package's own tests pass. It is done when you can say what it does to the consumers, and prove the load-bearing part of that claim by running code.

## Don't trust your own writeup

A blast-radius writeup that sounds right is worthless. It reads as convincing whether or not it is true, and that is the trap.

So do not hand back the writeup. Find the one or two facts the whole thing depends on and prove them by running code. Words are where you start, not what you ship.

### How sure are you

For each fact the change's safety depends on, get it as far down this list as is cheap, and say where it stopped.

1. You said so. Worthless on its own.
2. You pointed at the line. A real `file:line`, or the library's own source.
3. You showed the bad case cannot happen. You walked the failure step by step and it does not reach.
4. You ran it. A script or test that calls the real code and fails loud if you are wrong.
5. You reproduced it in the running app.

Any safety fact you cannot get to step 4, say so out loud. Do not write it up as settled. Step 4 is usually one small script that imports the same package build the app ships and calls the exact function you are worried about.

## Steps

1. **Read the change.** The diff, the symbols it adds, changes and deletes, and what it now does differently, including the part the diff does not spell out.

2. **Find the one fact it is safe because of.** Most changes that look scary are safe because of a single fact. Find it. If it holds, most of the scary cases die at once. Spend your time here, not on a long list of maybes.

3. **Look where grep stops.** In an nja repo that means, specifically:
   - **The JSON:API wire shape.** A serialiser or model change alters bytes the other side parses. The frontend `rehydrate()` of six apps reads that shape.
   - **Entity descriptors and `Modules`.** A renamed type or endpoint constant breaks rehydration at runtime, not at compile time.
   - **Cypher built by the framework.** `buildDefaultMatch()`, `{CURSOR}`, `initQuery()` serialisers. A change here silently alters company filtering, which is a security boundary.
   - **Neo4j stored shapes.** A date written as a string once stays wrong in the database after the code is fixed.
   - **Peer versions and the pnpm workspace.** Which apps are pinned to which package version right now.
   - **The consumer repos themselves.** Grep `~/Development/{a360ai,wyrdli,neural-erp,only35,dreamer,adhstudy}` for the symbol. A search that finds nothing is still an answer.

4. **Be honest about each risk.** Give it a real chance of happening and a real cost if it does. Keep the risks you confirmed; list the ones you checked and cleared separately. Cite a real `file:line`, and never invent a caller or an API.

5. **Prove the one fact.** Write a script or test that runs the real code, run it, and paste what happened. If you cannot prove it cheaply, mark it unproven. Do not round up.

6. For a big or wide change, ask a second model the same question and merge the answers. Different models catch different real bugs. `nja-interrogate` does this properly.

## What to hand back

- **What it does.** What changed, including the part that is not obvious.
- **The one fact it is safe because of.** State it, say which step you got it to, and show the proof. If you could not prove it, write **unproven**.
- **Risks.** Only the real ones. Each names how it breaks, the `file:line`, how likely and how bad, and how to check.
- **Cleared.** What you checked and why it is fine.
- **Consumers.** Per app: affected / not affected / unknown, with the evidence for each.
- **Before you release.** The cheapest test or repro that catches the real bug, including the script you wrote.

Write it through `nja-unslop`. Keep it short enough to read in one pass.

---

Adapted for nja from the `blast-radius` skill in [cursor/plugins `pstack`](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Copyright (c) 2026 Lauren Tan). Upstream at commit `195d935`. See `THIRD_PARTY.md`.
