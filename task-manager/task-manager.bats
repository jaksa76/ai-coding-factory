#!/usr/bin/env bats
# Tests for task-manager/task-manager (dispatcher + jira backend)

TASK_MANAGER="$BATS_TEST_DIRNAME/task-manager"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

    export JIRA_SITE="test.atlassian.net"
    export JIRA_EMAIL="test@example.com"
    export JIRA_TOKEN="token123"

    stub sleep ""
}

teardown() {
    rm -rf "$STUB_DIR"
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

# ── dispatcher: unknown backend ───────────────────────────────────────────────

@test "dispatcher: unknown TASK_MANAGER value exits non-zero with error" {
    TASK_MANAGER=notabackend run "$TASK_MANAGER" auth
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown task manager backend"* ]]
}

# ── dispatcher: --help / unknown subcommand ───────────────────────────────────

@test "dispatcher: --help prints usage" {
    stub acli ""
    run "$TASK_MANAGER" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatcher: -h prints usage" {
    stub acli ""
    run "$TASK_MANAGER" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatcher: unknown subcommand exits non-zero" {
    stub acli ""
    run "$TASK_MANAGER" notasubcommand
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown subcommand"* ]]
}

@test "dispatcher: no subcommand prints usage" {
    stub acli ""
    run "$TASK_MANAGER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── dispatcher: each subcommand routes to correct backend function ─────────────
# These tests stub acli to verify the dispatcher calls the right tm_* function.

@test "dispatcher: 'auth' routes to tm_auth (calls acli jira auth)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'"
    run "$TASK_MANAGER" auth
    [[ "$(cat "$acli_log")" == *"auth"* ]]
    rm -f "$acli_log"
}

@test "dispatcher: 'view' routes to tm_view (calls acli workitem view)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'; echo '{\"key\":\"PROJ-1\",\"fields\":{\"summary\":\"s\",\"description\":null,\"labels\":null,\"assignee\":null}}'"
    run "$TASK_MANAGER" view "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"workitem view"* ]]
    [[ "$(cat "$acli_log")" == *"PROJ-1"* ]]
    rm -f "$acli_log"
}

@test "dispatcher: 'assign' routes to tm_assign (calls acli workitem assign)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'"
    run "$TASK_MANAGER" assign "PROJ-1" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"workitem assign"* ]]
    rm -f "$acli_log"
}

@test "dispatcher: 'comment' routes to tm_comment (calls acli comment add)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'"
    run "$TASK_MANAGER" comment "PROJ-1" --comment "hello"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"comment add"* ]]
    [[ "$(cat "$acli_log")" == *"hello"* ]]
    rm -f "$acli_log"
}

@test "dispatcher: 'transition' routes to tm_transition (calls acli workitem transition)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'"
    run "$TASK_MANAGER" transition "PROJ-1" --status "Done"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"workitem transition"* ]]
    [[ "$(cat "$acli_log")" == *"Done"* ]]
    rm -f "$acli_log"
}

@test "dispatcher: 'transitions' routes to tm_transitions (calls acli workitem transitions)" {
    local acli_log
    acli_log="$(mktemp)"
    stub_script acli "echo \"\$*\" >> '$acli_log'; echo '[{\"name\":\"Done\"}]'"
    run "$TASK_MANAGER" transitions "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"workitem transitions"* ]]
    rm -f "$acli_log"
}

# ── transitions: output format ────────────────────────────────────────────────

@test "transitions: returns JSON array of status name strings" {
    stub_script acli "echo '[{\"name\":\"In Progress\"},{\"name\":\"Done\"},{\"name\":\"Planning\"}]'"
    run "$TASK_MANAGER" transitions "PROJ-1"
    [ "$status" -eq 0 ]
    result=$(printf '%s' "$output" | jq -r '.[0]')
    [[ "$result" == "In Progress" ]]
}

# ── view: output format ───────────────────────────────────────────────────────

@test "view: returns normalized JSON with key, summary, description, labels, assignee" {
    stub_script acli 'echo '"'"'{"key":"PROJ-1","fields":{"summary":"Fix bug","description":"Bug details","labels":["needs-plan"],"assignee":{"accountId":"acc1"},"status":{"name":"To Do"}}}'"'"''
    run "$TASK_MANAGER" view "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.key')" == "PROJ-1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.summary')" == "Fix bug" ]]
    [[ "$(printf '%s' "$output" | jq -r '.description')" == "Bug details" ]]
    [[ "$(printf '%s' "$output" | jq -r '.labels[0]')" == "needs-plan" ]]
    [[ "$(printf '%s' "$output" | jq -r '.assignee.accountId')" == "acc1" ]]
}

@test "view: labels defaults to empty array when absent" {
    stub_script acli 'echo '"'"'{"key":"PROJ-1","fields":{"summary":"s","description":null,"labels":null,"assignee":null}}'"'"''
    run "$TASK_MANAGER" view "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.labels | length')" == "0" ]]
}

# ── claim: argument / env validation ─────────────────────────────────────────

@test "claim: error: missing --project" {
    stub acli ""
    run "$TASK_MANAGER" claim --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "claim: error: missing --account-id" {
    stub acli ""
    run "$TASK_MANAGER" claim --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--account-id"* ]]
}

@test "claim: error: JIRA_SITE not set" {
    unset JIRA_SITE
    stub acli ""
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

@test "claim: error: JIRA_EMAIL not set" {
    unset JIRA_EMAIL
    stub acli ""
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_EMAIL"* ]]
}

@test "claim: error: JIRA_TOKEN not set" {
    unset JIRA_TOKEN
    stub acli ""
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_TOKEN"* ]]
}

@test "claim: error: unknown option" {
    stub acli ""
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

# ── claim: happy path ─────────────────────────────────────────────────────────

@test "claim: successful claim: skips login when already authenticated" {
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
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-1"* ]]
}

@test "claim: successful claim: performs login when not authenticated" {
    stub_script acli '
case "$*" in
  "jira auth status")        exit 1 ;;
  "jira auth login"*)        echo "logged in" ;;
  "jira workitem search"*)   echo '"'"'[{"key":"PROJ-2"}]'"'"' ;;
  "jira workitem assign"*)   ;;
  "jira workitem view PROJ-2 --json")
      echo '"'"'{"key":"PROJ-2","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":null,"status":{"name":"To Do"}}}'"'"' ;;
  "jira workitem transition"*) ;;
esac
'
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-2"* ]]
}

@test "claim: race condition: retries when assignee does not match" {
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
          echo '{\"key\":\"PROJ-4\",\"fields\":{\"assignee\":{\"accountId\":\"other\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}'
      else
          echo '{\"key\":\"PROJ-4\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}'
      fi
      ;;
  'jira workitem transition'*) ;;
esac
"
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"race detected"* ]]
    [[ "$output" == *"Successfully claimed PROJ-4"* ]]

    rm -f "$counter_file"
}

@test "claim: transitions issue to In Progress" {
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
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-6"* ]]
    [[ "$(cat "$transition_args_file")" == *"--key PROJ-6"* ]]
    [[ "$(cat "$transition_args_file")" == *"In Progress"* ]]

    rm -f "$transition_args_file"
}

@test "claim: --for-planning: transitions issue to Planning status" {
    local transition_args_file
    transition_args_file="$(mktemp)"

    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-8\",\"fields\":{\"labels\":[\"needs-plan\"]}}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-8 --json')
      echo '{\"key\":\"PROJ-8\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*)
      echo \"\$*\" > '$transition_args_file'
      ;;
esac
"
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1" --for-planning
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed PROJ-8"* ]]
    [[ "$(cat "$transition_args_file")" == *"--key PROJ-8"* ]]
    [[ "$(cat "$transition_args_file")" == *"Planning"* ]]

    rm -f "$transition_args_file"
}

# ── claim: planning filter / JQL ──────────────────────────────────────────────

@test "claim: JQL excludes needs-plan issues when PLAN_BY_DEFAULT is unset" {
    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-1\"}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-1 --json')
      echo '{\"key\":\"PROJ-1\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*) ;;
esac
"
    unset PLAN_BY_DEFAULT
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *'needs-plan'* ]]
}

@test "claim: JQL restricts to skip-plan issues when PLAN_BY_DEFAULT=true" {
    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-1\",\"fields\":{\"labels\":[\"skip-plan\"]}}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-1 --json')
      echo '{\"key\":\"PROJ-1\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*) ;;
esac
"
    export PLAN_BY_DEFAULT=true
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *'skip-plan'* ]]
}

@test "claim: --for-planning: JQL uses To Do status — PLAN_BY_DEFAULT unset" {
    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-1\"}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-1 --json')
      echo '{\"key\":\"PROJ-1\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*) ;;
esac
"
    unset PLAN_BY_DEFAULT
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1" --for-planning
    [ "$status" -eq 0 ]
    [[ "$output" == *'To Do'* ]]
    [[ "$output" == *'needs-plan'* ]]
    [[ "$output" != *'skip-plan'* ]]
}

@test "claim: --for-planning: JQL excludes skip-plan when PLAN_BY_DEFAULT=true" {
    stub_script acli "
case \"\$*\" in
  'jira auth status')        echo 'Authenticated' ;;
  'jira workitem search'*)   echo '[{\"key\":\"PROJ-1\"}]' ;;
  'jira workitem assign'*)   ;;
  'jira workitem view PROJ-1 --json')
      echo '{\"key\":\"PROJ-1\",\"fields\":{\"assignee\":{\"accountId\":\"acc1\"},\"summary\":\"Task\",\"description\":null,\"status\":{\"name\":\"To Do\"}}}' ;;
  'jira workitem transition'*) ;;
esac
"
    export PLAN_BY_DEFAULT=true
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1" --for-planning
    [ "$status" -eq 0 ]
    [[ "$output" == *'To Do'* ]]
    [[ "$output" == *'skip-plan'* ]]
    [[ "$output" == *'EMPTY'* ]]
    [[ "$output" != *'needs-plan'* ]]
}

@test "claim: transition failure is non-fatal: warning printed but exits 0" {
    stub_script acli '
case "$*" in
  "jira auth status")        echo "Authenticated" ;;
  "jira workitem search"*)   echo '"'"'[{"key":"PROJ-5"}]'"'"' ;;
  "jira workitem assign"*)   ;;
  "jira workitem view PROJ-5 --json")
      echo '"'"'{"key":"PROJ-5","fields":{"assignee":{"accountId":"acc1"},"summary":"Task","description":null,"status":{"name":"To Do"}}}'"'"' ;;
  "jira workitem transition"*) exit 1 ;;
esac
'
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"* ]]
    [[ "$output" == *"Successfully claimed PROJ-5"* ]]
}
