#!/usr/bin/env bats
# Tests for worker-builder/worker-builder

WORKER_BUILDER="$BATS_TEST_DIRNAME/worker-builder"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Default stubs — overridden per test as needed
    stub docker ""
    stub devcontainer ""
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
    run "$WORKER_BUILDER" build --devcontainer /some/workspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"--type"* ]]
}

@test "error: unknown option" {
    run "$WORKER_BUILDER" build --devcontainer /some/workspace --type claude --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "error: unknown agent type" {
    run "$WORKER_BUILDER" build --devcontainer /some/workspace --type llama
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
    run "$WORKER_BUILDER" build --devcontainer /some/workspace --type --push
    [ "$status" -eq 1 ]
    [[ "$output" == *"--type requires a value"* ]]
}

@test "error: --tag requires a value" {
    run "$WORKER_BUILDER" build --devcontainer /some/workspace --type claude --tag
    [ "$status" -eq 1 ]
    [[ "$output" == *"--tag requires a value"* ]]
}

# ── default tag derivation ─────────────────────────────────────────────────────

@test "default tag includes agent type" {
    local docker_log workspace_dir
    docker_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script docker "echo \"\$@\" >> '$docker_log'"

    run "$WORKER_BUILDER" build --devcontainer "$workspace_dir" --type claude

    [[ "$(cat "$docker_log")" == *"worker-claude:latest"* ]]

    rm -f "$docker_log"
    rm -rf "$workspace_dir"
}

@test "--tag overrides the default image tag" {
    local docker_log workspace_dir
    docker_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script docker "echo \"\$@\" >> '$docker_log'"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude \
        --tag my-custom-tag:v1

    [[ "$(cat "$docker_log")" == *"my-custom-tag:v1"* ]]

    rm -f "$docker_log"
    rm -rf "$workspace_dir"
}

# ── devcontainer build invocation ─────────────────────────────────────────────

@test "devcontainer build is called with workspace-folder and image-name" {
    local devcontainer_log workspace_dir
    devcontainer_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script devcontainer "echo \"\$@\" >> '$devcontainer_log'"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    local args
    args="$(cat "$devcontainer_log")"
    [[ "$args" == *"build"* ]]
    [[ "$args" == *"--workspace-folder"* ]]
    [[ "$args" == *"$workspace_dir"* ]]
    [[ "$args" == *"--image-name"* ]]
    [[ "$args" == *"worker-base-claude:latest"* ]]

    rm -f "$devcontainer_log"
    rm -rf "$workspace_dir"
}

# ── Dockerfile generation ─────────────────────────────────────────────────────

@test "generated Dockerfile starts with FROM worker-base-<agent>:latest" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    [[ "$output" == *"FROM worker-base-claude:latest"* ]]

    rm -rf "$workspace_dir"
}

@test "claude: Dockerfile installs Claude Code CLI" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    [[ "$output" == *"claude.ai/install.sh"* ]]

    rm -rf "$workspace_dir"
}

@test "copilot: Dockerfile installs gh CLI and @github/copilot" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type copilot

    [[ "$output" == *"gh"* ]]
    [[ "$output" == *"@github/copilot"* ]]

    rm -rf "$workspace_dir"
}

@test "codex: Dockerfile installs @openai/codex" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type codex

    [[ "$output" == *"@openai/codex"* ]]

    rm -rf "$workspace_dir"
}

@test "generated Dockerfile installs acli" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    [[ "$output" == *"acli"* ]]

    rm -rf "$workspace_dir"
}

@test "generated Dockerfile copies loop and claim" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    [[ "$output" == *"COPY claim/claim"* ]]
    [[ "$output" == *"COPY loop/loop"* ]]

    rm -rf "$workspace_dir"
}

# ── docker build / push ───────────────────────────────────────────────────────

@test "docker build is called with the generated tag" {
    local docker_log workspace_dir
    docker_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script docker "echo \"\$@\" >> '$docker_log'"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude \
        --tag test-image:v2

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"build"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log"
    rm -rf "$workspace_dir"
}

@test "--push: docker push is called after build" {
    local docker_log workspace_dir
    docker_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script docker "echo \"\$@\" >> '$docker_log'"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude \
        --tag test-image:v2 \
        --push

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"push"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log"
    rm -rf "$workspace_dir"
}

@test "without --push: docker push is NOT called" {
    local docker_log workspace_dir
    docker_log="$(mktemp)"
    workspace_dir="$(mktemp -d)"

    stub_script docker "echo \"\$@\" >> '$docker_log'"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude \
        --tag test-image:v2

    [[ "$(cat "$docker_log")" != *"push"* ]]

    rm -f "$docker_log"
    rm -rf "$workspace_dir"
}

@test "docker build failure propagates non-zero exit" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    stub_exit docker 1 "Build failed"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude

    [ "$status" -ne 0 ]

    rm -rf "$workspace_dir"
}

@test "prints Done message with image tag on success" {
    local workspace_dir
    workspace_dir="$(mktemp -d)"

    run "$WORKER_BUILDER" build \
        --devcontainer "$workspace_dir" \
        --type claude \
        --tag final-image:latest

    [ "$status" -eq 0 ]
    [[ "$output" == *"Done"* ]]
    [[ "$output" == *"final-image:latest"* ]]

    rm -rf "$workspace_dir"
}
