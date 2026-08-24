#!/usr/bin/env bash
# Shared helpers for the nja dependency scripts (sweep, doctor).
# SOURCED, never executed.
#
# Everything here is deterministic and side-effect free except
# nja_yaml_set_version, which is the single writer of pnpm-workspace.yaml.

NJA_DEPS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./nja-detect.sh
. "$NJA_DEPS_LIB_DIR/nja-detect.sh"

# ── output ───────────────────────────────────────────────────────────────────
nja_say()  { printf '%s\n' "$*"; }
nja_ok()   { printf '  ✓ %s\n' "$*"; }
nja_warn() { printf '  ⚠ %s\n' "$*"; }
nja_fail() { printf '  ✖ %s\n' "$*" >&2; }

# ── root ─────────────────────────────────────────────────────────────────────
# nja_resolve_root [path] — the repo root, or the given path if not a git repo.
nja_resolve_root() {
  local p="${1:-$PWD}"
  if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$p" rev-parse --show-toplevel
  else
    (cd "$p" && pwd)
  fi
}

# ── pnpm-workspace.yaml: packages ────────────────────────────────────────────
# nja_workspaces <root>
# One repo-relative directory per line: "." (the root manifest) plus every
# directory matched by the `packages:` globs that holds a package.json.
# Hardcoding the six historical paths is what left a360ai (three apps, no
# scripts/update.sh) unswept — always discover.
nja_workspaces() {
  local root="$1" yaml="$1/pnpm-workspace.yaml"
  [ -f "$yaml" ] || return 1
  printf '.\n'
  local glob base entry
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    case "$glob" in
      */\*)
        base="${glob%/\*}"
        [ -d "$root/$base" ] || continue
        for entry in "$root/$base"/*/; do
          [ -f "${entry}package.json" ] || continue
          entry="${entry%/}"
          printf '%s/%s\n' "$base" "${entry##*/}"
        done
        ;;
      *)
        [ -f "$root/$glob/package.json" ] && printf '%s\n' "$glob"
        ;;
    esac
  done <<EOF
$(nja_yaml_list "$yaml" packages)
EOF
  return 0
}

# nja_yaml_list <file> <block> — the "- item" entries of a top-level block.
nja_yaml_list() {
  awk -v want="$2" '
    index($0, want ":") == 1 { inb = 1; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    inb && /^[[:space:]]*-/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", line)
      if (line != "") print line
    }
  ' "$1"
}

# ── pnpm-workspace.yaml: key/value blocks ────────────────────────────────────
# nja_yaml_entries <file> <block>  →  "key<TAB>value" per entry.
# Mirrors the parser in each app's scripts/check-dep-drift.js, which is the
# reference implementation for the quoting these files actually use.
nja_yaml_entries() {
  awk -v want="$2" '
    index($0, want ":") == 1 { inb = 1; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    !inb                     { next }
    /^[[:space:]]*#/         { next }
    /^[[:space:]]*$/         { next }
    /^[[:space:]]*-/         { next }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      idx = index(line, ":")
      if (idx == 0) next
      k = substr(line, 1, idx - 1)
      v = substr(line, idx + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", k)
      gsub(/^['"'"'"]+|['"'"'"]+$/, "", v)
      if (k == "" || v == "") next
      printf "%s\t%s\n", k, v
    }
  ' "$1"
}
