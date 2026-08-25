#!/usr/bin/env bash
# A child that ignores SIGINT (but not SIGTERM), plus a plain child.
# Proves teardown reaches every group member, not just the leader.
#
# Also binds API_PORT/PORT like dev-ok.sh: Task 10's readiness poll requires
# api/web readiness to include the port genuinely being bound, not just a
# matching log line, so a fixture that claims to be ready must actually hold
# its ports — otherwise the readiness poll spins for the full --timeout
# instead of completing quickly.
set -uo pipefail
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

trap '' INT
( trap '' INT; while :; do sleep 1; done ) &
( while :; do sleep 1; done ) &
bind_port "$API_PORT"
bind_port "$WEB_PORT"
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 0.9s"
wait
