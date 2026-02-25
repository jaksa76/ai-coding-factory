#!/usr/bin/env bats
# Tests for worker-builder/worker-builder

WORKER_BUILDER="$BATS_TEST_DIRNAME/worker-builder"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Default stubs — overridden per test as needed
    stub git ""
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

# ── argument / option validation ──────────────────────────────────────────────

@test "error: missing --project" {
    run "$WORKER_BUILDER" --agent claude
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "error: missing --agent" {
    run "$WORKER_BUILDER" --project https://github.com/org/repo.git
    [ "$status" -eq 1 ]
    [[ "$output" == *"--agent"* ]]
}

@test "error: unknown option" {
    run "$WORKER_BUILDER" --project https://github.com/org/repo.git --agent claude --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "error: unknown agent type" {
    run "$WORKER_BUILDER" --project https://github.com/org/repo.git --agent llama
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown agent type"* ]]
    [[ "$output" == *"llama"* ]]
}

@test "error: --project requires a value" {
    run "$WORKER_BUILDER" --project --agent claude
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project requires a value"* ]]
}

@test "error: --agent requires a value" {
    run "$WORKER_BUILDER" --project https://github.com/org/repo.git --agent --push
    [ "$status" -eq 1 ]
    [[ "$output" == *"--agent requires a value"* ]]
}

@test "error: --tag requires a value" {
    run "$WORKER_BUILDER" --project https://github.com/org/repo.git --agent claude --tag
    [ "$status" -eq 1 ]
    [[ "$output" == *"--tag requires a value"* ]]
}

@test "--help prints usage" {
    run "$WORKER_BUILDER" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--project"* ]]
    [[ "$output" == *"--agent"* ]]
}

@test "-h prints usage" {
    run "$WORKER_BUILDER" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── default tag derivation ─────────────────────────────────────────────────────

@test "default tag includes repo name and agent" {
    local docker_log
    docker_log="$(mktemp)"

    # git archive fails → sparse clone path
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    clone)   ;;
    -C)      ;;
    *)       ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" --project https://github.com/org/myrepo.git --agent claude

    [[ "$(cat "$docker_log")" == *"worker-myrepo-claude:latest"* ]]

    rm -f "$docker_log"
}

@test "--tag overrides the default image tag" {
    local docker_log
    docker_log="$(mktemp)"

    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude \
        --tag my-custom-tag:v1

    [[ "$(cat "$docker_log")" == *"my-custom-tag:v1"* ]]

    rm -f "$docker_log"
}

# ── devcontainer fetch / parse ────────────────────────────────────────────────

@test "uses git archive when available" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$@\" >> '$git_log'
# Simulate git archive piping an empty tar (no devcontainer.json)
case \"\$1\" in
    archive) exit 0 ;;
    *) ;;
esac
"
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$(cat "$git_log")" == *"archive"* ]]

    rm -f "$git_log"
}

@test "falls back to sparse clone when git archive fails" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$@\" >> '$git_log'
case \"\$1\" in
    archive) exit 1 ;;
    *) ;;
esac
"
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$(cat "$git_log")" == *"clone"* ]]

    rm -f "$git_log"
}

@test "falls back to default base image when devcontainer.json not found" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$output" == *"devcontainer.json not found"* ]]
    [[ "$output" == *"mcr.microsoft.com/devcontainers/base:bullseye"* ]]
}

@test "git archive: uses image field from devcontainer.json" {
    stub_script git '
case "$1" in
    archive)
        tmpdir=$(mktemp -d)
        mkdir -p "$tmpdir/.devcontainer"
        printf '"'"'{"image": "node:18-bullseye"}'"'"' > "$tmpdir/.devcontainer/devcontainer.json"
        tar -c -C "$tmpdir" .devcontainer/devcontainer.json
        rm -rf "$tmpdir"
        ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    # Use the real jq for this test
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"node:18-bullseye"* ]]
    [[ "$output" == *"FROM node:18-bullseye"* ]]
}

@test "git archive: strips // comments from devcontainer.json before parsing" {
    stub_script git '
case "$1" in
    archive)
        tmpdir=$(mktemp -d)
        mkdir -p "$tmpdir/.devcontainer"
        printf '"'"'// project devcontainer\n{"image": "ubuntu:22.04" // base image\n}'"'"' \
            > "$tmpdir/.devcontainer/devcontainer.json"
        tar -c -C "$tmpdir" .devcontainer/devcontainer.json
        rm -rf "$tmpdir"
        ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"ubuntu:22.04"* ]]
    [[ "$output" == *"FROM ubuntu:22.04"* ]]
}

@test "sparse clone: uses image field from devcontainer.json" {
    stub_script git "
case \"\$1\" in
    archive) exit 1 ;;
    clone)
        # Destination is the last argument
        dest=\"\${@: -1}\"
        mkdir -p \"\$dest/.devcontainer\"
        printf '{\"image\": \"python:3.11-slim\"}' > \"\$dest/.devcontainer/devcontainer.json\"
        ;;
    -C) ;;   # sparse-checkout set / checkout — no-op
    *) ;;
esac
"
    stub_script docker "echo \"\$@\""
    rm -f "$STUB_DIR/jq"

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [ "$status" -eq 0 ]
    [[ "$output" == *"python:3.11-slim"* ]]
}

# ── Dockerfile generation ─────────────────────────────────────────────────────

@test "generated Dockerfile starts with FROM <base-image>" {
    local docker_log
    docker_log="$(mktemp)"

    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'; cat /dev/stdin 2>/dev/null || true"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$output" == *"FROM mcr.microsoft.com/devcontainers/base:bullseye"* ]]

    rm -f "$docker_log"
}

@test "claude: Dockerfile installs Claude Code CLI" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$output" == *"claude.ai/install.sh"* ]]
}

@test "copilot: Dockerfile installs gh CLI and @github/copilot" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent copilot

    [[ "$output" == *"gh"* ]]
    [[ "$output" == *"@github/copilot"* ]]
}

@test "codex: Dockerfile installs @openai/codex" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent codex

    [[ "$output" == *"@openai/codex"* ]]
}

@test "generated Dockerfile installs acli" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$output" == *"acli"* ]]
}

@test "generated Dockerfile copies loop and claim" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [[ "$output" == *"COPY claim/claim"* ]]
    [[ "$output" == *"COPY loop/loop"* ]]
}

# ── docker build / push ───────────────────────────────────────────────────────

@test "docker build is called with the generated tag" {
    local docker_log
    docker_log="$(mktemp)"

    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude \
        --tag test-image:v2

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"build"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log"
}

@test "--push: docker push is called after build" {
    local docker_log
    docker_log="$(mktemp)"

    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude \
        --tag test-image:v2 \
        --push

    local docker_args
    docker_args="$(cat "$docker_log")"
    [[ "$docker_args" == *"push"* ]]
    [[ "$docker_args" == *"test-image:v2"* ]]

    rm -f "$docker_log"
}

@test "without --push: docker push is NOT called" {
    local docker_log
    docker_log="$(mktemp)"

    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\" >> '$docker_log'"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude \
        --tag test-image:v2

    [[ "$(cat "$docker_log")" != *"push"* ]]

    rm -f "$docker_log"
}

@test "docker build failure propagates non-zero exit" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_exit docker 1 "Build failed"
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude

    [ "$status" -ne 0 ]
}

@test "prints Done message with image tag on success" {
    stub_script git '
case "$1" in
    archive) exit 1 ;;
    *) ;;
esac
'
    stub_script docker "echo \"\$@\""
    stub_script jq 'printf ""'

    run "$WORKER_BUILDER" \
        --project https://github.com/org/repo.git \
        --agent claude \
        --tag final-image:latest

    [ "$status" -eq 0 ]
    [[ "$output" == *"Done"* ]]
    [[ "$output" == *"final-image:latest"* ]]
}
