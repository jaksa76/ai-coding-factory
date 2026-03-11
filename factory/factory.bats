#!/usr/bin/env bats
# Tests for factory/factory

FACTORY="$BATS_TEST_DIRNAME/factory"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Create a runtime stub in the same dir as factory, so factory finds it
    RUNTIME_STUB="$BATS_TEST_DIRNAME/runtime"
    _orig_runtime="$(readlink "$RUNTIME_STUB" 2>/dev/null || true)"
}

teardown() {
    rm -rf "$STUB_DIR"
    # Restore original runtime symlink if we changed it
    if [[ -n "${_RUNTIME_STUB_INSTALLED:-}" ]]; then
        ln -sf "${_orig_runtime:-runtime-docker}" "$BATS_TEST_DIRNAME/runtime"
        unset _RUNTIME_STUB_INSTALLED
    fi
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

# Install a runtime stub at factory/runtime (replaces the symlink temporarily)
install_runtime_stub() {
    local body="$1"
    rm -f "$BATS_TEST_DIRNAME/runtime"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$BATS_TEST_DIRNAME/runtime"
    chmod +x "$BATS_TEST_DIRNAME/runtime"
    _RUNTIME_STUB_INSTALLED=1
}

restore_runtime_symlink() {
    rm -f "$BATS_TEST_DIRNAME/runtime"
    ln -sf "runtime-docker" "$BATS_TEST_DIRNAME/runtime"
    unset _RUNTIME_STUB_INSTALLED
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

@test "status: delegates to runtime status" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" status
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == "status" ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "status: runtime failure propagates non-zero exit" {
    install_runtime_stub "exit 1"

    run "$FACTORY" status
    [ "$status" -ne 0 ]

    restore_runtime_symlink
}

# ── add ───────────────────────────────────────────────────────────────────────

@test "add: requires --image" {
    run "$FACTORY" add 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"--image is required"* ]]
}

@test "add: requires count" {
    install_runtime_stub "echo \"\$@\""
    run "$FACTORY" add --image myimage
    [ "$status" -eq 1 ]
    [[ "$output" == *"count is required"* ]]
    restore_runtime_symlink
}

@test "add: count must be numeric" {
    install_runtime_stub "echo \"\$@\""
    run "$FACTORY" add --image myimage notanumber
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a positive integer"* ]]
    restore_runtime_symlink
}

@test "add: calls runtime add N times" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image myimage 3
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 3 ]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "add: passes image name to runtime add" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image my-worker-image 1
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"my-worker-image"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "add: runtime failure propagates non-zero exit" {
    install_runtime_stub "exit 1"
    run "$FACTORY" add --image myimage 1
    [ "$status" -ne 0 ]
    restore_runtime_symlink
}

@test "add: --env-file passes --env-file to runtime add" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image myimage --env-file "$env_file" 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"--env-file"* ]]
    [[ "$(cat "$calls_file")" == *"$env_file"* ]]

    restore_runtime_symlink
    rm -f "$calls_file" "$env_file"
}

@test "add: --env-file errors when file does not exist" {
    run "$FACTORY" add --image myimage --env-file /no/such/file 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"env file not found"* ]]
}

@test "add: FACTORY_ENV_FILE is used when no --env-file flag" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    FACTORY_ENV_FILE="$env_file" run "$FACTORY" add --image myimage 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"--env-file"* ]]
    [[ "$(cat "$calls_file")" == *"$env_file"* ]]

    restore_runtime_symlink
    rm -f "$calls_file" "$env_file"
}

# ── workers ───────────────────────────────────────────────────────────────────

@test "workers: defaults to 1 worker using worker-claude image" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" workers
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 1 ]
    [[ "$(cat "$calls_file")" == *"worker-claude"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "workers: starts N workers" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" workers 3
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 3 ]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "workers: FACTORY_WORKER_IMAGE overrides default image" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    FACTORY_WORKER_IMAGE=my-custom-worker run "$FACTORY" workers 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"my-custom-worker"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "workers: --env-file passes --env-file to runtime add" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" workers --env-file "$env_file" 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"--env-file"* ]]
    [[ "$(cat "$calls_file")" == *"$env_file"* ]]

    restore_runtime_symlink
    rm -f "$calls_file" "$env_file"
}

# ── planners ──────────────────────────────────────────────────────────────────

@test "planners: defaults to 1 worker using planner-claude image" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" planners
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 1 ]
    [[ "$(cat "$calls_file")" == *"planner-claude"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "planners: starts N planners" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" planners 2
    [ "$status" -eq 0 ]

    local call_count
    call_count="$(wc -l < "$calls_file")"
    [ "$call_count" -eq 2 ]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "planners: FACTORY_PLANNER_IMAGE overrides default image" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    FACTORY_PLANNER_IMAGE=my-custom-planner run "$FACTORY" planners 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"my-custom-planner"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "planners: --env-file passes --env-file to runtime add" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" planners --env-file "$env_file" 1
    [ "$status" -eq 0 ]
    [[ "$(cat "$calls_file")" == *"--env-file"* ]]
    [[ "$(cat "$calls_file")" == *"$env_file"* ]]

    restore_runtime_symlink
    rm -f "$calls_file" "$env_file"
}

# ── logs ──────────────────────────────────────────────────────────────────────

@test "logs: requires worker-id" {
    run "$FACTORY" logs
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id is required"* ]]
}

@test "logs: delegates to runtime logs with worker-id" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" logs abc123
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"logs"* ]]
    [[ "$args" == *"abc123"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "logs: runtime failure propagates non-zero exit" {
    install_runtime_stub "exit 1"
    run "$FACTORY" logs nonexistent
    [ "$status" -ne 0 ]
    restore_runtime_symlink
}

# ── stop ──────────────────────────────────────────────────────────────────────

@test "stop: requires worker-id or --all" {
    run "$FACTORY" stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"worker-id or --all is required"* ]]
}

@test "stop: delegates to runtime stop with worker-id" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" stop abc123
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"stop"* ]]
    [[ "$args" == *"abc123"* ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "stop --all: delegates to runtime stop-all" {
    local calls_file
    calls_file="$(mktemp)"
    install_runtime_stub "echo \"\$@\" > '$calls_file'"

    run "$FACTORY" stop --all
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == "stop-all" ]]

    restore_runtime_symlink
    rm -f "$calls_file"
}

@test "stop: runtime failure propagates non-zero exit" {
    install_runtime_stub "exit 1"
    run "$FACTORY" stop nonexistent
    [ "$status" -ne 0 ]
    restore_runtime_symlink
}

# ── import-claude-credentials ─────────────────────────────────────────────────

make_creds() {
    local home="$1"
    mkdir -p "$home/.claude"
    printf '{"claudeAiOauth":{"accessToken":"tok123","refreshToken":"ref456","expiresAt":9999999,"subscriptionType":"pro"}}' \
        > "$home/.claude/.credentials.json"
}

@test "import-claude-credentials: requires --env-file" {
    run "$FACTORY" import-claude-credentials
    [ "$status" -eq 1 ]
    [[ "$output" == *"--env-file is required"* ]]
}

@test "import-claude-credentials: requires credentials file to exist" {
    local fake_home
    fake_home="$(mktemp -d)"
    run env HOME="$fake_home" "$FACTORY" import-claude-credentials --env-file "$fake_home/test.env"
    [ "$status" -eq 1 ]
    [[ "$output" == *"credentials file not found"* ]]
    rm -rf "$fake_home"
}

@test "import-claude-credentials: writes all four vars to a new env file" {
    local fake_home env_file
    fake_home="$(mktemp -d)"
    env_file="$fake_home/test.env"
    make_creds "$fake_home"

    run env HOME="$fake_home" "$FACTORY" import-claude-credentials --env-file "$env_file"
    [ "$status" -eq 0 ]

    [[ "$(cat "$env_file")" == *"CLAUDE_ACCESS_TOKEN=tok123"* ]]
    [[ "$(cat "$env_file")" == *"CLAUDE_REFRESH_TOKEN=ref456"* ]]
    [[ "$(cat "$env_file")" == *"CLAUDE_TOKEN_EXPIRES_AT=9999999"* ]]
    [[ "$(cat "$env_file")" == *"CLAUDE_SUBSCRIPTION_TYPE=pro"* ]]

    rm -rf "$fake_home"
}

@test "import-claude-credentials: updates existing credentials, preserves other vars" {
    local fake_home env_file
    fake_home="$(mktemp -d)"
    env_file="$fake_home/test.env"
    make_creds "$fake_home"

    printf 'OTHER_VAR=x\nCLAUDE_ACCESS_TOKEN=old\nCLAUDE_REFRESH_TOKEN=old\n' > "$env_file"

    run env HOME="$fake_home" "$FACTORY" import-claude-credentials --env-file "$env_file"
    [ "$status" -eq 0 ]

    [[ "$(cat "$env_file")" == *"OTHER_VAR=x"* ]]
    [[ "$(cat "$env_file")" == *"CLAUDE_ACCESS_TOKEN=tok123"* ]]
    [[ "$(cat "$env_file")" != *"CLAUDE_ACCESS_TOKEN=old"* ]]

    rm -rf "$fake_home"
}

@test "import-claude-credentials: unknown option: error" {
    run "$FACTORY" import-claude-credentials --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ── image auto-build ──────────────────────────────────────────────────────────

# Installs a docker stub that tracks build calls.
# $1 = docker_calls_file path
# $2 = inspect exit code (0=exists, 1=not found)
# $3 = created timestamp returned by inspect --format (default: future date)
install_docker_stub() {
    local docker_calls_file="$1"
    local inspect_exit="${2:-0}"
    local created="${3:-2099-01-01T00:00:00.000000000Z}"
    stub_script "docker" "
        case \"\$1\" in
            image)
                if [[ \"\$*\" == *'--format'* ]]; then
                    echo '$created'
                    exit $inspect_exit
                fi
                exit $inspect_exit
                ;;
            build)
                echo \"\$@\" >> '$docker_calls_file'
                exit 0
                ;;
        esac
    "
}

@test "add: auto-builds missing image when using docker runtime (worker-claude)" {
    local calls_file docker_calls_file
    calls_file="$(mktemp)"
    docker_calls_file="$(mktemp)"

    install_docker_stub "$docker_calls_file" 1
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image worker-claude 1
    [ "$status" -eq 0 ]
    grep -q 'build' "$docker_calls_file"
    grep -q 'worker-claude' "$docker_calls_file"

    restore_runtime_symlink
    rm -f "$calls_file" "$docker_calls_file"
}

@test "add: rebuilds outdated image when using docker runtime" {
    local calls_file docker_calls_file
    calls_file="$(mktemp)"
    docker_calls_file="$(mktemp)"

    # Inspect succeeds but returns epoch 0 (very old) — source files will be newer
    install_docker_stub "$docker_calls_file" 0 "1970-01-01T00:00:00.000000000Z"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image worker-claude 1
    [ "$status" -eq 0 ]
    grep -q 'build' "$docker_calls_file"

    restore_runtime_symlink
    rm -f "$calls_file" "$docker_calls_file"
}

@test "add: skips rebuild when image is up to date" {
    local calls_file docker_calls_file
    calls_file="$(mktemp)"
    docker_calls_file="$(mktemp)"

    # Inspect succeeds with a far-future date — no source file will be newer
    install_docker_stub "$docker_calls_file" 0 "2099-01-01T00:00:00.000000000Z"
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image worker-claude 1
    [ "$status" -eq 0 ]
    # docker_calls_file should be empty (no build call)
    [ ! -s "$docker_calls_file" ]

    restore_runtime_symlink
    rm -f "$calls_file" "$docker_calls_file"
}

@test "add: skips auto-build for unknown image" {
    local calls_file docker_calls_file
    calls_file="$(mktemp)"
    docker_calls_file="$(mktemp)"

    install_docker_stub "$docker_calls_file" 1
    install_runtime_stub "echo \"\$@\" >> '$calls_file'"

    run "$FACTORY" add --image custom-unknown-image 1
    [ "$status" -eq 0 ]
    # docker build should NOT have been called
    [ ! -s "$docker_calls_file" ]

    restore_runtime_symlink
    rm -f "$calls_file" "$docker_calls_file"
}

