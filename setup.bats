#!/usr/bin/env bats
# Tests for setup.sh credential import logic

SETUP="$BATS_TEST_DIRNAME/setup.sh"

# ── helpers ───────────────────────────────────────────────────────────────────

make_credentials_file() {
    local dir="$1"
    mkdir -p "$dir/.claude"
    cat > "$dir/.claude/.credentials.json" <<'EOF'
{"claudeAiOauth":{"accessToken":"test-access-token","refreshToken":"test-refresh-token","expiresAt":9999999999999,"subscriptionType":"pro"}}
EOF
}

# Run setup.sh up to collect_agent_credentials only, sourcing the helpers
run_collect_credentials() {
    local home_dir="$1"
    local inputs="$2"   # newline-separated stdin

    # Source functions from setup.sh in a subshell
    bash -c "
        HOME='$home_dir'
        source '$SETUP'
        CHOSEN_AGENT=claude
        # Provide input via stdin
        collect_agent_credentials
        echo \"ACCESS=\$CLAUDE_ACCESS_TOKEN\"
        echo \"REFRESH=\$CLAUDE_REFRESH_TOKEN\"
        echo \"EXPIRES=\$CLAUDE_TOKEN_EXPIRES_AT\"
        echo \"SUBTYPE=\$CLAUDE_SUBSCRIPTION_TYPE\"
        echo \"APIKEY=\$ANTHROPIC_API_KEY\"
    " <<< "$inputs" 2>/dev/null
}

# ── tests ─────────────────────────────────────────────────────────────────────

@test "setup_bin creates symlinks for all scripts" {
    local tmp_bin
    tmp_bin="$(mktemp -d)"

    bash -c "
        source '$SETUP'
        BIN_DIR='$tmp_bin'
        REPO_DIR='$BATS_TEST_DIRNAME'
        CHOSEN_AGENT=claude
        setup_bin
    " < /dev/null 2>/dev/null

    local expected=(task-manager loop implement plan factory worker-builder agent)
    for name in "${expected[@]}"; do
        [[ -L "$tmp_bin/$name" ]] || { echo "missing symlink: $name"; exit 1; }
    done

    rm -rf "$tmp_bin"
}

@test "setup_factory_runtime points runtime symlink to selected backend" {
    local tmp_repo
    tmp_repo="$(mktemp -d)"
    local tmp_bin
    tmp_bin="$(mktemp -d)"
    mkdir -p "$tmp_repo/factory"
    touch "$tmp_repo/factory/runtime-docker"
    touch "$tmp_repo/factory/runtime-aws"

    bash -c "
        source '$SETUP'
        REPO_DIR='$tmp_repo'
        BIN_DIR='$tmp_bin'
        CHOSEN_RUNTIME=aws
        setup_factory_runtime
    " < /dev/null 2>/dev/null

    [[ -L "$tmp_bin/runtime" ]] || { echo "missing bin/runtime symlink"; rm -rf "$tmp_repo" "$tmp_bin"; exit 1; }
    [[ "$(readlink "$tmp_bin/runtime")" == "$tmp_repo/factory/runtime-aws" ]] \
        || { echo "bin/runtime should point to runtime-aws"; rm -rf "$tmp_repo" "$tmp_bin"; exit 1; }

    [[ -L "$tmp_repo/factory/runtime" ]] || { echo "missing runtime symlink"; rm -rf "$tmp_repo"; exit 1; }
    [[ "$(readlink "$tmp_repo/factory/runtime")" == "$tmp_repo/factory/runtime-aws" ]] \
        || { echo "factory/runtime should point to runtime-aws"; rm -rf "$tmp_repo" "$tmp_bin"; exit 1; }

    rm -rf "$tmp_repo" "$tmp_bin"
}

@test "imports credentials from file when it exists and user accepts" {
    local tmp_home
    tmp_home="$(mktemp -d)"
    make_credentials_file "$tmp_home"

    # Input: method=2, accept import (y)
    output="$(run_collect_credentials "$tmp_home" $'2\ny')"

    echo "$output" | grep -q "ACCESS=test-access-token"
    echo "$output" | grep -q "REFRESH=test-refresh-token"
    echo "$output" | grep -q "EXPIRES=9999999999999"
    echo "$output" | grep -q "SUBTYPE=pro"
    echo "$output" | grep -q "APIKEY=$"

    rm -rf "$tmp_home"
}

@test "falls back to manual entry when user declines import" {
    local tmp_home
    tmp_home="$(mktemp -d)"
    make_credentials_file "$tmp_home"

    # Input: method=2, decline import (n), then manual values
    output="$(run_collect_credentials "$tmp_home" $'2\nn\nmanual-access\nmanual-refresh\n12345\npro')"

    echo "$output" | grep -q "ACCESS=manual-access"
    echo "$output" | grep -q "REFRESH=manual-refresh"

    rm -rf "$tmp_home"
}

@test "falls back to manual entry when credentials file is missing" {
    local tmp_home
    tmp_home="$(mktemp -d)"
    # No credentials file

    # Input: method=2, then manual values
    output="$(run_collect_credentials "$tmp_home" $'2\nmanual-access\nmanual-refresh\n12345\npro')"

    echo "$output" | grep -q "ACCESS=manual-access"

    rm -rf "$tmp_home"
}

@test "API key method still works" {
    local tmp_home
    tmp_home="$(mktemp -d)"

    # Input: method=1 (API key), then the key
    output="$(run_collect_credentials "$tmp_home" $'1\nsk-test-api-key')"

    echo "$output" | grep -q "APIKEY=sk-test-api-key"
    echo "$output" | grep -q "ACCESS=$"

    rm -rf "$tmp_home"
}
