#!/usr/bin/env bats
# Tests for factory/runtime-docker

RUNTIME="$BATS_TEST_DIRNAME/runtime-docker"

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"
}

teardown() {
    rm -rf "$STUB_DIR"
}

stub_script() {
    local cmd="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

stub_exit() {
    local cmd="$1" code="$2" out="${3:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\nexit %d\n' "$out" "$code" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# ── add ───────────────────────────────────────────────────────────────────────

@test "add: runs docker run with label, name, and image" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" add my-worker myimage
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"run"* ]]
    [[ "$args" == *"ai-coding-factory.worker"* ]]
    [[ "$args" == *"my-worker"* ]]
    [[ "$args" == *"myimage"* ]]

    rm -f "$calls_file"
}

@test "add: passes --env-file to docker run when provided" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" add my-worker myimage --env-file "$env_file"
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"--env-file"* ]]
    [[ "$args" == *"$env_file"* ]]

    rm -f "$calls_file" "$env_file"
}

@test "add: does not pass --env-file when not provided" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" add my-worker myimage
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" != *"--env-file"* ]]

    rm -f "$calls_file"
}

@test "add: passes --restart=no to docker run" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" add my-worker myimage
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"--restart=no"* ]]

    rm -f "$calls_file"
}

@test "add: requires name" {
    run "$RUNTIME" add
    [ "$status" -eq 1 ]
    [[ "$output" == *"name is required"* ]]
}

@test "add: requires image" {
    run "$RUNTIME" add myname
    [ "$status" -eq 1 ]
    [[ "$output" == *"image is required"* ]]
}

# ── status ────────────────────────────────────────────────────────────────────

@test "status: calls docker ps with factory worker label filter" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" status
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"ai-coding-factory.worker"* ]]

    rm -f "$calls_file"
}

@test "status: docker failure propagates non-zero exit" {
    stub_exit docker 1 "Cannot connect"
    run "$RUNTIME" status
    [ "$status" -ne 0 ]
}

# ── logs ──────────────────────────────────────────────────────────────────────

@test "logs: calls docker logs -f with the given ID" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" logs abc123
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"logs"* ]]
    [[ "$args" == *"-f"* ]]
    [[ "$args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "logs: requires worker-id" {
    run "$RUNTIME" logs
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id is required"* ]]
}

# ── stop ──────────────────────────────────────────────────────────────────────

@test "stop: calls docker stop with the given ID" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" stop abc123
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"stop"* ]]
    [[ "$args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "stop: requires worker-id" {
    run "$RUNTIME" stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id is required"* ]]
}

# ── stop-all ──────────────────────────────────────────────────────────────────

@test "stop-all: stops every container with the factory label" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "
        if [[ \"\$1\" == 'ps' ]]; then
            echo 'abc123'
            echo 'def456'
        else
            echo \"\$@\" >> '$calls_file'
        fi
    "

    run "$RUNTIME" stop-all
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"stop"* ]]
    [[ "$args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "stop-all: prints message when no workers running" {
    stub_script docker "
        if [[ \"\$1\" == 'ps' ]]; then
            echo ''
        fi
    "

    run "$RUNTIME" stop-all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No running workers"* ]]
}

# ── unknown subcommand ────────────────────────────────────────────────────────

@test "unknown subcommand: error" {
    run "$RUNTIME" bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown subcommand"* ]]
}

@test "no args: error" {
    run "$RUNTIME"
    [ "$status" -eq 1 ]
    [[ "$output" == *"subcommand is required"* ]]
}
