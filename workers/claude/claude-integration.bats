#!/usr/bin/env bats
# Integration test for workers/claude Docker image
#
# Requires: Docker daemon running
# Build context: repository root (docker build -f workers/claude/Dockerfile .)
#
# Run: bats workers/claude/claude-integration.bats

IMAGE_TAG="ai-coding-factory/claude-worker:test"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

setup_file() {
    # Build the image once for the whole test suite; output goes to stderr so
    # bats can capture it without interfering with TAP output.
    echo "Building Docker image $IMAGE_TAG …" >&3
    docker build \
        --tag "$IMAGE_TAG" \
        --file "$REPO_ROOT/workers/claude/Dockerfile" \
        "$REPO_ROOT" >&3 2>&3
}

teardown_file() {
    docker rmi --force "$IMAGE_TAG" >/dev/null 2>&1 || true
}

# Strip 'export' prefix from .env so docker --env-file can consume it.
# Prints the path to a temp file; caller is responsible for deleting it.
make_docker_env_file() {
    local tmp
    tmp="$(mktemp)"
    grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$' | sed 's/^export //' > "$tmp"
    echo "$tmp"
}


# ── tool availability ─────────────────────────────────────────────────────────
# Use --entrypoint /bin/sh to bypass the default ENTRYPOINT for shell checks.

@test "claude is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
}

@test "agent is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which agent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent"* ]]
}

@test "image has loop installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which loop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loop"* ]]
}

@test "image has task-manager installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which task-manager"
    [ "$status" -eq 0 ]
    [[ "$output" == *"task-manager"* ]]
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

@test "entrypoint invokes agent init and loop" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent init"* ]]
    [[ "$output" == *"loop --project"* ]]
}

# ── loop behaviour ────────────────────────────────────────────────────────────

@test "loop --help prints usage (overrides ENTRYPOINT)" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "loop requires --project flag" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "loop requires JIRA_SITE env var" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --project PROJ
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

# ── end-to-end ────────────────────────────────────────────────────────────────

@test "agent init writes valid credentials JSON" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "agent init >/dev/null && cat /home/worker/.claude/.credentials.json"
    rm -f "$env_file"

    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
    [[ "$(echo "$output" | jq -r '.claudeAiOauth.accessToken')" != "null" ]]
    [[ "$(echo "$output" | jq -r '.claudeAiOauth.accessToken')" != "" ]]
}

@test "agent run passes prompt to claude and returns output" {
    # Uses a mock claude created inside the container to verify plumbing
    # without hitting the real API.
    run docker run --rm \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            mkdir -p /tmp/mock-bin
            printf '#!/bin/sh\necho HELLO\n' > /tmp/mock-bin/claude
            chmod +x /tmp/mock-bin/claude
            export PATH=/tmp/mock-bin:\$PATH
            agent run 'any prompt'
        "

    [ "$status" -eq 0 ]
    [[ "$output" == *"HELLO"* ]]
}

@test "claude responds to a real prompt (live API smoke test)" {
    # This is the only test that calls the real Claude API.
    # docker run foreground does not reliably forward stdout from the claude binary,
    # so we use detached mode and read logs after the container exits.
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file container exit_code reply
    env_file="$(make_docker_env_file)"

    container=$(docker run -d \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            agent init >/dev/null 2>&1
            claude --dangerously-skip-permissions \
                --model claude-haiku-4-5-20251001 \
                -p 'Reply with the single word HELLO and nothing else.' \
                > /tmp/reply.txt 2>&1
            cat /tmp/reply.txt
        ")
    rm -f "$env_file"

    exit_code=$(docker wait "$container")
    reply=$(docker logs "$container" 2>&1)
    docker rm "$container" >/dev/null 2>&1

    echo "# reply: $reply" >&3
    [ "$exit_code" -eq 0 ]
    [[ "$reply" == *"HELLO"* ]]
}
