#!/usr/bin/env bats
# Tests for worker-builder/worker-builder

WORKER_BUILDER="$BATS_TEST_DIRNAME/worker-builder"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Default stubs — overridden per test as needed
    stub docker ""
    stub jq ""

    # Default jq stub: return empty (no image field)
    stub_script jq 'printf ""'
}

teardown() {
    rm -rf "$STUB_DIR"
}

stub() {
    local cmd="$1" out="${2:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$out" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

stub_exit() {
    local cmd="$1" code="$2" out="${3:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\nexit %d\n' "$out" "$code" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

stub_script() {
    local cmd="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# ── subcommand validation ─────────────────────────────────────────────────────

@test "error: no subcommand prints usage" {
    run "$WORKER_BUILDER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"build"* ]]
}

@test "error: unknown subcommand" {
    run "$WORKER_BUILDER" frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown subcommand"* ]]
    [[ "$output" == *"frobnicate"* ]]
}

@test "--help prints usage" {
    run "$WORKER_BUILDER" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--devcontainer"* ]]
    [[ "$output" == *"--type"* ]]
}

@test "-h prints usage" {
    run "$WORKER_BUILDER" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── argument / option validation ──────────────────────────────────────────────

@test "error: missing --devcontainer" {
    run "$WORKER_BUILDER" build --type claude
    [ "$status" -eq 1 ]
    [[ "$output" == *"--devcontainer"* ]]
}

@test "error: missing --type" {
    run "$WORKER_BUILDER" build --devcontainer /some/path/devcontainer.json
    [ "$status" -eq 1 ]
    [[ "$output" == *"--type"* ]]
}

@test "error: unknown option" {
    run "$WORKER_BUILDER" build --devcontainer /some/path/devcontainer.json --type claude --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "error: unknown agent type" {
    run "$WORKER_BUILDER" build --devcontainer /some/path/devcontainer.json --type llama
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown agent type"* ]]
    [[ "$output" == *"llama"* ]]
}

@test "error: --devcontainer requires a value" {
    run "$WORKER_BUILDER" build --devcontainer --type claude
    [ "$status" -eq 1 ]
    [[ "$output" == *"--devcontainer requires a value"* ]]
}

@test "error: --type requires a value" {
    run "$WORKER_BUILDER" build --devcontainer /some/path/devcontainer.json --type --push
    [ "$status" -eq 1 ]
    [[ "$output" == *"--type requires a value"* ]]
}

@test "error: --tag requires a value" {
    run "$WORKER_BUILDER" build --devcontainer /some/path/devcontainer.json --type claude --tag
    [ "$status" -eq 1 ]
    [[ "$output" == *"--tag requires a value"* ]]
}

# ── default tag derivation ─────────────────────────────────────────────────────

@test "default tag includes agent type" {
    local docker_log devcontainer_file
    docker_log="$(mktemp)"
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build --devcontainer "$devcontainer_file" --type claude

    [[ "$(cat "$docker_log")" == *"worker-claude:latest"* ]]

    rm -f "$docker_log" "$devcontainer_file"
}

@test "--tag overrides the default image tag" {
    local docker_log devcontainer_file
    docker_log="$(mktemp)"
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude \
        --tag my-custom-tag:v1

    [[ "$(cat "$docker_log")" == *"my-custom-tag:v1"* ]]

    rm -f "$docker_log" "$devcontainer_file"
}

# ── devcontainer.json parsing ─────────────────────────────────────────────────

@test "falls back to default base image when devcontainer.json not found" {
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer /nonexistent/path/devcontainer.json \
        --type claude

    [[ "$output" == *"devcontainer.json not found"* ]]
    [[ "$output" == *"mcr.microsoft.com/devcontainers/base:bullseye"* ]]
}

@test "uses image field from devcontainer.json" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{"image": "node:18-bullseye"}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    # Use the real jq for this test
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"node:18-bullseye"* ]]
    [[ "$output" == *"FROM node:18-bullseye"* ]]

    rm -f "$devcontainer_file"
}

@test "strips // comments from devcontainer.json before parsing" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '// project devcontainer\n{"image": "ubuntu:22.04" // base image\n}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"ubuntu:22.04"* ]]
    [[ "$output" == *"FROM ubuntu:22.04"* ]]

    rm -f "$devcontainer_file"
}

@test "falls back to default when devcontainer.json has no image field" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{"name": "My Project"}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"No image field in devcontainer.json"* ]]
    [[ "$output" == *"mcr.microsoft.com/devcontainers/base:bullseye"* ]]

    rm -f "$devcontainer_file"
}

# ── Dockerfile generation ─────────────────────────────────────────────────────

@test "generated Dockerfile starts with FROM <base-image>" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [[ "$output" == *"FROM mcr.microsoft.com/devcontainers/base:bullseye"* ]]

    rm -f "$devcontainer_file"
}

@test "claude: Dockerfile installs Claude Code CLI" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [[ "$output" == *"claude.ai/install.sh"* ]]

    rm -f "$devcontainer_file"
}

@test "copilot: Dockerfile installs gh CLI and @github/copilot" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type copilot

    [[ "$output" == *"gh"* ]]
    [[ "$output" == *"@github/copilot"* ]]

    rm -f "$devcontainer_file"
}

@test "codex: Dockerfile installs @openai/codex" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type codex

    [[ "$output" == *"@openai/codex"* ]]

    rm -f "$devcontainer_file"
}

@test "generated Dockerfile installs acli" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [[ "$output" == *"acli"* ]]

    rm -f "$devcontainer_file"
}

@test "generated Dockerfile copies loop and claim" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [[ "$output" == *"COPY claim/claim"* ]]
    [[ "$output" == *"COPY loop/loop"* ]]

    rm -f "$devcontainer_file"
}

# ── docker build / push ───────────────────────────────────────────────────────

@test "docker build is called with the generated tag" {
    local docker_log devcontainer_file
    docker_log="$(mktemp)"
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude \
        --tag test-image:v2

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"build"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log" "$devcontainer_file"
}

@test "--push: docker push is called after build" {
    local docker_log devcontainer_file
    docker_log="$(mktemp)"
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude \
        --tag test-image:v2 \
        --push

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"push"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log" "$devcontainer_file"
}

@test "without --push: docker push is NOT called" {
    local docker_log devcontainer_file
    docker_log="$(mktemp)"
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude \
        --tag test-image:v2

    [[ "$(cat "$docker_log")" != *"push"* ]]

    rm -f "$docker_log" "$devcontainer_file"
}

@test "docker build failure propagates non-zero exit" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_exit docker 1 "Build failed"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude

    [ "$status" -ne 0 ]

    rm -f "$devcontainer_file"
}

@test "prints Done message with image tag on success" {
    local devcontainer_file
    devcontainer_file="$(mktemp)"
    printf '{}' > "$devcontainer_file"

    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" build \
        --devcontainer "$devcontainer_file" \
        --type claude \
        --tag final-image:latest

    [ "$status" -eq 0 ]
    [[ "$output" == *"Done"* ]]
    [[ "$output" == *"final-image:latest"* ]]

    rm -f "$devcontainer_file"
}
