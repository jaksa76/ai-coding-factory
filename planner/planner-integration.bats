#!/usr/bin/env bats
# Integration test for planner Docker image
#
# Requires: Docker daemon running
# Build context: repository root (docker build -f planner/Dockerfile .)
#
# Run: bats planner/planner-integration.bats

IMAGE_TAG="ai-coding-factory/planner:test"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env.test}"

setup_file() {
    echo "Building Docker image $IMAGE_TAG …" >&3
    docker build \
        --tag "$IMAGE_TAG" \
        --file "$REPO_ROOT/planner/Dockerfile" \
        "$REPO_ROOT" >&3 2>&3
}

teardown_file() {
    docker rmi --force "$IMAGE_TAG" >/dev/null 2>&1 || true
}


# ── tool availability ─────────────────────────────────────────────────────────

@test "image has claude installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
}

@test "image has agent installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which agent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent"* ]]
}

@test "image has loop installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which loop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loop"* ]]
}

@test "image has plan installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which plan"
    [ "$status" -eq 0 ]
    [[ "$output" == *"plan"* ]]
}

@test "image has git-utils.sh installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "[ -f /usr/local/bin/git-utils.sh ] && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "image has task-manager installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which task-manager"
    [ "$status" -eq 0 ]
    [[ "$output" == *"task-manager"* ]]
}

@test "image has task-manager backends installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "[ -x /usr/local/bin/backends/jira ] && [ -x /usr/local/bin/backends/github ] && [ -x /usr/local/bin/backends/todo ] && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "image has acli installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which acli"
    [ "$status" -eq 0 ]
    [[ "$output" == *"acli"* ]]
}

@test "image has jq installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which jq"
    [ "$status" -eq 0 ]
}

@test "image has git installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which git"
    [ "$status" -eq 0 ]
}

# ── credentials directory ─────────────────────────────────────────────────────

@test "~/.claude directory exists and is writable" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "[ -d /home/worker/.claude ] && [ -w /home/worker/.claude ] && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

# ── entrypoint ────────────────────────────────────────────────────────────────

@test "entrypoint uses bash" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"bash"'* ]]
}

@test "entrypoint invokes agent init and loop --for-planning" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent init"* ]]
    [[ "$output" == *"loop --for-planning"* ]]
}

# ── loop behaviour ────────────────────────────────────────────────────────────

@test "loop --help prints usage" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "loop requires --project flag" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}
