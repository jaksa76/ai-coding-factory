#!/usr/bin/env bats
# Integration test for factory full cycle:
#   start workers → watch logs → stop workers
#
# Requires: Docker daemon running
#
# Run: bats factory/factory-integration.bats

FACTORY="$BATS_TEST_DIRNAME/factory"
# Use a lightweight image that stays running long enough to test with
TEST_IMAGE="busybox"
WORKER_LABEL="ai-coding-factory.worker=true"

setup_file() {
    # Pull the test image once for the whole suite
    echo "Pulling $TEST_IMAGE …" >&3
    docker pull "$TEST_IMAGE" >&3 2>&3
}

teardown_file() {
    # Clean up any leftover test containers
    local ids
    ids="$(docker ps -a --filter "label=$WORKER_LABEL" --quiet)"
    if [[ -n "$ids" ]]; then
        # shellcheck disable=SC2086
        docker rm -f $ids >/dev/null 2>&1 || true
    fi
}

teardown() {
    # After each test, remove any factory workers so tests don't interfere
    local ids
    ids="$(docker ps -a --filter "label=$WORKER_LABEL" --quiet)"
    if [[ -n "$ids" ]]; then
        # shellcheck disable=SC2086
        docker rm -f $ids >/dev/null 2>&1 || true
    fi
}

# ── status before any workers ─────────────────────────────────────────────────

@test "status: no workers running initially" {
    run "$FACTORY" status
    [ "$status" -eq 0 ]
    # Output should only be the header row (or empty)
    local line_count
    line_count="$(echo "$output" | grep -c 'factory-worker' || true)"
    [ "$line_count" -eq 0 ]
}

# ── full cycle ────────────────────────────────────────────────────────────────

@test "full cycle: add workers, status shows them, stop them" {
    # Start 2 workers running a long-lived command
    run "$FACTORY" add --image "$TEST_IMAGE" 2 -- sh -c 'sleep 60'
    [ "$status" -eq 0 ]

    # Status should list both workers
    run "$FACTORY" status
    [ "$status" -eq 0 ]
    local worker_count
    worker_count="$(echo "$output" | grep -c 'factory-worker' || true)"
    [ "$worker_count" -eq 2 ]

    # Stop all workers
    run "$FACTORY" stop --all
    [ "$status" -eq 0 ]

    # Status should now show no workers
    run "$FACTORY" status
    [ "$status" -eq 0 ]
    worker_count="$(echo "$output" | grep -c 'factory-worker' || true)"
    [ "$worker_count" -eq 0 ]
}

@test "add: worker containers are labelled correctly" {
    run "$FACTORY" add --image "$TEST_IMAGE" 1 -- sh -c 'sleep 60'
    [ "$status" -eq 0 ]

    # Verify the container has the factory label
    local container_id
    container_id="$(docker ps --filter "label=$WORKER_LABEL" --quiet)"
    [ -n "$container_id" ]
}

@test "logs: streams output from a running worker" {
    # Start a worker that emits a known string
    run "$FACTORY" add --image "$TEST_IMAGE" 1 -- sh -c 'echo HELLO_FROM_WORKER; sleep 60'
    [ "$status" -eq 0 ]

    # Get the container name from docker ps
    local container_name
    container_name="$(docker ps --filter "label=$WORKER_LABEL" --format '{{.Names}}' | head -1)"
    [ -n "$container_name" ]

    # Wait briefly for the container to emit output
    sleep 1

    # Stream logs (non-follow mode via docker logs directly to avoid blocking)
    run docker logs "$container_name"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HELLO_FROM_WORKER"* ]]
}

@test "stop: stops a specific worker by name" {
    run "$FACTORY" add --image "$TEST_IMAGE" 2 -- sh -c 'sleep 60'
    [ "$status" -eq 0 ]

    # Get the first worker name
    local first_worker
    first_worker="$(docker ps --filter "label=$WORKER_LABEL" --format '{{.Names}}' | head -1)"
    [ -n "$first_worker" ]

    # Stop only the first worker
    run "$FACTORY" stop "$first_worker"
    [ "$status" -eq 0 ]

    # There should still be one worker running
    local remaining
    remaining="$(docker ps --filter "label=$WORKER_LABEL" --quiet | wc -l)"
    [ "$remaining" -eq 1 ]
}

@test "stop --all: with no workers prints informational message" {
    run "$FACTORY" stop --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No running workers"* ]]
}
