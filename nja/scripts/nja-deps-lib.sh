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
  local result
  if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
    result="$(git -C "$p" rev-parse --show-toplevel)"
    # macOS: strip /private prefix that git adds when resolving symlinks
    result="${result#/private}"
    printf '%s\n' "$result"
  else
    (cd "$p" && pwd)
  fi
}
