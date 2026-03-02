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

# ── --refresh: no-op when token is still valid ────────────────────────────────

@test "--refresh: no-op when token has not expired" {
    # expiresAt far in future — should NOT call curl
    write_creds "9999999999000"
    stub_exit curl 0 '{"access_token":"should-not-be-called"}'

    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"still valid"* ]]

    # credentials file should be unchanged
    AT="$(jq -r '.claudeAiOauth.accessToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$AT" == "test-access-token" ]]
}

# ── --refresh: refreshes when token is expired ────────────────────────────────

@test "--refresh: calls refresh endpoint when token is expired" {
    # expiresAt in the past
    write_creds "1000000000000"

    stub_script curl '
echo "$@" >> /tmp/curl-args-'"$$"'.txt
printf '"'"'{"access_token":"new-token","expires_in":28800}'"'"'
'
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"refreshed"* ]]

    AT="$(jq -r '.claudeAiOauth.accessToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$AT" == "new-token" ]]
    rm -f "/tmp/curl-args-$$.txt"
}

@test "--refresh: updates expiresAt after successful refresh" {
    write_creds "1000000000000"

    stub_script curl 'printf '"'"'{"access_token":"new-token","expires_in":28800}'"'"''
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]

    NEW_EA="$(jq -r '.claudeAiOauth.expiresAt' "$FAKE_HOME/.claude/.credentials.json")"
    # New expiresAt must be greater than the old one (1000000000000)
    [[ "$NEW_EA" -gt 1000000000000 ]]
}

@test "--refresh: updates refreshToken when server returns a new one" {
    write_creds "1000000000000" "old-refresh-token"

    stub_script curl 'printf '"'"'{"access_token":"new-token","refresh_token":"new-refresh-token","expires_in":28800}'"'"''
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]

    RT="$(jq -r '.claudeAiOauth.refreshToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$RT" == "new-refresh-token" ]]
}

@test "--refresh: keeps old refreshToken when server does not return one" {
    write_creds "1000000000000" "keep-this-refresh-token"

    stub_script curl 'printf '"'"'{"access_token":"new-token","expires_in":28800}'"'"''
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]

    RT="$(jq -r '.claudeAiOauth.refreshToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$RT" == "keep-this-refresh-token" ]]
}

# ── --refresh: graceful failure handling ──────────────────────────────────────

@test "--refresh: exits 0 and warns when curl fails" {
    write_creds "1000000000000"
    stub_exit curl 1 "connection refused"

    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
}

@test "--refresh: exits 0 and warns when server returns error JSON" {
    write_creds "1000000000000"
    stub_script curl 'printf '"'"'{"error":"invalid_grant","error_description":"Refresh token has expired"}'"'"''

    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
    [[ "$output" == *"Refresh token has expired"* ]]
}

@test "--refresh: exits 0 and warns when response has no access_token" {
    write_creds "1000000000000"
    stub_script curl 'printf '"'"'{"token_type":"bearer"}'"'"''

    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
}

@test "--refresh: does not update credentials file when refresh fails" {
    write_creds "1000000000000" "original-refresh" "original-access"
    stub_exit curl 1 "network error"

    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]

    AT="$(jq -r '.claudeAiOauth.accessToken' "$FAKE_HOME/.claude/.credentials.json")"
    [[ "$AT" == "original-access" ]]
}

# ── --refresh: missing credentials file ───────────────────────────────────────

@test "--refresh: error when credentials file does not exist" {
    # Don't call write_creds — no file created
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ── --refresh: passes correct parameters to oauth endpoint ────────────────────

@test "--refresh: sends refresh_token and client_id to endpoint" {
    write_creds "1000000000000" "my-refresh-token"
    local args_file
    args_file="$(mktemp)"

    stub_script curl "
echo \"\$@\" >> '$args_file'
printf '{\"access_token\":\"new-token\",\"expires_in\":28800}'
"
    run bash "$INIT_CLAUDE" --refresh
    [ "$status" -eq 0 ]

    ARGS="$(cat "$args_file")"
    [[ "$ARGS" == *"refresh_token"* ]]
    [[ "$ARGS" == *"my-refresh-token"* ]]
    [[ "$ARGS" == *"9d1c250a-e61b-44d9-88ed-5944d1962f5e"* ]]
    [[ "$ARGS" == *"console.anthropic.com"* ]]
    rm -f "$args_file"
}
