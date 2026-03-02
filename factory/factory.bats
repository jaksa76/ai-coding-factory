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

# ── add ───────────────────────────────────────────────────────────────────────

@test "add: requires --image" {
    run "$FACTORY" add 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"--image is required"* ]]
}

@test "add: requires count" {
    stub docker ""
    run "$FACTORY" add --image myimage
    [ "$status" -eq 1 ]
    [[ "$output" == *"count is required"* ]]
}

@test "add: count must be numeric" {
    stub docker ""
    run "$FACTORY" add --image myimage notanumber
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a positive integer"* ]]
}

@test "add: launches N containers" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image myimage 3
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 3 ]

    rm -f "$calls_file"
}

@test "add: passes worker label to docker run" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image myimage 1
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"ai-coding-factory.worker"* ]]

    rm -f "$calls_file"
}

@test "add: passes image name to docker run" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image my-worker-image 1
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"my-worker-image"* ]]

    rm -f "$calls_file"
}

@test "add: passes --restart=on-failure to docker run" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image myimage 1
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"--restart=on-failure"* ]]

    rm -f "$calls_file"
}

@test "add: docker failure propagates non-zero exit" {
    stub_exit docker 1 "Unable to find image"
    run "$FACTORY" add --image myimage 1
    [ "$status" -ne 0 ]
}

# ── logs ──────────────────────────────────────────────────────────────────────

@test "logs: requires worker-id" {
    run "$FACTORY" logs
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id is required"* ]]
}

@test "logs: calls docker logs -f with worker-id" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" logs abc123
    [ "$status" -eq 0 ]

    local docker_args
    docker_args="$(cat "$calls_file")"
    [[ "$docker_args" == *"logs"* ]]
    [[ "$docker_args" == *"-f"* ]]
    [[ "$docker_args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "logs: docker failure propagates non-zero exit" {
    stub_exit docker 1 "No such container"
    run "$FACTORY" logs nonexistent
    [ "$status" -ne 0 ]
}

# ── stop ──────────────────────────────────────────────────────────────────────

@test "stop: requires worker-id or --all" {
    run "$FACTORY" stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id or --all is required"* ]]
}

@test "stop: stops a specific worker" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script docker "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" stop abc123
    [ "$status" -eq 0 ]

    local docker_args
    docker_args="$(cat "$calls_file")"
    [[ "$docker_args" == *"stop"* ]]
    [[ "$docker_args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "stop --all: stops all running workers" {
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

    run "$FACTORY" stop --all
    [ "$status" -eq 0 ]

    local docker_args
    docker_args="$(cat "$calls_file")"
    [[ "$docker_args" == *"stop"* ]]
    [[ "$docker_args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "stop --all: prints message when no workers running" {
    stub_script docker "
        if [[ \"\$1\" == 'ps' ]]; then
            echo ''
        fi
    "

    run "$FACTORY" stop --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No running workers"* ]]
}

@test "stop: docker failure propagates non-zero exit" {
    stub_exit docker 1 "No such container"
    run "$FACTORY" stop nonexistent
    [ "$status" -ne 0 ]
}
