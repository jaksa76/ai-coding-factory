#!/usr/bin/env bats
# Integration test for workers/copilot Docker image
#
# Requires: Docker daemon running
# Build context: repository root (docker build -f workers/copilot/Dockerfile .)
#
# Run: bats workers/copilot/copilot-integration.bats

IMAGE_TAG="ai-coding-factory/copilot-worker:test"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

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

@test "image has gh installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which gh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh"* ]]
}

@test "@github/copilot npm package is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "ls /usr/local/lib/node_modules/@github/copilot/index.js"
    [ "$status" -eq 0 ]
}

@test "copilot wrapper is executable" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "[ -x /usr/local/bin/copilot ] && echo ok"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "agent is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which agent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent"* ]]
}

@test "copilot config template is present with placeholders" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" \
        -c "cat /root/.copilot/config.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'${GH_USERNAME}'* ]]
    [[ "$output" == *'${GH_TOKEN}'* ]]
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

@test "image has implement installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which implement"
    [ "$status" -eq 0 ]
    [[ "$output" == *"implement"* ]]
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

@test "agent init injects credentials into config" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "agent init && cat /root/.copilot/config.json"
    rm -f "$env_file"

    [ "$status" -eq 0 ]
    # Placeholders must have been replaced
    [[ "$output" != *'${GH_USERNAME}'* ]]
    [[ "$output" != *'${GH_TOKEN}'* ]]
    # Real username should now appear in the config
    [[ "$output" == *"jaksa76"* ]]
}

@test "agent run passes prompt to copilot and returns output" {
    # Uses a mock copilot created inside the container to verify plumbing
    # without hitting the real API.
    run docker run --rm \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            mkdir -p /tmp/mock-bin
            printf '#!/bin/sh\necho HELLO\n' > /tmp/mock-bin/copilot
            chmod +x /tmp/mock-bin/copilot
            export PATH=/tmp/mock-bin:\$PATH
            agent run 'any prompt'
        "

    [ "$status" -eq 0 ]
    [[ "$output" == *"HELLO"* ]]
}

@test "copilot responds to a real prompt (live API smoke test)" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file container exit_code reply
    env_file="$(make_docker_env_file)"

    container=$(docker run -d \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            agent init
            copilot -p 'Reply with the single word HELLO and nothing else.' \
                --no-ask-user --yolo --model gpt-4.1-nano \
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
