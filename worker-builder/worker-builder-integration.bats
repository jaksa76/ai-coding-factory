#!/usr/bin/env bats
# Integration tests for worker-builder (requires Docker and network access)

WORKER_BUILDER="$BATS_TEST_DIRNAME/worker-builder"
TEST_IMAGE="test-worker-integration:latest"

setup() {
    if ! command -v docker >/dev/null 2>&1; then
        skip "docker not available"
    fi

    WORKSPACE="$(mktemp -d)"
    mkdir -p "$WORKSPACE/.devcontainer"
    printf '{"image": "ubuntu:22.04"}' > "$WORKSPACE/.devcontainer/devcontainer.json"
}

teardown() {
    docker rmi -f "$TEST_IMAGE" 2>/dev/null || true
    rm -rf "$WORKSPACE"
}

@test "builds a real worker image with loop, task-manager, and claude installed" {
    run "$WORKER_BUILDER" build \
        --devcontainer "$WORKSPACE" \
        --type claude \
        --tag "$TEST_IMAGE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Done"* ]]

    # Verify loop is present and executable
    run docker run --rm --entrypoint which "$TEST_IMAGE" loop
    [ "$status" -eq 0 ]

    # Verify task-manager is present and executable
    run docker run --rm --entrypoint which "$TEST_IMAGE" task-manager
    [ "$status" -eq 0 ]

    # Verify claude CLI is present
    run docker run --rm --entrypoint which "$TEST_IMAGE" claude
    [ "$status" -eq 0 ]
}
