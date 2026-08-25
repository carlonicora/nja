#!/usr/bin/env bash
# A child that ignores SIGINT (but not SIGTERM), plus a plain child.
# Proves teardown reaches every group member, not just the leader.
set -uo pipefail
trap '' INT
( trap '' INT; while :; do sleep 1; done ) &
( while :; do sleep 1; done ) &
echo "fixture-api:dev: [Nest] Nest application successfully started"
echo "fixture-api:dev:worker: [Nest] Nest application successfully started"
echo "fixture-web:dev:  ✓ Ready in 0.9s"
wait
