#!/usr/bin/env bash
# Emits a fatal pattern, then keeps running — the boot check (Task 10) must
# not wait for the process to exit before calling it a failure.
set -uo pipefail
sleep 1
echo "fixture-api:dev: [Nest] UnknownDependenciesException: Nest can't resolve dependencies of the FooService"
while :; do sleep 1; done
