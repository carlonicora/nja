#!/usr/bin/env bash
# Stands in for `pnpm dev`: prints turbo-style ready lines, binds the two
# ports, and stays up until signalled.
#
# Binds with python3, not `nc -l` — nc's listen flag is not portable across
# BSD/GNU netcat builds, and a fixture that silently fails to bind makes
# every port assertion in the suite vacuous.
set -uo pipefail
# Reads the same env var names the script's own precondition/port checks
# use (API_PORT, PORT — not WEB_PORT) so a non-default PORT doesn't leave
# this fixture bound to the wrong port while the script checks another.
API_PORT="${API_PORT:-13950}"
WEB_PORT="${PORT:-13951}"

bind_port() {
  python3 -c '
import socket, sys, time
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
while True:
    time.sleep(1)
' "$1" &
}

bind_port "$API_PORT"
bind_port "$WEB_PORT"

# 4s, not 1s: Task 10's readiness poll declares the stack ready the instant
# both ports are bound AND all three ready lines are in the log — all of
# which happen back-to-back right after this sleep. A 1s margin left the
# I3 SIGINT-race test (test-dev-boot.sh) racing the outer harness's own
# detect-and-signal latency almost evenly, which was intermittently lost.
# 4s keeps this fixture reliably alive long enough for that signal to land.
sleep 4
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 1.2s"
while :; do sleep 1; done
