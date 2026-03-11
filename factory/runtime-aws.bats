#!/usr/bin/env bats
# Tests for factory/runtime-aws

RUNTIME="$BATS_TEST_DIRNAME/runtime-aws"

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Default env for all tests
    export FACTORY_AWS_REGION="us-east-1"
    export FACTORY_AWS_CLUSTER="test-cluster"
    export FACTORY_AWS_SUBNET_ID="subnet-abc"
    export FACTORY_AWS_SECURITY_GROUP_ID="sg-abc"
    export FACTORY_AWS_LOG_GROUP="/ecs/test"
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

# Default aws stub that handles common calls
default_aws_stub() {
    local calls_file="${1:-/dev/null}"
    stub_script aws "
        echo \"\$@\" >> '$calls_file'
        case \"\$2\" in
            describe-clusters)  echo 'ACTIVE' ;;
            describe-log-groups) echo '/ecs/test' ;;
            get-role)           echo 'ecsTaskExecutionRole' ;;
            register-task-definition) echo 'arn:aws:ecs:us-east-1:123456789012:task-definition/ai-coding-factory-myworker:1' ;;
            run-task)           echo 'arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123' ;;
            get-caller-identity) echo '123456789012' ;;
            stop-task)          echo 'STOPPED' ;;
            list-tasks)         echo '[]' ;;
        esac
    "
}

# ── add ───────────────────────────────────────────────────────────────────────

@test "add: registers a task definition and runs an ECS task" {
    local calls_file
    calls_file="$(mktemp)"
    default_aws_stub "$calls_file"

    run "$RUNTIME" add myworker myimage
    [ "$status" -eq 0 ]

    local calls
    calls="$(cat "$calls_file")"
    [[ "$calls" == *"register-task-definition"* ]]
    [[ "$calls" == *"run-task"* ]]

    rm -f "$calls_file"
}

@test "add: creates ECS cluster if it doesn't exist" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script aws "
        echo \"\$@\" >> '$calls_file'
        case \"\$2\" in
            describe-clusters)  echo 'INACTIVE' ;;
            create-cluster)     echo 'ai-coding-factory' ;;
            describe-log-groups) echo '/ecs/test' ;;
            get-role)           echo 'ecsTaskExecutionRole' ;;
            register-task-definition) echo 'arn:aws:ecs:us-east-1:123456789012:task-definition/ai-coding-factory-myworker:1' ;;
            run-task)           echo 'arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123' ;;
            get-caller-identity) echo '123456789012' ;;
        esac
    "

    run "$RUNTIME" add myworker myimage
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"create-cluster"* ]]

    rm -f "$calls_file"
}

@test "add: passes env vars from --env-file into the task definition" {
    local calls_file env_file
    calls_file="$(mktemp)"
    env_file="$(mktemp)"
    printf 'MY_VAR=hello\nOTHER_VAR=world\n' > "$env_file"

    local task_def_file
    task_def_file="$(mktemp)"
    stub_script aws "
        echo \"\$@\" >> '$calls_file'
        # Capture task def JSON
        if [[ \"\$2\" == 'register-task-definition' ]]; then
            # Find --cli-input-json value and save it
            while [[ \$# -gt 0 ]]; do
                if [[ \"\$1\" == '--cli-input-json' ]]; then
                    echo \"\$2\" > '$task_def_file'
                fi
                shift
            done
            echo 'arn:aws:ecs:us-east-1:123456789012:task-definition/ai-coding-factory-myworker:1'
        elif [[ \"\$2\" == 'describe-clusters' ]]; then
            echo 'ACTIVE'
        elif [[ \"\$2\" == 'describe-log-groups' ]]; then
            echo '/ecs/test'
        elif [[ \"\$2\" == 'get-role' ]]; then
            echo 'ecsTaskExecutionRole'
        elif [[ \"\$2\" == 'run-task' ]]; then
            echo 'arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123'
        elif [[ \"\$2\" == 'get-caller-identity' ]]; then
            echo '123456789012'
        fi
    "

    run "$RUNTIME" add myworker myimage --env-file "$env_file"
    [ "$status" -eq 0 ]

    local task_def
    task_def="$(cat "$task_def_file")"
    [[ "$task_def" == *"MY_VAR"* ]]
    [[ "$task_def" == *"hello"* ]]

    rm -f "$calls_file" "$env_file" "$task_def_file"
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

@test "status: returns formatted table of running tasks" {
    stub_script aws "
        case \"\$2\" in
            list-tasks)
                echo '[\"arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123\"]'
                ;;
            describe-tasks)
                cat <<'JSON'
{\"tasks\":[{\"taskArn\":\"arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123\",\"lastStatus\":\"RUNNING\",\"containers\":[{\"name\":\"myworker\",\"image\":\"myimage\"}],\"tags\":[{\"key\":\"ai-coding-factory.worker\",\"value\":\"true\"}]}]}
JSON
                ;;
        esac
    "

    run "$RUNTIME" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"abc123"* ]]
    [[ "$output" == *"RUNNING"* ]]
    [[ "$output" == *"myimage"* ]]
}

@test "status: returns empty table when no tasks" {
    stub_script aws "echo '[]'"

    run "$RUNTIME" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"ID"* ]]
}

# ── stop ──────────────────────────────────────────────────────────────────────

@test "stop: calls ecs stop-task with correct cluster and task ARN" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script aws "echo \"\$@\" > '$calls_file'"

    run "$RUNTIME" stop "arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123"
    [ "$status" -eq 0 ]

    local args
    args="$(cat "$calls_file")"
    [[ "$args" == *"stop-task"* ]]
    [[ "$args" == *"test-cluster"* ]]
    [[ "$args" == *"abc123"* ]]

    rm -f "$calls_file"
}

@test "stop: requires task-arn" {
    run "$RUNTIME" stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"task-arn is required"* ]]
}

# ── stop-all ──────────────────────────────────────────────────────────────────

@test "stop-all: stops every task with the factory label" {
    local calls_file
    calls_file="$(mktemp)"
    stub_script aws "
        echo \"\$@\" >> '$calls_file'
        if [[ \"\$2\" == 'list-tasks' ]]; then
            echo 'arn:aws:ecs:us-east-1:123:task/cluster/task1'
            echo 'arn:aws:ecs:us-east-1:123:task/cluster/task2'
        fi
    "

    run "$RUNTIME" stop-all
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"stop-task"* ]]

    rm -f "$calls_file"
}

@test "stop-all: prints message when no tasks running" {
    stub_script aws "
        if [[ \"\$2\" == 'list-tasks' ]]; then
            echo ''
        fi
    "

    run "$RUNTIME" stop-all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No running workers"* ]]
}

# ── defaults ──────────────────────────────────────────────────────────────────

@test "missing FACTORY_AWS_REGION defaults to us-east-1" {
    local calls_file
    calls_file="$(mktemp)"
    default_aws_stub "$calls_file"

    unset FACTORY_AWS_REGION
    unset AWS_DEFAULT_REGION

    run "$RUNTIME" add myworker myimage
    [ "$status" -eq 0 ]

    [[ "$(cat "$calls_file")" == *"us-east-1"* ]]

    rm -f "$calls_file"
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
