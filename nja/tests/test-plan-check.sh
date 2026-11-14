# Suite for scripts/nja-plan-check.sh: the mechanical plan checks.
# Sourced by run.sh.
PC="$NJA_SCRIPTS_DIR/nja-plan-check.sh"

pc_repo="$(t_mkrepo)"
mkdir -p "$pc_repo/apps/api/src/features/npc/dtos" "$pc_repo/scripts" "$pc_repo/apps/web/tests"
: > "$pc_repo/apps/api/src/features/npc/dtos/npc.post.dto.ts"
: > "$pc_repo/apps/api/src/features/npc/dtos/npc.put.dto.ts"
: > "$pc_repo/apps/api/src/features/npc/npc.module.ts"

HEADER='> **For agentic workers:** Execute this plan only through the execution protocol in the prompt file written by `nja-delegate-implementation`; the executing session never invokes that skill. NO `git add`, `git commit`, `git push`, `git stash`, branch or worktree at any point.'

pc_write() { printf '%s\n' "$@" > "$pc_repo/plan.md"; }
pc_run() { bash "$PC" "$pc_repo/plan.md" "$pc_repo" 2>&1; }

# 1. a clean plan passes, and the header's own "NO `git commit`" is not a step.
pc_write "# Plan" "" "$HEADER" "" \
  "## Task 1: DTOs" "" "**Files:**" \
  '- Modify: `apps/api/src/features/npc/dtos/npc.post.dto.ts:12-30` (`NpcPostAttributesDTO`), `npc.put.dto.ts`' \
  '- Create: `apps/api/src/features/npc/dtos/npc.patch.dto.ts`' \
  '- Modify: `apps/api/src/features/npc/npc.module.ts` (`Clue.clueType` stays, next to the `./const/session-wrap-up` export in `packages/shared/src/const`)' "" \
  "- No task has a Commit step; the plan never says frequent commits." "" \
  "- [ ] **Step 1: Write the failing spec**" "" \
  "## Task 2: E2E — NPC" "" "**Files:** none new" "" \
  "## Task 3: Final verification" "" "Run the spec review with the audit."
pc_out="$(pc_run)"
t_assert_exit 0 "clean plan exits 0" -- bash "$PC" "$pc_repo/plan.md" "$pc_repo"
t_assert_contains "$pc_out" "plan-check: 0 BLOCKING" "clean plan has no BLOCKING finding"
t_assert_contains "$pc_out" "3 Modify/Delete and 1 Create paths checked" "bare file name resolves against the line's last path; symbols and line suffixes are skipped"

# 2. every contract break is reported with its line.
pc_write "# Plan" "" "> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development" "" \
  "## Task 1: DTOs" "" "**Files:**" \
  '- Modify: `apps/api/src/features/npc/dtos/npc.gone.dto.ts`' \
  '- Create: `apps/api/src/features/npc/dtos/npc.post.dto.ts`' \
  '- Test: `apps/api/src/features/npc/dtos/npc.dto.spec.ts`' "" \
  "- [ ] **Step 5: Commit**" "" \
  '```bash' 'git add apps/api && git commit -m "feat: dtos"' '```' "" \
  "## Task 2: Service" "" "**Files:**" '- `apps/api/src/features/npc/npc.module.ts`' "" \
  "Use frequent commits." "" "**1. Subagent-Driven (recommended)**"
pc_out="$(pc_run)"
t_assert_exit 1 "contract breaks exit 1" -- bash "$PC" "$pc_repo/plan.md" "$pc_repo"
t_assert_contains "$pc_out" "BLOCKING plan.md:1 nja-header" "missing nja header is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:3 required-sub-skill" "REQUIRED SUB-SKILL is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:8 missing-path" "Modify of a missing file is blocking at its line"
t_assert_contains "$pc_out" "BLOCKING plan.md:9 create-exists" "Create of an existing file is blocking at its line"
t_assert_contains "$pc_out" "BLOCKING plan.md:10 file-markers" "a Test: marker is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:12 commit-step" "a Commit step is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:15 git-step" "a git add/commit command is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:20 file-markers" "a Files list with no marker is blocking at its **Files:** line"
t_assert_contains "$pc_out" "BLOCKING plan.md:23 frequent-commits" "\"frequent commits\" is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:25 execution-menu" "the execution menu is blocking"
t_assert_contains "$pc_out" "BLOCKING plan.md:1 spec-review" "a plan with no spec review is blocking"

# 3. e2e: a repo with an e2e suite and no e2e heading gets a CHECK, not a BLOCKING.
: > "$pc_repo/scripts/e2e.sh"; : > "$pc_repo/apps/web/tests/README.md"
pc_write "# Plan" "" "$HEADER" "" "## Task 1: Final verification" "" "Spec review runs here."
pc_out="$(pc_run)"
t_assert_contains "$pc_out" "CHECK plan.md:1 e2e-task" "missing e2e heading is reported for judgment"
t_assert_exit 0 "the e2e CHECK alone does not fail the plan" -- bash "$PC" "$pc_repo/plan.md" "$pc_repo"

# 4. usage errors.
t_assert_exit 2 "no plan argument exits 2" -- bash "$PC"
t_assert_exit 2 "a missing plan file exits 2" -- bash "$PC" "$pc_repo/nope.md" "$pc_repo"
