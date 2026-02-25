#!/usr/bin/env bats
# Integration test for workers/copilot Docker image
#
# Requires: Docker daemon running
# Build context: repository root (docker build -f workers/copilot/Dockerfile .)
#
# Run: bats workers/copilot/copilot-integration.bats

IMAGE_TAG="ai-coding-factory/copilot-worker:test"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup_file() {
    # Build the image once for the whole test suite; output goes to stderr so
    # bats can capture it without interfering with TAP output.
    echo "Building Docker image $IMAGE_TAG …" >&3
    docker build \
        --tag "$IMAGE_TAG" \
        --file "$REPO_ROOT/workers/copilot/Dockerfile" \
        "$REPO_ROOT" >&3 2>&3
}

teardown_file() {
    docker rmi --force "$IMAGE_TAG" >/dev/null 2>&1 || true
}

# ── tool availability ─────────────────────────────────────────────────────────
# Use --entrypoint /bin/sh to bypass the loop ENTRYPOINT for shell checks.

@test "image has gh installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which gh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh"* ]]
}

@test "gh copilot extension is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "ls /root/.local/share/gh/extensions/gh-copilot/gh-copilot"
    [ "$status" -eq 0 ]
}

@test "gh copilot binary is executable" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "[ -x /root/.local/share/gh/extensions/gh-copilot/gh-copilot ] && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "image has loop installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which loop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loop"* ]]
}

@test "image has claim installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which claim"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claim"* ]]
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

# ── entrypoint ────────────────────────────────────────────────────────────────

@test "entrypoint is loop" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"loop"'* ]]
}

@test "entrypoint uses gh copilot suggest as the agent" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh copilot suggest"* ]]
}

@test "entrypoint specifies gpt-4.1 model" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gpt-4.1"* ]]
}

# ── loop behaviour ────────────────────────────────────────────────────────────

@test "loop --help prints usage (overrides ENTRYPOINT)" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "loop requires --project flag" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --agent "gh copilot suggest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "loop requires JIRA_SITE env var" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" \
        --project PROJ --agent "gh copilot suggest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}
