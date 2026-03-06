#!/usr/bin/env bats
# Unit tests for workers/copilot/agent

AGENT="$BATS_TEST_DIRNAME/agent"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Temp copilot config dir
    FAKE_COPILOT_DIR="$(mktemp -d)"
    mkdir -p "$FAKE_COPILOT_DIR/.copilot"
    # Create a template config file with placeholders
    cat > "$FAKE_COPILOT_DIR/.copilot/config.json" <<'EOF'
{
  "copilot_tokens": {
    "https://github.com:${GH_USERNAME}": "${GH_TOKEN}"
  },
  "last_logged_in_user": {
    "login": "${GH_USERNAME}"
  }
}
EOF

    # Bind /root/.copilot to our fake dir by overriding in the script via env
    # We test the init logic by pointing the script at FAKE_COPILOT_DIR
    # Since init-copilot uses /root/.copilot/config.json, we need to override that path.
    # We mount it via a sed wrapper stub that redirects the path.
    stub_script sed "
# Redirect /root/.copilot/config.json to our fake location
args=()
for arg in \"\$@\"; do
    args+=(\"\${arg//\/root\/.copilot\/config.json/$FAKE_COPILOT_DIR\/.copilot\/config.json}\")
done
exec /usr/bin/sed \"\${args[@]}\"
"

    # Default env vars
    export GH_TOKEN="ghp-test-token"
    export GH_USERNAME="testuser"

    # Default stub for copilot CLI
    stub copilot ""
}

teardown() {
    rm -rf "$STUB_DIR" "$FAKE_COPILOT_DIR"
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

# ── agent init ────────────────────────────────────────────────────────────────

@test "init: exits 0 when GH_TOKEN and GH_USERNAME are set" {
    run "$AGENT" init
    [ "$status" -eq 0 ]
}

@test "init: prints success message" {
    run "$AGENT" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"initialized"* ]]
}

@test "init: error when GH_TOKEN missing" {
    unset GH_TOKEN
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"GH_TOKEN"* ]]
}

@test "init: error when GH_USERNAME missing" {
    unset GH_USERNAME
    run "$AGENT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"GH_USERNAME"* ]]
}

# ── agent run ─────────────────────────────────────────────────────────────────

@test "run: invokes copilot with --allow-all --no-ask-user and -p flags" {
    local copilot_log
    copilot_log="$(mktemp)"
    stub_script copilot "echo \"\$*\" >> '$copilot_log'"

    run "$AGENT" run "hello world"

    [[ "$(cat "$copilot_log")" == *"--allow-all"* ]]
    [[ "$(cat "$copilot_log")" == *"--no-ask-user"* ]]
    [[ "$(cat "$copilot_log")" == *"-p"* ]]
    [[ "$(cat "$copilot_log")" == *"hello world"* ]]

    rm -f "$copilot_log"
}

@test "run: passes full prompt as a single argument to copilot" {
    local copilot_log
    copilot_log="$(mktemp)"
    stub_script copilot "printf '%s\n' \"\$@\" >> '$copilot_log'"

    run "$AGENT" run "multi word prompt with spaces"

    grep -q "^multi word prompt with spaces$" "$copilot_log"

    rm -f "$copilot_log"
}

@test "run: exit code mirrors copilot exit code on success" {
    stub_exit copilot 0 ""

    run "$AGENT" run "prompt"

    [ "$status" -eq 0 ]
}

@test "run: exit code mirrors copilot exit code on failure" {
    stub_exit copilot 5 ""

    run "$AGENT" run "prompt"

    [ "$status" -eq 5 ]
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
