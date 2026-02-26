#!/usr/bin/env bats
# Unit tests for workers/claude/run-claude.sh

RUN_CLAUDE="$BATS_TEST_DIRNAME/run-claude.sh"

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    FAKE_HOME="$(mktemp -d)"
    export HOME="$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude"

    # Stub init-claude so token refresh is a no-op
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_DIR/init-claude"
    chmod +x "$STUB_DIR/init-claude"

    # Capture file for claude invocations
    CLAUDE_ARGS_FILE="$(mktemp)"
    export CLAUDE_ARGS_FILE

    # Stub claude to record args and print a fixed response
    cat > "$STUB_DIR/claude" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_ARGS_FILE"
echo "stub response"
EOF
    chmod +x "$STUB_DIR/claude"
}

teardown() {
    rm -rf "$STUB_DIR" "$FAKE_HOME"
    rm -f "$CLAUDE_ARGS_FILE"
}

@test "run-claude: passes --verbose to claude" {
    run bash "$RUN_CLAUDE" -p "hello"
    [ "$status" -eq 0 ]
    ARGS="$(cat "$CLAUDE_ARGS_FILE")"
    [[ "$ARGS" == *"--verbose"* ]]
}

@test "run-claude: --verbose appears before forwarded arguments" {
    run bash "$RUN_CLAUDE" --dangerously-skip-permissions -p "test prompt"
    [ "$status" -eq 0 ]
    ARGS="$(cat "$CLAUDE_ARGS_FILE")"
    # --verbose must be present and forwarded args must also be present
    [[ "$ARGS" == *"--verbose"* ]]
    [[ "$ARGS" == *"--dangerously-skip-permissions"* ]]
    [[ "$ARGS" == *"-p"* ]]
    [[ "$ARGS" == *"test prompt"* ]]
}

@test "run-claude: forwards all arguments to claude" {
    run bash "$RUN_CLAUDE" --dangerously-skip-permissions -p "my prompt"
    [ "$status" -eq 0 ]
    ARGS="$(cat "$CLAUDE_ARGS_FILE")"
    [[ "$ARGS" == *"--dangerously-skip-permissions"* ]]
    [[ "$ARGS" == *"-p"* ]]
    [[ "$ARGS" == *"my prompt"* ]]
}

@test "run-claude: calls init-claude --refresh" {
    INIT_LOG="$(mktemp)"
    cat > "$STUB_DIR/init-claude" << EOF
#!/usr/bin/env bash
echo "\$@" >> "$INIT_LOG"
exit 0
EOF
    chmod +x "$STUB_DIR/init-claude"

    run bash "$RUN_CLAUDE" -p "test"
    [ "$status" -eq 0 ]
    [[ "$(cat "$INIT_LOG")" == *"--refresh"* ]]
    rm -f "$INIT_LOG"
}

@test "run-claude: exits non-zero if init-claude fails" {
    printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_DIR/init-claude"
    chmod +x "$STUB_DIR/init-claude"

    run bash "$RUN_CLAUDE" -p "test"
    [ "$status" -ne 0 ]
}

@test "run-claude: prints claude output to stdout" {
    run bash "$RUN_CLAUDE" -p "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stub response"* ]]
}
