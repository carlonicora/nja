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

# nja_yaml_set_version <file> <block> <key> <new-version>
# The ONLY writer of pnpm-workspace.yaml. Substitutes the version token and
# nothing else — indentation, quoting, trailing comments and every other line
# survive byte-for-byte. These files carry incident commentary that is worth
# more than the versions; a reformatting write would be a regression.
#
# Exit codes:
#   0  substituted; the file was updated in place.
#   1  the key was not found as a scalar entry in that block — soft/benign
#      (also the outcome for a key that only appears as a nested-map header,
#      e.g. `react:` with indented children and no inline value). The file
#      is left byte-identical and no temp file is left behind.
#   2  hard failure: missing/unreadable file, unwritable directory, an awk
#      error, a truncated write, or a failed mv. The file is left
#      byte-identical and no temp file is left behind.
nja_yaml_set_version() {
  local file="$1" block="$2" key="$3" new="$4"
  local tmp="$file.nja.tmp"
  local rc=0

  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    return 2
  fi
  local dir="${file%/*}"
  [ "$dir" = "$file" ] && dir="."
  if [ ! -w "$dir" ]; then
    return 2
  fi

  trap 'rm -f "$tmp"' INT TERM HUP

  awk -v want="$block" -v key="$key" -v new="$new" '
    BEGIN { inb = 0; done = 0 }
    index($0, want ":") == 1 { inb = 1; print; next }
    inb && /^[^[:space:]#]/  { inb = 0 }
    {
      matched = 0
      if (inb && !done && $0 !~ /^[[:space:]]*#/) {
        # Determine where the key ends and the value separator (":") is.
        # A key whose first non-space character is a quote may itself
        # contain a colon (e.g. '"'"'react:native'"'"'), so the separator is the
        # first ":" AFTER the matching closing quote, not the first ":"
        # in the line.
        i = 1
        while (i <= length($0) && substr($0, i, 1) ~ /[[:space:]]/) i++
        firstch = (i <= length($0)) ? substr($0, i, 1) : ""
        if (firstch == "\047" || firstch == "\"") {
          qch = firstch
          closepos = 0
          j = i + 1
          while (j <= length($0)) {
            if (substr($0, j, 1) == qch) { closepos = j; break }
            j++
          }
          if (closepos > 0) {
            afterkey = substr($0, closepos + 1)
            crel = index(afterkey, ":")
            idx = (crel > 0) ? closepos + crel : 0
          } else {
            idx = 0
          }
        } else {
          idx = index($0, ":")
        }
        if (idx > 0) {
          k = substr($0, 1, idx - 1)
          bare = k
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", bare)
          gsub(/^['"'"'"]+|['"'"'"]+$/, "", bare)
          if (bare == key) {
            rest = substr($0, idx + 1)
            match(rest, /^[[:space:]]*/); gap = substr(rest, 1, RLENGTH)
            val = substr(rest, RLENGTH + 1)
            trail = ""
            # A "#" only starts a comment when preceded by whitespace (or
            # at the very start of the value) — a bare "#" glued to the
            # value, e.g. github:lovell/sharp#v0.35.3, is part of the value.
            if (match(val, /(^|[[:space:]])#.*$/)) {
              trail = substr(val, RSTART)
              val = substr(val, 1, RSTART - 1)
            }
            valtrim = val
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", valtrim)
            # An empty value means this is a nested-map header (e.g.
            # `react:` with indented children below), not a scalar entry.
            # nja_yaml_entries already refuses to treat these as real
            # entries (see its "k == \"\" || v == \"\"" guard); the writer
            # must be at least as strict, or it clobbers the header and
            # orphans the child lines.
            if (valtrim != "") {
              q = ""
              if (substr(val, 1, 1) == "\047" || substr(val, 1, 1) == "\"") q = substr(val, 1, 1)
              printf "%s:%s%s%s%s%s\n", k, gap, q, new, q, trail
              done = 1
              matched = 1
            }
          }
        }
      }
      if (!matched) print
    }
    END { exit(done ? 0 : 1) }
  ' "$file" > "$tmp"
  local code=$?

  if [ "$code" -eq 1 ]; then
    rc=1
  elif [ "$code" -ne 0 ]; then
    rc=2
  elif [ ! -s "$tmp" ] && [ -s "$file" ]; then
    rc=2
  elif mv "$tmp" "$file"; then
    rc=0
  else
    rc=2
  fi

  [ "$rc" -ne 0 ] && rm -f "$tmp"
  trap - INT TERM HUP
  return "$rc"
}
