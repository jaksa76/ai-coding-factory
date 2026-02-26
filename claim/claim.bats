#!/usr/bin/env bats
# Tests for claim/claim

CLAIM="$BATS_TEST_DIRNAME/claim"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    # Per-test stub directory on PATH
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    # Minimal required env vars (can be overridden per test)
    export JIRA_SITE="test.atlassian.net"
    export JIRA_EMAIL="test@example.com"
    export JIRA_TOKEN="token123"

    # Silence sleep by default
    stub sleep ""
}

teardown() {
    rm -rf "$STUB_DIR"
}

# stub <cmd> [stdout_content]
# Creates an executable in STUB_DIR that exits 0 and prints optional content.
stub() {
    local cmd="$1"
    local out="${2:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$out" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# stub_exit <cmd> <exit_code> [stdout_content]
stub_exit() {
    local cmd="$1" code="$2" out="${3:-}"
    printf '#!/usr/bin/env bash\nprintf "%%s" %q\nexit %d\n' "$out" "$code" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# stub_script <cmd> <script_body>
stub_script() {
    local cmd="$1" body="$2"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_DIR/$cmd"
    chmod +x "$STUB_DIR/$cmd"
}

# ── argument / env validation ─────────────────────────────────────────────────

@test "error: missing --project" {
    run "$CLAIM" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "error: missing --account-id" {
    run "$CLAIM" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--account-id"* ]]
}

@test "error: JIRA_SITE not set" {
    unset JIRA_SITE
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

@test "error: JIRA_EMAIL not set" {
    unset JIRA_EMAIL
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_EMAIL"* ]]
}

@test "error: JIRA_TOKEN not set" {
    unset JIRA_TOKEN
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_TOKEN"* ]]
}

@test "error: unknown option" {
    run "$CLAIM" --project "PROJ" --account-id "acc1" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "--help prints usage" {
    run "$CLAIM" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run "$CLAIM" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── happy path ────────────────────────────────────────────────────────────────

@test "successful claim: skips login when already authenticated" {
    # acli auth status reports authenticated; search returns one issue; assign
    # succeeds; view confirms correct assignee; transition succeeds; view prints JSON
    stub_script acli '
case "$*" in
  "jira auth status")        echo "Authenticated" ;;
  "jira workitem search"*)   echo '"'"'[{"key":"PROJ-1"}]'"'"' ;;
  "jira workitem assign"*)   ;;
  "jira workitem view PROJ-1 --json")
      echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"desc","status":{"name":"In Progress"}}}'"'"' ;;
  "jira workitem transition"*) ;;
esac
'
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-1"* ]]
}

@test "successful claim: performs login when not authenticated" {
    local login_called=0
    stub_script acli '
case "$*" in
  "jira auth status")        exit 1 ;;   # not authenticated
  "jira auth login"*)        echo "logged in" ;;
  "jira workitem search"*)   echo '"'"'[{"key":"PROJ-2"}]'"'"' ;;
  "jira workitem assign"*)   ;;
  "jira workitem view PROJ-2 --json")
      echo '"'"'{"key":"PROJ-2","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":null,"status":{"name":"To Do"}}}'"'"' ;;
  "jira workitem transition"*) ;;
esac
'
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-2"* ]]
}

@test "no issues found: retries after waiting, then claims on second attempt" {
    # Counter file to simulate: first call returns empty, second returns an issue
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script acli "
case \"\$*\" in
  'jira auth status')       echo 'Authenticated' ;;
  'jira workitem search'*)
      count=\$(cat '$counter_file')
      echo \$((count + 1)) > '$counter_file'
      if [ \"\$count\" -eq 0 ]; then
          echo '[]'
      else
          echo '[{\"key\":\"PROJ-3\"}]'
      fi
      ;;
  'jira workitem assign'*)  ;;
  'jira workitem view PROJ-3 --json')
      echo '{\"key\":\"PROJ-3\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*) ;;
esac
"
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No unassigned open issues found"* ]]
    [[ "$output" == *"Successfully claimed PROJ-3"* ]]

    rm -f "$counter_file"
}

@test "race condition: retries when assignee does not match" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script acli "
case \"\$*\" in
  'jira auth status')       echo 'Authenticated' ;;
  'jira workitem search'*)  echo '[{\"key\":\"PROJ-4\"}]' ;;
  'jira workitem assign'*)  ;;
  'jira workitem view PROJ-4 --json')
      count=\$(cat '$counter_file')
      echo \$((count + 1)) > '$counter_file'
      if [ \"\$count\" -eq 0 ]; then
          # First verify: someone else has it (race)
          echo '{\"key\":\"PROJ-4\",\"fields\":{\"assignee\":{\"accountId\":\"other\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}'
      else
          # Second verify: we own it
          echo '{\"key\":\"PROJ-4\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}'
      fi
      ;;
  'jira workitem transition'*) ;;
esac
"
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"race detected"* ]]
    [[ "$output" == *"Successfully claimed PROJ-4"* ]]

    rm -f "$counter_file"
}

@test "successful claim: transitions issue to In Progress" {
    local transition_args_file
    transition_args_file="$(mktemp)"

    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-6\"}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-6 --json')
      echo '{\"key\":\"PROJ-6\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*)
      echo \"\$*\" > '$transition_args_file'
      ;;
esac
"
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-6"* ]]

    local transition_args
    transition_args="$(cat "$transition_args_file")"
    [[ "$transition_args" == *"--key PROJ-6"* ]]
    [[ "$transition_args" == *"--status"* ]]
    [[ "$transition_args" == *"In Progress"* ]]

    rm -f "$transition_args_file"
}

@test "transition failure is non-fatal: warning printed but exits 0" {
    stub_script acli '
case "$*" in
  "jira auth status")        echo "Authenticated" ;;
  "jira workitem search"*)   echo '"'"'[{"key":"PROJ-5"}]'"'"' ;;
  "jira workitem assign"*)   ;;
  "jira workitem view PROJ-5 --json")
      echo '"'"'{"key":"PROJ-5","fields":{"assignee":{"accountId":"acc1"},"summary":"Task","description":null,"status":{"name":"To Do"}}}'"'"' ;;
  "jira workitem transition"*) exit 1 ;;   # transition fails
esac
'
    run "$CLAIM" --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
    [[ "$output" == *"Successfully claimed PROJ-5"* ]]
}
