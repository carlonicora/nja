WAVES="$NJA_SCRIPTS_DIR/nja-fleet-waves.sh"

fleet="$(cd "$(mktemp -d -t nja-waves)" && pwd -P)"
mkdir -p "$fleet/a" "$fleet/b" "$fleet/c" "$fleet/logs"
roster="$fleet/roster.txt"
printf '%s\n%s\n%s\n' "$fleet/a" "$fleet/b" "$fleet/c" > "$roster"

# ── all pass ────────────────────────────────────────────────────────────────
NJA_FLEET_STAGE_CMD='exit 0' \
  t_assert_exit 0 "all members passing exits 0" -- \
  bash "$WAVES" --roster "$roster" --stage lint --logs "$fleet/logs" --width 2

t_assert_eq "0" "$(cat "$fleet/logs/a.lint.rc")" "a per-member rc file is written"
t_assert_eq "3" "$(ls "$fleet/logs"/*.lint.rc | grep -c .)" "one rc file per member"

# ── one fails: the others still run ─────────────────────────────────────────
rm -f "$fleet/logs"/*
NJA_FLEET_STAGE_CMD='case "$PWD" in */b) exit 7 ;; *) exit 0 ;; esac' \
  t_assert_exit 2 "one failing member exits 2" -- \
  bash "$WAVES" --roster "$roster" --stage lint --logs "$fleet/logs" --width 2

t_assert_eq "7" "$(cat "$fleet/logs/b.lint.rc")" "the failing member's code is recorded"
t_assert_eq "0" "$(cat "$fleet/logs/c.lint.rc")" "a member after the failure still ran"

# ── logs capture output ─────────────────────────────────────────────────────
rm -f "$fleet/logs"/*
NJA_FLEET_STAGE_CMD='echo hello-from-member' \
  bash "$WAVES" --roster "$roster" --stage build --logs "$fleet/logs" --width 3 >/dev/null 2>&1
t_assert_contains "$(cat "$fleet/logs/a.build.log")" "hello-from-member" "stdout lands in the member log"

# ── roster hygiene ──────────────────────────────────────────────────────────
rm -f "$fleet/logs"/*
printf '# a comment\n\n%s\n' "$fleet/a" > "$fleet/roster2.txt"
NJA_FLEET_STAGE_CMD='exit 0' \
  bash "$WAVES" --roster "$fleet/roster2.txt" --stage test --logs "$fleet/logs" >/dev/null 2>&1
t_assert_eq "1" "$(ls "$fleet/logs"/*.test.rc | grep -c .)" "comments and blank lines are skipped"

t_assert_exit 1 "a missing roster exits 1" -- bash "$WAVES" --roster /nonexistent --stage lint
t_assert_exit 1 "an unknown stage exits 1" -- bash "$WAVES" --roster "$roster" --stage frobnicate
t_assert_exit 1 "a bare --stage exits 1" -- bash "$WAVES" --roster "$roster" --stage

rm -rf "$fleet"

# ── boot queue: serial, and exit 4 aborts the rest ──────────────────────────
fleet="$(cd "$(mktemp -d -t nja-boot)" && pwd -P)"
mkdir -p "$fleet/a" "$fleet/b" "$fleet/c" "$fleet/logs"
roster="$fleet/roster.txt"
printf '%s\n%s\n%s\n' "$fleet/a" "$fleet/b" "$fleet/c" > "$roster"

NJA_FLEET_STAGE_CMD='exit 0' \
  t_assert_exit 0 "a clean boot queue exits 0" -- \
  bash "$WAVES" --roster "$roster" --stage boot --logs "$fleet/logs"
t_assert_eq "3" "$(ls "$fleet/logs"/*.boot.rc | grep -c .)" "every member booted"

rm -f "$fleet/logs"/*
NJA_FLEET_STAGE_CMD='case "$PWD" in */a) exit 2 ;; *) exit 0 ;; esac' \
  t_assert_exit 2 "a boot failure exits 2" -- \
  bash "$WAVES" --roster "$roster" --stage boot --logs "$fleet/logs"
t_assert_eq "3" "$(ls "$fleet/logs"/*.boot.rc | grep -c .)" "a plain failure does not stop the queue"

rm -f "$fleet/logs"/*
NJA_FLEET_STAGE_CMD='case "$PWD" in */a) exit 4 ;; *) exit 0 ;; esac' \
  t_assert_exit 4 "teardown-unverified aborts the queue with exit 4" -- \
  bash "$WAVES" --roster "$roster" --stage boot --logs "$fleet/logs"
t_assert_eq "1" "$(ls "$fleet/logs"/*.boot.rc | grep -c .)" "no member after the exit-4 ran"

rm -f "$fleet/logs"/*
abort_out="$(NJA_FLEET_STAGE_CMD='case "$PWD" in */a) exit 4 ;; *) exit 0 ;; esac' bash "$WAVES" --roster "$roster" --stage boot --logs "$fleet/logs" 2>&1)"
t_assert_contains "$abort_out" "ABORTING" "the abort is announced, not silent"
t_assert_contains "$abort_out" "NOT free the port" "the abort restates the port rule"

rm -f "$fleet/logs"/*
NJA_FLEET_STAGE_CMD='case "$PWD" in */c) exit 4 ;; *) exit 0 ;; esac' \
  t_assert_exit 4 "exit 4 on the last member still exits 4" -- \
  bash "$WAVES" --roster "$roster" --stage boot --logs "$fleet/logs"

rm -rf "$fleet"
