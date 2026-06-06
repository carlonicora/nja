#!/usr/bin/env bash
# Shared detector: is a directory an nja project?
#
# The plugin is installed at user scope, so its hooks fire in EVERY repo. They
# must stay completely inert in projects that don't use nestjs-neo4jsonapi /
# nextjs-jsonapi — otherwise rules like the Base-UI/Radix ban would wrongly
# block unrelated projects.
#
# A repo counts as nja if either:
#   • it has an `nja.config.json` at its root (explicit opt-in), or
#   • any tracked package.json depends on @carlonicora/nestjs-neo4jsonapi or
#     @carlonicora/nextjs-jsonapi.
nja_is_project() {
  local root="${1:-$PWD}"
  [ -f "$root/nja.config.json" ] && return 0
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$root" grep -qiE '@carlonicora/(nestjs-neo4jsonapi|nextjs-jsonapi)' -- '*package.json' >/dev/null 2>&1 && return 0
  fi
  grep -qiE '@carlonicora/(nestjs-neo4jsonapi|nextjs-jsonapi)' "$root/package.json" 2>/dev/null && return 0
  return 1
}
