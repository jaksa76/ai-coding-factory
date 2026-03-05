#!/usr/bin/env bats
# Unit tests for workers/claude/init-claude.sh

INIT_CLAUDE="$BATS_TEST_DIRNAME/init-claude.sh"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Temp HOME so credentials land in a throwaway directory
    FAKE_HOME="$(mktemp -d)"
    export HOME="$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude"

    # Default required env vars for initial-setup mode
    export CLAUDE_ACCESS_TOKEN="test-access-token"
    export CLAUDE_REFRESH_TOKEN="test-refresh-token"
    export CLAUDE_TOKEN_EXPIRES_AT="9999999999000"
    export CLAUDE_SUBSCRIPTION_TYPE="pro"

    # Stub sleep so tests don't wait
    stub sleep ""
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

# Write a credentials file with given expiresAt (epoch ms)
write_creds() {
    local expires_at="${1:-9999999999000}"
    local refresh_token="${2:-test-refresh-token}"
    local access_token="${3:-test-access-token}"
    jq -n \
        --arg at "$access_token" \
        --arg rt "$refresh_token" \
        --argjson ea "$expires_at" \
        '{claudeAiOauth:{accessToken:$at,refreshToken:$rt,expiresAt:$ea,subscriptionType:"pro",rateLimitTier:"default_claude_ai"}}' \
        > "$FAKE_HOME/.claude/.credentials.json"
}

# ── ANTHROPIC_API_KEY mode ────────────────────────────────────────────────────

@test "api key mode: exits 0 when ANTHROPIC_API_KEY is set" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
}

@test "api key mode: does not write credentials file" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
    [ ! -f "$FAKE_HOME/.claude/.credentials.json" ]
}

@test "api key mode: prints informational message" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
}

@test "api key mode: --refresh is a no-op when ANTHROPIC_API_KEY is set" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
}

@test "api key mode: does not require OAuth vars when ANTHROPIC_API_KEY is set" {
    export ANTHROPIC_API_KEY="sk-ant-test-key"
    unset CLAUDE_ACCESS_TOKEN
    unset CLAUDE_REFRESH_TOKEN
    unset CLAUDE_TOKEN_EXPIRES_AT
    unset CLAUDE_SUBSCRIPTION_TYPE
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
}

# ── initial setup mode ────────────────────────────────────────────────────────

@test "initial setup: writes credentials file" {
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_HOME/.claude/.credentials.json" ]
    ACCESS="$(jq -r '.claudeAiOauth.accessToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$ACCESS" == "test-access-token" ]]
}

@test "initial setup: prints success message" {
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"initialized"* ]]
}

@test "initial setup: error when CLAUDE_ACCESS_TOKEN missing" {
    unset CLAUDE_ACCESS_TOKEN
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_ACCESS_TOKEN"* ]]
}

@test "initial setup: error when CLAUDE_REFRESH_TOKEN missing" {
    unset CLAUDE_REFRESH_TOKEN
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_REFRESH_TOKEN"* ]]
}

@test "initial setup: error when CLAUDE_TOKEN_EXPIRES_AT missing" {
    unset CLAUDE_TOKEN_EXPIRES_AT
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_TOKEN_EXPIRES_AT"* ]]
}

@test "initial setup: error when CLAUDE_SUBSCRIPTION_TYPE missing" {
    unset CLAUDE_SUBSCRIPTION_TYPE
    run bash "$INIT_CLAUDE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE_SUBSCRIPTION_TYPE"* ]]
}
