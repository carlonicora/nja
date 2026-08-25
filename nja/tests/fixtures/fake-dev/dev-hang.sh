#!/usr/bin/env bash
# Never becomes ready. Used to test the timeout path (Task 10).
set -uo pipefail
echo "fixture-api:dev: starting..."
while :; do sleep 1; done
