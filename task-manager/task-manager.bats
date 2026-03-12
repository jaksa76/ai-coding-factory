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

@test "claim: JQL includes ORDER BY rank ASC" {
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
    run "$TASK_MANAGER" claim --project "PROJ" --account-id "acc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *'ORDER BY rank ASC'* ]]
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

# ── github backend ────────────────────────────────────────────────────────────

@test "github: dispatcher selects github backend (no unknown-backend error)" {
    stub_script gh 'case "$*" in "auth status") exit 0 ;; *) ;; esac'
    run env TASK_MANAGER=github "$TASK_MANAGER" auth
    [ "$status" -eq 0 ]
}

@test "github: claim: error: missing --project" {
    stub_script gh ""
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --account-id "user1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "github: claim: error: missing --account-id" {
    stub_script gh ""
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --project "owner/repo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--account-id"* ]]
}

@test "github: claim: error: unknown option" {
    stub_script gh ""
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "github: claim: happy path: claims first eligible issue" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "
echo \"\$*\" >> '$gh_log'
case \"\$*\" in
  'auth status') exit 0 ;;
  'issue list'*'--json'*)
      echo '[{\"number\":42,\"title\":\"Fix bug\",\"body\":\"desc\",\"labels\":[],\"assignees\":[]}]' ;;
  'issue edit 42'*'--add-assignee user1'*) ;;
  'issue edit 42'*'--add-label in-progress'*) ;;
  'issue view 42'*'--json assignees'*)
      echo '{\"assignees\":[{\"login\":\"user1\"}]}' ;;
  'issue view 42'*'--json body'*)
      echo '{\"body\":\"desc\"}' ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed #42"* ]]
    issue_json="$(printf '%s\n' "$output" | awk '/^\{/{f=1} f')"
    [[ "$(printf '%s' "$issue_json" | jq -r '.key')"     == "42" ]]
    [[ "$(printf '%s' "$issue_json" | jq -r '.summary')" == "Fix bug" ]]
    rm -f "$gh_log"
}

@test "github: claim: race condition: retries when assignee does not match" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script gh "
case \"\$*\" in
  'auth status') exit 0 ;;
  'issue list'*'--json'*)
      echo '[{\"number\":7,\"title\":\"Task\",\"body\":\"\",\"labels\":[],\"assignees\":[]}]' ;;
  'issue edit'*'--add-assignee'*) ;;
  'issue edit'*'--add-label'*) ;;
  'issue view 7'*'--json assignees'*)
      count=\$(cat '$counter_file')
      echo \$((count + 1)) > '$counter_file'
      if [ \"\$count\" -eq 0 ]; then
          echo '{\"assignees\":[{\"login\":\"other\"}]}'
      else
          echo '{\"assignees\":[{\"login\":\"user1\"}]}'
      fi
      ;;
  'issue view 7'*'--json body'*) echo '{\"body\":\"\"}' ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"race detected"* ]]
    [[ "$output" == *"Successfully claimed #7"* ]]
    rm -f "$counter_file"
}

@test "github: claim: no issues exits non-zero on list empty (waits and retries once)" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script gh "
case \"\$*\" in
  'auth status') exit 0 ;;
  'issue list'*'--json'*)
      count=\$(cat '$counter_file')
      echo \$((count + 1)) > '$counter_file'
      if [ \"\$count\" -eq 0 ]; then
          echo '[]'
      else
          exit 99
      fi
      ;;
  *) ;;
esac
"
    # Stub sleep to avoid actual waiting, but make second gh call exit non-zero to stop loop
    run env TASK_MANAGER=github "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No eligible issues found"* ]]
    rm -f "$counter_file"
}

@test "github: claim: --for-planning: adds in-planning label, removes in-progress" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "
echo \"\$*\" >> '$gh_log'
case \"\$*\" in
  'auth status') exit 0 ;;
  'issue list'*'needs-plan'*'--json'*)
      echo '[{\"number\":5,\"title\":\"Plan me\",\"body\":\"\",\"labels\":[{\"name\":\"needs-plan\"}],\"assignees\":[]}]' ;;
  'issue edit 5'*'--add-assignee user1'*) ;;
  'issue edit 5'*'--add-label in-progress'*) ;;
  'issue view 5'*'--json assignees'*)
      echo '{\"assignees\":[{\"login\":\"user1\"}]}' ;;
  'issue edit 5'*'--add-label in-planning'*) ;;
  'issue edit 5'*'--remove-label in-progress'*) ;;
  'issue view 5'*'--json body'*) echo '{\"body\":\"\"}' ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github PLAN_BY_DEFAULT="" "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1" --for-planning
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed #5"* ]]
    [[ "$(cat "$gh_log")" == *"in-planning"* ]]
    rm -f "$gh_log"
}

@test "github: claim: PLAN_BY_DEFAULT=true selects issues without skip-plan" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "
echo \"\$*\" >> '$gh_log'
case \"\$*\" in
  'auth status') exit 0 ;;
  'issue list'*'--json'*)
      echo '[{\"number\":3,\"title\":\"Task\",\"body\":\"\",\"labels\":[],\"assignees\":[]}]' ;;
  'issue edit'*) ;;
  'issue view 3'*'--json assignees'*)
      echo '{\"assignees\":[{\"login\":\"user1\"}]}' ;;
  'issue view 3'*'--json body'*) echo '{\"body\":\"\"}' ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github PLAN_BY_DEFAULT=true "$TASK_MANAGER" claim --project "owner/repo" --account-id "user1"
    [ "$status" -eq 0 ]
    # skip-plan filter appears in the jq expression passed to gh
    [[ "$(cat "$gh_log")" == *"skip-plan"* ]]
    rm -f "$gh_log"
}

@test "github: view: returns normalized JSON" {
    stub_script gh '
case "$*" in
  "issue view 42"*)
      echo '"'"'{"number":42,"title":"Fix bug","body":"Bug details","labels":[{"name":"in-progress"}],"assignees":[{"login":"user1"}]}'"'"' ;;
  *) ;;
esac
'
    run env TASK_MANAGER=github GITHUB_REPO="owner/repo" "$TASK_MANAGER" view "42"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.key')"         == "42" ]]
    [[ "$(printf '%s' "$output" | jq -r '.summary')"     == "Fix bug" ]]
    [[ "$(printf '%s' "$output" | jq -r '.description')" == "Bug details" ]]
    [[ "$(printf '%s' "$output" | jq -r '.labels[0]')"   == "in-progress" ]]
    [[ "$(printf '%s' "$output" | jq -r '.assignee.accountId')" == "user1" ]]
}

@test "github: view: error when GITHUB_REPO is not set" {
    stub_script gh ""
    run env TASK_MANAGER=github "$TASK_MANAGER" view "42"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GITHUB_REPO"* ]]
}

@test "github: transition: Done closes the issue" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "echo \"\$*\" >> '$gh_log'"
    run env TASK_MANAGER=github GITHUB_REPO="owner/repo" "$TASK_MANAGER" transition "42" --status "Done"
    [ "$status" -eq 0 ]
    [[ "$(cat "$gh_log")" == *"issue close 42"* ]]
    rm -f "$gh_log"
}

@test "github: transition: In Review adds in-review label, removes in-progress" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "echo \"\$*\" >> '$gh_log'"
    run env TASK_MANAGER=github GITHUB_REPO="owner/repo" "$TASK_MANAGER" transition "42" --status "In Review"
    [ "$status" -eq 0 ]
    [[ "$(cat "$gh_log")" == *"--add-label in-review"* ]]
    [[ "$(cat "$gh_log")" == *"--remove-label in-progress"* ]]
    rm -f "$gh_log"
}

@test "github: comment: posts body via gh issue comment" {
    local gh_log
    gh_log="$(mktemp)"
    stub_script gh "echo \"\$*\" >> '$gh_log'"
    run env TASK_MANAGER=github GITHUB_REPO="owner/repo" "$TASK_MANAGER" comment "42" --comment "hello world"
    [ "$status" -eq 0 ]
    [[ "$(cat "$gh_log")" == *"issue comment 42"* ]]
    [[ "$(cat "$gh_log")" == *"hello world"* ]]
    rm -f "$gh_log"
}

# ── todo backend ──────────────────────────────────────────────────────────────

_todo_tmpfile() {
    # Create a temp TODO.md with given content and echo path
    local tmpfile
    tmpfile="$(mktemp --suffix=.md)"
    printf '%s\n' "$@" > "$tmpfile"
    echo "$tmpfile"
}

@test "todo: dispatcher selects todo backend (auth exits 0)" {
    run env TASK_MANAGER=todo "$TASK_MANAGER" auth
    [ "$status" -eq 0 ]
}

@test "todo: list: returns open items as JSON array" {
    local f
    f=$(_todo_tmpfile "- [ ] Task one" "- [>] In progress" "- [x] Done item")
    run env TASK_MANAGER=todo TODO_FILE="$f" PLAN_BY_DEFAULT="" "$TASK_MANAGER" list --project "$f"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.[0].key')"     == "TODO-1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.[0].summary')" == "Task one" ]]
    [[ "$(printf '%s' "$output" | jq 'length')"          == "1" ]]
    rm -f "$f"
}

@test "todo: list: excludes in-progress and done items" {
    local f
    f=$(_todo_tmpfile "- [>] In progress" "- [x] Done" "- [ ] Open")
    run env TASK_MANAGER=todo TODO_FILE="$f" PLAN_BY_DEFAULT="" "$TASK_MANAGER" list --project "$f"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq 'length')" == "1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.[0].summary')" == "Open" ]]
    rm -f "$f"
}

@test "todo: list: --for-planning returns only needs-plan items when PLAN_BY_DEFAULT unset" {
    local f
    f=$(_todo_tmpfile "- [ ] Regular task" "- [ ] Plan this [needs-plan]")
    unset PLAN_BY_DEFAULT
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" list --project "$f" --for-planning
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq 'length')" == "1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.[0].summary')" == *"needs-plan"* ]]
    rm -f "$f"
}

@test "todo: list: --for-planning returns all open items when PLAN_BY_DEFAULT=true" {
    local f
    f=$(_todo_tmpfile "- [ ] Regular task" "- [ ] Another task" "- [ ] skip [skip-plan]")
    run env TASK_MANAGER=todo TODO_FILE="$f" PLAN_BY_DEFAULT=true "$TASK_MANAGER" list --project "$f" --for-planning
    [ "$status" -eq 0 ]
    # skip-plan item is excluded; the other 2 are included
    [[ "$(printf '%s' "$output" | jq 'length')" == "2" ]]
    rm -f "$f"
}

@test "todo: claim: marks first open item as [>] (in-progress)" {
    local f
    f=$(_todo_tmpfile "- [ ] Task one" "- [ ] Task two")
    run env TASK_MANAGER=todo TODO_FILE="$f" PLAN_BY_DEFAULT="" "$TASK_MANAGER" claim --project "$f" --account-id "agent1"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [>] Task one" ]]
    rm -f "$f"
}

@test "todo: claim: --for-planning marks first eligible item as [~] (in-planning)" {
    local f
    f=$(_todo_tmpfile "- [ ] Plan this [needs-plan]" "- [ ] Other task")
    unset PLAN_BY_DEFAULT
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" claim --project "$f" --account-id "agent1" --for-planning
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [~] Plan this [needs-plan]" ]]
    rm -f "$f"
}

@test "todo: claim: returns correct JSON with key, summary, description" {
    local f
    f=$(_todo_tmpfile "- [ ] Fix the bug")
    run env TASK_MANAGER=todo TODO_FILE="$f" PLAN_BY_DEFAULT="" "$TASK_MANAGER" claim --project "$f" --account-id "agent1"
    [ "$status" -eq 0 ]
    local json
    json=$(printf '%s\n' "$output" | grep '^{')
    [[ "$(printf '%s' "$json" | jq -r '.key')"         == "TODO-1" ]]
    [[ "$(printf '%s' "$json" | jq -r '.summary')"     == "Fix the bug" ]]
    [[ "$(printf '%s' "$json" | jq -r '.description')" == "" ]]
    rm -f "$f"
}

@test "todo: view: returns normalized JSON for given key" {
    local f
    f=$(_todo_tmpfile "- [>] Fix the bug")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" view "TODO-1"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.key')"     == "TODO-1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.summary')" == "Fix the bug" ]]
    rm -f "$f"
}

@test "todo: transition: In Progress marks item as [>]" {
    local f
    f=$(_todo_tmpfile "- [ ] Task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" transition "TODO-1" --status "In Progress"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [>] Task" ]]
    rm -f "$f"
}

@test "todo: transition: Planning marks item as [~]" {
    local f
    f=$(_todo_tmpfile "- [ ] Task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" transition "TODO-1" --status "Planning"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [~] Task" ]]
    rm -f "$f"
}

@test "todo: transition: Awaiting Plan Review marks item as [?]" {
    local f
    f=$(_todo_tmpfile "- [~] Task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" transition "TODO-1" --status "Awaiting Plan Review"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [?] Task" ]]
    rm -f "$f"
}

@test "todo: transition: Plan Approved marks item as [p]" {
    local f
    f=$(_todo_tmpfile "- [?] Task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" transition "TODO-1" --status "Plan Approved"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [p] Task" ]]
    rm -f "$f"
}

@test "todo: transition: Done marks item as [x]" {
    local f
    f=$(_todo_tmpfile "- [>] Task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" transition "TODO-1" --status "Done"
    [ "$status" -eq 0 ]
    [[ "$(head -1 "$f")" == "- [x] Task" ]]
    rm -f "$f"
}

@test "todo: comment: appends note line below the task" {
    local f
    f=$(_todo_tmpfile "- [>] Fix the bug" "- [ ] Other task")
    run env TASK_MANAGER=todo TODO_FILE="$f" "$TASK_MANAGER" comment "TODO-1" --comment "Done in PR #42"
    [ "$status" -eq 0 ]
    [[ "$(sed -n '2p' "$f")" == "  - Note: Done in PR #42" ]]
    rm -f "$f"
}

