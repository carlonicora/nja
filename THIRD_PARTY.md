# Third-party notices

## pstack

Parts of this plugin are adapted from **pstack**, a Cursor plugin by Lauren Tan.

- Upstream: https://github.com/cursor/plugins/tree/main/pstack
- Vendored from commit `195d9359bdc2890f83745df69927528ad4538406`
- Licence: MIT

pstack targets Cursor. Every file below was ported to Claude Code (`Agent` in place of
`Task`, `~/.claude/` paths in place of `~/.cursor/`, `superpowers:writing-skills` in place
of Cursor's built-in `create-skill`, Anthropic model names) and adapted to the
nestjs-neo4jsonapi + nextjs-jsonapi stack.

### Skills adapted

| This plugin | Upstream skill |
|---|---|
| `nja-create-verifier` | `create-verification-skill` |
| `nja-maintain-verifier` | `maintain-verification-skill` |
| `nja-reflect` | `reflect` |
| `nja-blast-radius` | `blast-radius` |
| `nja-interrogate` | `interrogate` |
| `nja-unslop` | `unslop` |

### Reference files vendored

Copied with only the Cursor-specific paths changed:

- `nja-interrogate/references/` — `reviewer-prompt.md`, `rubric.md`, `code-quality-review.md`, `lead-judgment.md`
- `nja-reflect/references/` — `judgment-reviewer.md`, `tooling-reviewer.md`, `divergent-reviewer.md`, `synthesizer.md`
- `nja-create-verifier/references/feature-map-example/` — `README.md`, `search.md`, `create-note.md`

### Sections adapted

`nja-architecture/references/discipline.md` sections 1 to 5 are adapted from the
`principle-prove-it-works`, `principle-fix-root-causes`, `principle-type-system-discipline`,
`principle-encode-lessons-in-structure` and `principle-separate-before-serializing-shared-state`
skills.

### Licence

```
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

To diff against upstream later:

```bash
curl -sL https://github.com/cursor/plugins/archive/195d9359bdc2890f83745df69927528ad4538406.tar.gz | tar xz
diff -ru plugins-195d*/pstack/skills/interrogate/references nja/skills/nja-interrogate/references
```
