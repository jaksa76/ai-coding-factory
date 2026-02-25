#!/usr/bin/env bats
# Tests for factory/factory

FACTORY="$BATS_TEST_DIRNAME/factory"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"
}

teardown() {
    rm -rf "$STUB_DIR"
}

stub() {
    local cmd="$1"
    local out="${2:-}"
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

# ── argument / command validation ─────────────────────────────────────────────

@test "no args: prints usage" {
    run "$FACTORY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--help prints usage" {
    run "$FACTORY" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run "$FACTORY" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown command: error" {
    run "$FACTORY" unknown-cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# ── status ────────────────────────────────────────────────────────────────────

@test "status: exits 0 and returns docker ps output" {
    stub docker "CONTAINER ID   IMAGE          STATUS      NAMES"
    run "$FACTORY" status
    [ "$status" -eq 0 ]
}

@test "status: lists running workers" {
    stub_script docker 'printf "CONTAINER ID\tIMAGE\tSTATUS\tNAMES\nabc123\tworker-claude\tUp 2 hours\tfactory-worker-1\n789xyz\tworker-claude\tUp 1 hour\tfactory-worker-2\n"'
    run "$FACTORY" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"factory-worker-1"* ]]
    [[ "$output" == *"factory-worker-2"* ]]
}

@test "status: passes factory worker label filter to docker ps" {
    local called_file
    called_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$called_file'"

    run "$FACTORY" status
    [ "$status" -eq 0 ]

    local docker_args
    docker_args="$(cat "$called_file")"
    [[ "$docker_args" == *"ai-coding-factory.worker"* ]]

    rm -f "$called_file"
}

@test "status: docker failure propagates non-zero exit" {
    stub_exit docker 1 "Cannot connect to the Docker daemon"
    run "$FACTORY" status
    [ "$status" -ne 0 ]
}
