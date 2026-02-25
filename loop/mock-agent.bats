#!/usr/bin/env bats
# Tests for loop/mock-agent

AGENT="$BATS_TEST_DIRNAME/mock-agent"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    # Per-test stub directory on PATH
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Temporary git repo directory for the agent to work in
    WORK_DIR="$(mktemp -d)"

    # stub git — records calls, exits 0
    stub git ""
}

teardown() {
    rm -rf "$STUB_DIR" "$WORK_DIR"
}

# stub <cmd> [stdout_content]
stub() {
    local cmd="$1"
    local out="${2:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$out" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# stub_script <cmd> <script_body>
stub_script() {
    local cmd="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# ── argument validation ───────────────────────────────────────────────────────

@test "error: no arguments" {
    run "$AGENT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--help prints usage" {
    run "$AGENT" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run "$AGENT" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── happy path ────────────────────────────────────────────────────────────────

@test "appends prompt to work-log.md and commits" {
    # Track git calls
    stub_script git '
case "$*" in
  "add work-log.md") ;;
  "commit -m mock agent: process issue") ;;
  *) echo "unexpected git call: $*" >&2; exit 1 ;;
esac
'
    cd "$WORK_DIR"
    run "$AGENT" "Fix the login bug"
    [ "$status" -eq 0 ]
    [ -f work-log.md ]
    [[ "$(cat work-log.md)" == *"Fix the login bug"* ]]
}

@test "multi-word prompt is written in full" {
    stub git ""
    cd "$WORK_DIR"
    run "$AGENT" "Implement dark mode for the dashboard"
    [ "$status" -eq 0 ]
    [ -f work-log.md ]
    [[ "$(cat work-log.md)" == *"Implement dark mode for the dashboard"* ]]
}

@test "appends to existing work-log.md (does not overwrite)" {
    stub git ""
    cd "$WORK_DIR"
    echo "previous entry" > work-log.md

    run "$AGENT" "new entry"
    [ "$status" -eq 0 ]
    [[ "$(cat work-log.md)" == *"previous entry"* ]]
    [[ "$(cat work-log.md)" == *"new entry"* ]]
}

@test "git add is called with work-log.md" {
    local add_log
    add_log="$(mktemp)"
    stub_script git "
case \"\$*\" in
  'add work-log.md') echo 'add called' >> '$add_log' ;;
  'commit'*) ;;
  *) echo \"unexpected: \$*\" >&2; exit 1 ;;
esac
"
    cd "$WORK_DIR"
    run "$AGENT" "some prompt"
    [ "$status" -eq 0 ]
    [ -f "$add_log" ]
    [[ "$(cat "$add_log")" == *"add called"* ]]
    rm -f "$add_log"
}

@test "git commit is called with expected message" {
    local commit_log
    commit_log="$(mktemp)"
    stub_script git "
case \"\$*\" in
  'add work-log.md') ;;
  'commit -m mock agent: process issue') echo 'commit called' >> '$commit_log' ;;
  *) echo \"unexpected: \$*\" >&2; exit 1 ;;
esac
"
    cd "$WORK_DIR"
    run "$AGENT" "some prompt"
    [ "$status" -eq 0 ]
    [ -f "$commit_log" ]
    [[ "$(cat "$commit_log")" == *"commit called"* ]]
    rm -f "$commit_log"
}

@test "exits non-zero when git commit fails" {
    stub_script git '
case "$*" in
  "add work-log.md") ;;
  "commit"*) exit 1 ;;
esac
'
    cd "$WORK_DIR"
    run "$AGENT" "some prompt"
    [ "$status" -ne 0 ]
}
