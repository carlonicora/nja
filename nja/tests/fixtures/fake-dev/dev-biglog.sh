#!/usr/bin/env bash
# Like dev-ok.sh, but after the ready lines it floods well over a megabyte
# of turbo-shaped chatter (":dev:"-prefixed, like real webpack/compile
# output) — regression coverage for the grep-q/pipefail false-negative bug
# found in Task 10 review round 1: `saw_api`/`saw_worker` used to end their
# pipeline in `grep -q`, which exits the instant it matches and closes its
# stdin; if an upstream stage is still mid-write to a pipe already holding
# more than the kernel's pipe buffer (~16KB, trivially exceeded by real
# compile chatter after the ready line), that upstream process gets
# SIGPIPE and — under `pipefail` — the whole pipeline reports failure even
# though the match genuinely happened. This fixture exists to make that
# regression observable in the test suite, where fixture logs are normally
# only ~200 bytes.
#
# Binds with python3, not `nc -l` — see dev-ok.sh for why.
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

bind_port "$API_PORT"
bind_port "$WEB_PORT"

sleep 1
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 1.2s"

# ~1.4MB of trailing ":dev:"-shaped chatter, deliberately AFTER the ready
# lines — that ordering is what triggers the old bug (the match is found
# early in the stream, but a huge amount of further data is still queued
# behind it).
yes "fixture-web:dev: webpack compiled chunk padding padding padding padding" | head -n 20000

while :; do sleep 1; done
