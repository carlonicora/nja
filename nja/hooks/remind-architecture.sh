#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|MultiEdit, shipped with the `nja` plugin.
# Injects a reminder to read the relevant architecture doc before editing a
# source file in a nestjs-neo4jsonapi + nextjs-jsonapi monorepo.
# Soft mode: reminder only, never blocks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/nja-detect.sh
. "$SCRIPT_DIR/../scripts/nja-detect.sh" 2>/dev/null || exit 0

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
# The script lives inside the plugin, not the target project, so derive the
# project root from the hook payload's cwd (fallback to $PWD).
PROJECT_ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$PWD"

[ -n "$FILE_PATH" ] || exit 0

# Stay inert outside nja projects (the plugin is user-scoped, fires everywhere).
nja_is_project "$PROJECT_ROOT" || exit 0

# Resolve the file path relative to the project root.
case "$FILE_PATH" in
  /*)
    # Absolute path: must be inside the project, else ignore.
    case "$FILE_PATH" in
      "$PROJECT_ROOT"/*) REL="${FILE_PATH#"$PROJECT_ROOT"/}" ;;
      *) exit 0 ;;
    esac
    ;;
  *)
    # Relative path: use as-is.
    REL="$FILE_PATH"
    ;;
esac

# Skip the plugin/agent's own .claude dir and non-source noise.
case "$REL" in
  .claude/*|node_modules/*|*/node_modules/*|*/dist/*|*/.next/*|docs/*|*.md) exit 0 ;;
esac

DOC=""
# NOTE: These patterns mirror the routing table in
# skills/nja-architecture/SKILL.md. If you change one, change the other.
case "$REL" in
  # Backend
  # Agent dirs first: agent/nodes/*.service.ts must route to the LLM doc,
  # not the generic services doc.
  apps/api/src/features/*/agent/*)
    DOC="references/backend/06-llm-calls.md → references/backend/04-services.md" ;;
  apps/api/src/features/*/entities/*)
    DOC="references/core-principles.md → references/backend/01-entity-basics.md" ;;
  apps/api/src/features/*/dtos/*|apps/api/src/features/*.dto.ts|apps/api/src/features/*/*.dto.ts)
    DOC="references/backend/02-dtos.md" ;;
  apps/api/src/features/*/repositories/*|apps/api/src/features/*.repository.ts|apps/api/src/features/*/*.repository.ts)
    DOC="references/backend/03-repositories.md → references/anti-patterns.md" ;;
  apps/api/src/features/*/services/*|apps/api/src/features/*.service.ts|apps/api/src/features/*/*.service.ts)
    DOC="references/backend/04-services.md" ;;
  apps/api/src/features/*/controllers/*|apps/api/src/features/*.controller.ts|apps/api/src/features/*/*.controller.ts)
    DOC="references/backend/05-controllers.md → references/backend/02-dtos.md" ;;
  apps/api/src/features/*)
    DOC="references/backend/ (pick the file-role doc: entity/dtos/repositories/services/controllers); see SKILL.md routing table" ;;

  # Frontend
  apps/web/src/features/*/data/*Interface.ts)
    DOC="references/frontend/02-interfaces.md" ;;
  apps/web/src/features/*/data/*Service.ts)
    DOC="references/frontend/03-services.md → references/anti-patterns.md" ;;
  apps/web/src/features/*/data/*.ts)
    DOC="references/frontend/01-models.md" ;;
  apps/web/src/features/*/components/*|apps/web/src/features/*/*.tsx)
    DOC="references/frontend/04-components.md (+ references/frontend/05-typography.md if the edit styles text, + references/frontend/06-blocknote.md if it touches a rich-text field)" ;;
  apps/web/src/features/*)
    DOC="references/frontend/ (pick the file-role doc: models/interfaces/services/components); see SKILL.md routing table" ;;

  # Shared packages
  packages/nestjs-neo4jsonapi/src/*)
    DOC="packages/nestjs-neo4jsonapi/CLAUDE.md + apps/api/CLAUDE.md" ;;
  packages/nextjs-jsonapi/src/*)
    DOC="packages/nextjs-jsonapi/CLAUDE.md + apps/web/CLAUDE.md" ;;
  packages/shared/src/*)
    DOC="packages/shared/CLAUDE.md" ;;
  packages/*/src/*)
    PKG=$(printf '%s' "$REL" | awk -F/ '{print $2}')
    DOC="packages/$PKG/CLAUDE.md" ;;

  *)
    exit 0 ;;
esac

MSG="ARCHITECTURE GUARDRAIL
You are about to edit \`$REL\`.

Before proceeding, invoke the \`nja-architecture\` skill — it provides the architecture rules and references for nestjs-neo4jsonapi + nextjs-jsonapi codebases.

For this file, the skill's routing table will direct you to:
  → $DOC

Violating architectural rules produces broken or insecure code. Skipping the skill invocation when the routing table has a match for this file is a guardrail violation."

jq -n --arg msg "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $msg
  }
}'
