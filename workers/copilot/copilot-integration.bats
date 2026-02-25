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

@test "init-copilot is installed" {
    run docker run --rm --entrypoint /bin/sh "$IMAGE_TAG" -c "which init-copilot"
    [ "$status" -eq 0 ]
    [[ "$output" == *"init-copilot"* ]]
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

@test "entrypoint uses bash" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"bash"'* ]]
}

@test "entrypoint invokes loop --agent copilot" {
    run docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loop --agent copilot"* ]]
}

# ── loop behaviour ────────────────────────────────────────────────────────────

@test "loop --help prints usage (overrides ENTRYPOINT)" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "loop requires --project flag" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" --agent "copilot"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "loop requires JIRA_SITE env var" {
    run docker run --rm --entrypoint loop "$IMAGE_TAG" \
        --project PROJ --agent "copilot"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

# ── end-to-end ────────────────────────────────────────────────────────────────

@test "init-copilot injects credentials into config" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "init-copilot && cat /root/.copilot/config.json"
    rm -f "$env_file"

    [ "$status" -eq 0 ]
    # Placeholders must have been replaced
    [[ "$output" != *'${GH_USERNAME}'* ]]
    [[ "$output" != *'${GH_TOKEN}'* ]]
    # Real username should now appear in the config
    [[ "$output" == *"jaksa76"* ]]
}

@test "copilot responds to a prompt after init (exercises the agent)" {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi
    local env_file
    env_file="$(make_docker_env_file)"

    run docker run --rm \
        --env-file "$env_file" \
        --entrypoint bash \
        "$IMAGE_TAG" -c "
            init-copilot
            copilot -p 'Reply with the single word HELLO and nothing else.' \
                --no-ask-user --yolo --model gpt-4.1
        "
    rm -f "$env_file"

    echo "# output: $output" >&3
    [ "$status" -eq 0 ]
    [[ "$output" == *"HELLO"* ]]
}
