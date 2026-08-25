#!/usr/bin/env bash
# Stands in for `pnpm dev`: prints turbo-style ready lines, binds the two
# ports, and stays up until signalled.
#
# Binds with python3, not `nc -l` — nc's listen flag is not portable across
# BSD/GNU netcat builds, and a fixture that silently fails to bind makes
# every port assertion in the suite vacuous.
set -uo pipefail
API_PORT="${API_PORT:-13950}"
WEB_PORT="${WEB_PORT:-13951}"

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

sleep 1
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 1.2s"
while :; do sleep 1; done
