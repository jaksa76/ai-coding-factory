#!/usr/bin/env bats
# Unit tests for workers/claude/agent

AGENT="$BATS_TEST_DIRNAME/agent"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Temp HOME so credentials land in a throwaway directory
    FAKE_HOME="$(mktemp -d)"
    export HOME="$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude"

    # Default required env vars for OAuth mode
    export CLAUDE_ACCESS_TOKEN="test-access-token"
    export CLAUDE_REFRESH_TOKEN="test-refresh-token"
    export CLAUDE_TOKEN_EXPIRES_AT="9999999999000"
    export CLAUDE_SUBSCRIPTION_TYPE="pro"

    # Default stub for claude CLI
    stub claude ""
}

teardown() {
    rm -rf "$STUB_DIR" "$FAKE_HOME"
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

# ── agent init: API key mode ──────────────────────────────────────────────────

@test "init: api key mode — exits 0 when ANTHROPIC_API_KEY is set" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run "$AGENT" init
    [ "$status" -eq 0 ]
}

@test "init: api key mode — does not write credentials file" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run "$AGENT" init
    [ "$status" -eq 0 ]
    [ ! -f "$FAKE_HOME/.claude/.credentials.json" ]
}

@test "init: api key mode — prints informational message" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run "$AGENT" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
}

@test "init: api key mode — does not require OAuth vars" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    unset CLAUDE_ACCESS_TOKEN
    unset CLAUDE_REFRESH_TOKEN
    unset CLAUDE_TOKEN_EXPIRES_AT
    unset CLAUDE_SUBSCRIPTION_TYPE
    run "$AGENT" init
    [ "$status" -eq 0 ]
}

# ── agent init: OAuth mode ────────────────────────────────────────────────────

@test "init: oauth mode — writes credentials file" {
    run "$AGENT" init
    [ "$status" -eq 0 ]
    [ -f "$FAKE_HOME/.claude/.credentials.json" ]
    ACCESS="$(jq -r '.claudeAiOauth.accessToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$ACCESS" == "test-access-token" ]]
}

@test "init: oauth mode — prints success message" {
    run "$AGENT" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"initialized"* ]]
}

@test "init: oauth mode — error when CLAUDE_ACCESS_TOKEN missing" {
    unset CLAUDE_ACCESS_TOKEN
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_ACCESS_TOKEN"* ]]
}

@test "init: oauth mode — error when CLAUDE_REFRESH_TOKEN missing" {
    unset CLAUDE_REFRESH_TOKEN
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_REFRESH_TOKEN"* ]]
}

@test "init: oauth mode — error when CLAUDE_TOKEN_EXPIRES_AT missing" {
    unset CLAUDE_TOKEN_EXPIRES_AT
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_TOKEN_EXPIRES_AT"* ]]
}

@test "init: oauth mode — error when CLAUDE_SUBSCRIPTION_TYPE missing" {
    unset CLAUDE_SUBSCRIPTION_TYPE
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_SUBSCRIPTION_TYPE"* ]]
}

# ── agent run ─────────────────────────────────────────────────────────────────

@test "run: invokes claude with --dangerously-skip-permissions and -p flags" {
    local claude_log
    claude_log="$(mktemp)"
    stub_script claude "echo \"\$*\" >> '$claude_log'"

    run "$AGENT" run "hello world"

    [[ "$(cat "$claude_log")" == *"--dangerously-skip-permissions"* ]]
    [[ "$(cat "$claude_log")" == *"-p"* ]]
    [[ "$(cat "$claude_log")" == *"hello world"* ]]

    rm -f "$claude_log"
}

@test "run: passes full prompt as a single argument to claude" {
    local claude_log
    claude_log="$(mktemp)"
    stub_script claude "printf '%s\n' \"\$@\" >> '$claude_log'"

    run "$AGENT" run "multi word prompt with spaces"

    # The prompt should appear as a single entry (not split across lines)
    grep -q "^multi word prompt with spaces$" "$claude_log"

    rm -f "$claude_log"
}

@test "run: exit code mirrors claude exit code on success" {
    stub_exit claude 0 ""

    run "$AGENT" run "prompt"

    [ "$status" -eq 0 ]
}

@test "run: exit code mirrors claude exit code on failure" {
    stub_exit claude 42 ""

    run "$AGENT" run "prompt"

    [ "$status" -eq 42 ]
}

# ── usage / unknown subcommand ─────────────────────────────────────────────────

@test "no subcommand: exits 1 with usage message" {
    run "$AGENT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown subcommand: exits 1 with usage message" {
    run "$AGENT" foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
