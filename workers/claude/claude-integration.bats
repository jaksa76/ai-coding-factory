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

@test "init-claude is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which init-claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"init-claude"* ]]
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

@test "entrypoint invokes loop --agent claude" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loop --project"* ]]
    [[ "$output" == *"--agent"* ]]
    [[ "$output" == *"claude"* ]]
}

# ── loop behaviour ────────────────────────────────────────────────────────────

@test "loop --help prints usage (overrides ENTRYPOINT)" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "loop requires --project flag" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --agent "claude"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "loop requires JIRA_SITE env var" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" \
        --project PROJ --agent "claude"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

# ── end-to-end ────────────────────────────────────────────────────────────────

@test "init-claude writes valid credentials JSON" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    # Run init-claude then print the credentials file on its own line so we can
    # parse just the JSON (init-claude also prints a human-readable status line).
    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "init-claude >/dev/null && cat /home/worker/.claude/.credentials.json"
    rm -f "$env_file"

    [ "$status" -eq 0 ]
    # Output must be valid JSON
    echo "$output" | jq . >/dev/null
    # Must contain the expected structure
    [[ "$(echo "$output" | jq -r '.claudeAiOauth.accessToken')" != "null" ]]
    [[ "$(echo "$output" | jq -r '.claudeAiOauth.accessToken')" != "" ]]
}

@test "claude responds to a prompt after init (exercises the agent)" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            init-claude
            claude --dangerously-skip-permissions \
                -p 'Reply with the single word HELLO and nothing else.'
        "
    rm -f "$env_file"

    echo "# output: $output" >&3
    [ "$status" -eq 0 ]
    [[ "$output" == *"HELLO"* ]]
}
