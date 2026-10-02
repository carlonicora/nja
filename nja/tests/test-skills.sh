#!/usr/bin/env bash
# Static checks over the plugin's SKILL.md files and their references.
#
# Every assertion here exists because a real defect shipped past lint, build
# and the shell suites — all of which are blind to markdown. Sourced by
# run.sh; never executed directly.

SKILLS_DIR="$(cd "$NJA_SCRIPTS_DIR/../skills" && pwd)"
PLUGIN_DIR="$(cd "$NJA_SCRIPTS_DIR/.." && pwd)"
REPO_DIR="$(cd "$PLUGIN_DIR/.." && pwd)"

# Skills adapted from pstack. Each must carry an attribution footer.
VENDORED="nja-blast-radius nja-create-verifier nja-interrogate nja-maintain-verifier nja-reflect nja-unslop nja-automate-me"

# ── frontmatter ───────────────────────────────────────────────────────────

for d in "$SKILLS_DIR"/*/; do
  n="$(basename "$d")"
  fm="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$d/SKILL.md" 2>/dev/null)"
  t_assert_eq "1" "$(printf '%s' "$fm" | grep -c '^name:')" "$n has exactly one name:"
  t_assert_eq "1" "$(printf '%s' "$fm" | grep -c '^description:')" "$n has exactly one description:"
  t_assert_eq "$n" "$(printf '%s' "$fm" | sed -n 's/^name: *//p')" "$n frontmatter name matches its directory"
done

# ── authoring best practices ──────────────────────────────────────────────
#
# Anthropic skill authoring best practices set hard limits on the frontmatter
# and on how a skill's files are laid out. Claude loads every description at
# startup to pick a skill, and reads SKILL.md and its references on demand;
# breaking these rules makes a skill misfire or get read only in part.

for d in "$SKILLS_DIR"/*/; do
  n="$(basename "$d")"; f="$d/SKILL.md"
  fm="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$f" 2>/dev/null)"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description: *//p' | head -1 \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"

  # Best practices: name is at most 64 chars of lowercase letters, digits and
  # hyphens, and may not use the reserved words "anthropic" or "claude".
  bad=""
  [ "${#name}" -le 64 ] || bad="$bad length ${#name} > 64;"
  printf '%s' "$name" | grep -qE '^[a-z0-9-]+$' || bad="$bad not [a-z0-9-]+;"
  printf '%s' "$name" | grep -qiE 'anthropic|claude' && bad="$bad reserved word;"
  if [ -z "$bad" ]; then t_pass "$n name follows the naming rules"
  else t_fail "$n name follows the naming rules" "[$name]:$bad"; fi

  # Best practices: description is non-empty and at most 1024 chars.
  if [ -n "$desc" ] && [ "${#desc}" -le 1024 ]; then t_pass "$n description is 1-1024 chars"
  else t_fail "$n description is 1-1024 chars" "length ${#desc}"; fi

  # Best practices: description may not contain XML tags.
  tag="$(printf '%s' "$desc" | grep -oE '<[^>]*>' | head -3 | tr '\n' ' ')"
  if [ -z "$tag" ]; then t_pass "$n description has no XML tags"
  else t_fail "$n description has no XML tags" "found: $tag"; fi

  # Best practices: description is written in third person, since it is
  # injected into the system prompt. Quoted trigger phrases are the user
  # speaking, so they may say "you" or "I".
  unq="$(printf '%s' "$desc" | sed 's/"[^"]*"//g')"
  pov="$( { printf '%s\n' "$unq" | grep -oiwE 'you|your|yours'
            printf '%s\n' "$unq" | grep -owE 'I'; } | sort -u | tr '\n' ' ')"
  if [ -z "$pov" ]; then t_pass "$n description is written in third person"
  else t_fail "$n description is written in third person" "first/second person outside quotes: $pov"; fi

  # Best practices: keep the SKILL.md body under 500 lines; move detail into
  # reference files instead.
  body="$(awk 'NR==1&&/^---$/{f=1;next} f==1&&/^---$/{f=2;next} f==2{c++} END{print c+0}' "$f" 2>/dev/null)"
  if [ "$body" -lt 500 ]; then t_pass "$n SKILL.md body is under 500 lines"
  else t_fail "$n SKILL.md body is under 500 lines" "$body lines"; fi

  # Best practices: keep references one level deep — every reference file is
  # linked straight from SKILL.md, because Claude may only partially read a
  # file it reaches through another reference. Hidden files (.DS_Store) are
  # not references and never ship.
  unlinked=""
  if [ -d "$d/references" ]; then
    skill_md="$(cat "$f" 2>/dev/null)"
    while IFS= read -r ref; do
      rel="${ref#"$d"}"; rel="${rel#/}"
      sub="${rel#references/}"
      base="$(basename "$ref")"
      case "$skill_md" in
        *"$rel"*|*"$sub"*|*"$base"*) ;;
        *) unlinked="$unlinked $rel" ;;
      esac
    done <<EOF
$(find "$d/references" -type f ! -name '.*' 2>/dev/null | sort)
EOF
  fi
  if [ -z "$unlinked" ]; then t_pass "$n links every reference file directly from SKILL.md"
  else t_fail "$n links every reference file directly from SKILL.md" "unlinked:$unlinked"; fi
done

# Best practices: a reference file over 100 lines opens with a table of
# contents, so Claude sees the full scope even when it previews only the top.
# The first `## ` heading outside fenced code must be `## Contents`.
for ref in $(find "$SKILLS_DIR" -path '*/evals' -prune -o -path '*/references/*' -type f -name '*.md' -print 2>/dev/null | sort); do
  rel="${ref#"$SKILLS_DIR"/}"
  lines="$(awk 'END{print NR}' "$ref")"
  [ "$lines" -gt 100 ] || continue
  first="$(awk '/^[ \t]*```/{c=!c;next} !c&&/^## /{print;exit}' "$ref")"
  t_assert_eq "## Contents" "$first" "$rel ($lines lines) opens with a ## Contents table"
done

# ── cited reference paths resolve ─────────────────────────────────────────
#
# A skill that cites `references/foo.md` and ships no such file sends the
# agent to a dead end mid-task, and nothing else in the repo notices.

for d in "$SKILLS_DIR"/*/; do
  n="$(basename "$d")"; missing=""
  # `references/<path>.md` inside backticks, anywhere in the skill body.
  for ref in $(grep -oE '`references/[A-Za-z0-9_./-]+\.md`' "$d/SKILL.md" 2>/dev/null | tr -d '`' | sort -u); do
    # A skill may cite its own references/ or nja-architecture's — the authority
    # skill's docs are cited by name across the plugin. Anything else is dead.
    [ -f "$d/$ref" ] && continue
    [ -f "$SKILLS_DIR/nja-architecture/$ref" ] && continue
    missing="$missing $ref"
  done
  if [ -z "$missing" ]; then t_pass "$n cites only reference files that exist"
  else t_fail "$n cites only reference files that exist" "missing:$missing"; fi
done

# ── template placeholders exist ───────────────────────────────────────────
#
# nja-interrogate fills a reviewer template by slot. A slot the orchestrator
# believes in but the template does not have silently drops that content —
# which is how the whole nja adaptation went missing from the reviewers.

RP="$SKILLS_DIR/nja-interrogate/references/reviewer-prompt.md"
if [ -f "$RP" ]; then
  for slot in INTENT DIFF_OR_FILES RUBRIC_CONTENTS CODE_QUALITY_CONTENTS REQUIRED_READING; do
    t_assert_contains "$(cat "$RP")" "{$slot}" "reviewer-prompt.md has a {$slot} slot"
  done
else
  t_fail "reviewer-prompt.md exists" "not found at $RP"
fi

# ── no Cursor residue in vendored files ───────────────────────────────────
#
# The reference files were copied verbatim from a Cursor plugin. Anything
# naming Cursor's paths or tool names makes the vendored logic misfire here:
# the reflect reviewers gate on tool names, and the synthesiser rejects
# their output when the gate does not match.

residue="$(grep -rInE '\.cursor/|~/\.cursor|\bTask\b prompts|Shell, Grep|create-skill' \
  "$SKILLS_DIR" --include='*.md' 2>/dev/null | grep -v 'superpowers:writing-skills' || true)"
if [ -z "$residue" ]; then t_pass "no Cursor paths or tool names survive in any skill"
else t_fail "no Cursor paths or tool names survive in any skill" "$(printf '%s' "$residue" | head -4)"; fi

# ── the lsof form this repo already corrected ─────────────────────────────
#
# `lsof -ti :<port>` also matches UDP holders that -sTCP:LISTEN does not
# filter; nja-pre-release records the correction and nja-dev-boot.sh uses
# the right form. Piping the bare form into kill is how an unrelated
# project's server dies.

badlsof="$(grep -rIn 'lsof -ti :' "$SKILLS_DIR" "$PLUGIN_DIR/scripts" 2>/dev/null \
  | grep -viE 'not +.?lsof -ti :|never' || true)"
if [ -z "$badlsof" ]; then t_pass "no skill teaches the bare 'lsof -ti :<port>' form"
else t_fail "no skill teaches the bare 'lsof -ti :<port>' form" "$(printf '%s' "$badlsof" | head -3)"; fi

# ── never pattern-kill ────────────────────────────────────────────────────

badkill="$(grep -rInE '\b(pkill|killall)\b' "$SKILLS_DIR" --include='*.md' --exclude-dir=evals 2>/dev/null \
  | grep -viE 'never|no +.?(pkill|killall)|does \*\*not\*\* use|not use|any name' || true)"
if [ -z "$badkill" ]; then t_pass "no skill instructs a pattern kill"
else t_fail "no skill instructs a pattern kill" "$(printf '%s' "$badkill" | head -3)"; fi

# ── ports and hosts are read, never hardcoded ─────────────────────────────
#
# Real values: a360ai 3400/3401 on avvocato360.test, wyrdli 3950/3951,
# neural-erp 3300/3301. No pattern covers them, so a skill that states one
# teaches an agent to look in the wrong place.

badport="$(grep -rInE '3[0-9]xx|34xx|33xx' "$SKILLS_DIR" --include='*.md' 2>/dev/null || true)"
if [ -z "$badport" ]; then t_pass "no skill hardcodes a port pattern"
else t_fail "no skill hardcodes a port pattern" "$(printf '%s' "$badport" | head -3)"; fi

# ── credentials never land in a tracked file ──────────────────────────────
#
# .claude/ is tracked in the consumer repos. A generated skill is a tracked
# file; telling an agent to record credentials in one commits them.

badcreds="$(grep -rInE 'credential|password' "$SKILLS_DIR" --include='*.md' 2>/dev/null \
  | grep -iE 'record|store|write|save|put' \
  | grep -viE 'never|\.env|not the value|variable name' || true)"
if [ -z "$badcreds" ]; then t_pass "no skill tells an agent to record credentials"
else t_fail "no skill tells an agent to record credentials" "$(printf '%s' "$badcreds" | head -3)"; fi

# ── vendored skills carry attribution, and the licence ships ──────────────

for n in $VENDORED; do
  f="$SKILLS_DIR/$n/SKILL.md"
  [ -f "$f" ] || continue
  t_assert_contains "$(cat "$f")" "pstack" "$n carries an upstream attribution footer"
done

t_assert_exit 0 "THIRD_PARTY.md ships inside the published plugin tree" -- test -f "$PLUGIN_DIR/THIRD_PARTY.md"
t_assert_exit 0 "LICENSE ships inside the published plugin tree" -- test -f "$PLUGIN_DIR/LICENSE"

# ── no assumed default branch ─────────────────────────────────────────────
#
# nja is on main; the apps are on dev; both libraries are on master. Any
# skill naming one of them as "the" base is wrong somewhere.

badbranch="$(grep -rInE 'git diff (dev|main|master)\.\.\.' "$SKILLS_DIR" --include='*.md' 2>/dev/null || true)"
if [ -z "$badbranch" ]; then t_pass "no skill assumes a fixed base branch in a git diff"
else t_fail "no skill assumes a fixed base branch in a git diff" "$(printf '%s' "$badbranch" | head -3)"; fi

# ── the fleet roster is discovered, not listed ────────────────────────────
#
# nja-fleet-survey.sh's own header: "The roster is NEVER stored in the
# skill: it is rediscovered on every invocation."

# The failure mode is a path list an agent is told to walk, not a dated note
# recording what was true on a day. Only the former goes stale as instruction.
roster="$(grep -rIn '~/Development/{\|Development/a360ai.*Development/wyrdli' \
  "$SKILLS_DIR" --include='*.md' 2>/dev/null || true)"
if [ -z "$roster" ]; then t_pass "no skill hardcodes the fleet roster"
else t_fail "no skill hardcodes the fleet roster" "$(printf '%s' "$roster" | head -3)"; fi

# ── manifests agree ───────────────────────────────────────────────────────

pv="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_DIR/.claude-plugin/plugin.json" | head -1)"
mv_="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$REPO_DIR/.claude-plugin/marketplace.json" | head -1)"
t_assert_eq "$pv" "$mv_" "plugin.json and marketplace.json agree on the version"

# ── every shipped skill is documented ─────────────────────────────────────

for d in "$SKILLS_DIR"/*/; do
  n="$(basename "$d")"
  t_assert_contains "$(cat "$REPO_DIR/README.md")" "\`$n\`" "README documents $n"
done
