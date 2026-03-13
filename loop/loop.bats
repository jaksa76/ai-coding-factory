#!/usr/bin/env bats
# Tests for loop/loop

LOOP="$BATS_TEST_DIRNAME/loop"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    # Per-test stub directory on PATH; real task-manager comes after
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$BATS_TEST_DIRNAME/../task-manager:$PATH"

    # Temporary directory for LOOP_WORK_DIR (controls where repos are cloned)
    WORK_TMPDIR="$(mktemp -d)"
    export LOOP_WORK_DIR="$WORK_TMPDIR"

    # Required env vars
    export JIRA_SITE="test.atlassian.net"
    export JIRA_EMAIL="test@example.com"
    export JIRA_TOKEN="token123"
    export JIRA_ASSIGNEE_ACCOUNT_ID="acc123"
    export GIT_REPO_URL="https://github.com/org/repo.git"
    export GIT_USERNAME="gituser"
    export GIT_TOKEN="gittoken"

    stub sleep ""

    # Default stubs for plan/implement (loop delegates to these)
    stub implement ""
    stub plan ""

    # task-manager claim: succeed once (return JSON), then exit 1 to break the loop.
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    local real_tm
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
}

teardown() {
    rm -rf "$STUB_DIR" "$WORK_TMPDIR"
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

# ── argument validation ───────────────────────────────────────────────────────

@test "error: missing --project" {
    run "$LOOP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "error: unknown option" {
    run "$LOOP" --project "PROJ" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "--help prints usage" {
    run "$LOOP" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run "$LOOP" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── environment variable validation ──────────────────────────────────────────

@test "error: JIRA_SITE not set" {
    unset JIRA_SITE
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

@test "error: JIRA_EMAIL not set" {
    unset JIRA_EMAIL
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_EMAIL"* ]]
}

@test "error: JIRA_TOKEN not set" {
    unset JIRA_TOKEN
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_TOKEN"* ]]
}

@test "error: JIRA_ASSIGNEE_ACCOUNT_ID not set" {
    unset JIRA_ASSIGNEE_ACCOUNT_ID
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_ASSIGNEE_ACCOUNT_ID"* ]]
}

@test "error: GIT_REPO_URL not set" {
    unset GIT_REPO_URL
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_REPO_URL"* ]]
}

@test "error: GIT_USERNAME not set" {
    unset GIT_USERNAME
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_USERNAME"* ]]
}

@test "error: GIT_TOKEN not set" {
    unset GIT_TOKEN
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_TOKEN"* ]]
}

# ── dispatch ──────────────────────────────────────────────────────────────────

@test "implementation mode: calls implement with the claimed issue key" {
    local impl_log
    impl_log="$(mktemp)"
    stub_script implement "echo \"\$*\" >> '$impl_log'"

    run "$LOOP" --project PROJ
    [[ "$(cat "$impl_log")" == *"PROJ-1"* ]]

    rm -f "$impl_log"
}

@test "planning mode: calls plan with the claimed issue key" {
    local plan_log
    plan_log="$(mktemp)"
    stub_script plan "echo \"\$*\" >> '$plan_log'"

    run "$LOOP" --project PROJ --for-planning
    [[ "$(cat "$plan_log")" == *"PROJ-1"* ]]

    rm -f "$plan_log"
}

@test "claim output with progress messages: issue key is correctly extracted" {
    local impl_log counter_file real_tm
    impl_log="$(mktemp)"
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script implement "echo \"\$*\" >> '$impl_log'"
    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'Searching for unassigned open issues in project PROJ...'
        echo 'Attempting to claim PROJ-2...'
        echo 'Successfully claimed PROJ-2.'
        printf '{\"key\":\"PROJ-2\",\"summary\":\"Add feature\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$impl_log")" == *"PROJ-2"* ]]

    rm -f "$impl_log" "$counter_file"
}

# ── no-issues handling ────────────────────────────────────────────────────────

@test "no issues: waits and polls again when claim exits 2" {
    local impl_log counter_file real_tm
    impl_log="$(mktemp)"
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script implement "echo \"\$*\" >> '$impl_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'No unassigned open issues found in project PROJ.'
        exit 2
    elif [ \"\$count\" -eq 1 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$impl_log")" == *"PROJ-1"* ]]

    rm -f "$impl_log" "$counter_file"
}

@test "no issues: default wait is 60 seconds" {
    local counter_file sleep_log real_tm
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'No unassigned open issues found in project PROJ.'
        exit 2
    elif [ \"\$count\" -eq 1 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"60"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "no issues: NO_ISSUES_WAIT overrides default wait" {
    local counter_file sleep_log real_tm
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'No unassigned open issues found in project PROJ.'
        exit 2
    elif [ \"\$count\" -eq 1 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    export NO_ISSUES_WAIT=120
    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"120"* ]]

    rm -f "$counter_file" "$sleep_log"
}

# ── inter-issue sleep ─────────────────────────────────────────────────────────

@test "inter-issue sleep: default wait is 1200 seconds in implementation mode" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"1200"* ]]

    rm -f "$sleep_log"
}

@test "inter-issue sleep: default wait is 600 seconds in planning mode" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    run "$LOOP" --project PROJ --for-planning
    [[ "$(cat "$sleep_log")" == *"600"* ]]

    rm -f "$sleep_log"
}

@test "inter-issue sleep: INTER_ISSUE_WAIT overrides default wait" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    export INTER_ISSUE_WAIT=5
    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"5"* ]]

    rm -f "$sleep_log"
}

# ── planning mode no-issues ───────────────────────────────────────────────────

@test "planning mode: no issues: waits and polls again when claim exits 2" {
    local plan_log counter_file real_tm
    plan_log="$(mktemp)"
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script plan "echo \"\$*\" >> '$plan_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'No planning issues found.'
        exit 2
    elif [ \"\$count\" -eq 1 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"No planning issues available in project PROJ"* ]]
    [[ "$output" == *"Waiting"* ]]
    [[ "$(cat "$plan_log")" == *"PROJ-1"* ]]

    rm -f "$plan_log" "$counter_file"
}

@test "planning mode: NO_ISSUES_WAIT overrides default wait" {
    local plan_log counter_file sleep_log real_tm
    plan_log="$(mktemp)"
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"
    stub_script plan "echo \"\$*\" >> '$plan_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        echo 'No planning issues found.'
        exit 2
    elif [ \"\$count\" -eq 1 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"

    export NO_ISSUES_WAIT=120
    run "$LOOP" --project PROJ --for-planning

    [[ "$(cat "$sleep_log")" == *"120"* ]]

    rm -f "$plan_log" "$counter_file" "$sleep_log"
}

# ── TASK_MANAGER=github: validation ──────────────────────────────────────────

@test "github backend: error: GH_TOKEN not set" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID GH_TOKEN
    run env TASK_MANAGER=github "$LOOP" --project "owner/repo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GH_TOKEN"* ]]
}

@test "github backend: error: GH_ASSIGNEE not set" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID
    run env TASK_MANAGER=github GH_TOKEN=tok "$LOOP" --project "owner/repo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GH_ASSIGNEE"* ]]
}

@test "github backend: Jira vars not required" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"1\",\"summary\":\"Do it\"}\n'
    else
        exit 1
    fi
    ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github GH_TOKEN=tok GH_ASSIGNEE=myuser \
        "$LOOP" --project "owner/repo"
    [[ "$output" != *"JIRA_SITE"* ]]
    [[ "$output" != *"JIRA_EMAIL"* ]]
    rm -f "$counter_file"
}

@test "github backend: GITHUB_REPO exported for task-manager subcommands" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID
    local tm_log
    tm_log="$(mktemp)"
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script task-manager "
echo \"GITHUB_REPO=\$GITHUB_REPO\" >> '$tm_log'
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"5\",\"summary\":\"Task\"}\n'
    else
        exit 1
    fi
    ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github GH_TOKEN=tok GH_ASSIGNEE=myuser \
        "$LOOP" --project "owner/myrepo"
    [[ "$(cat "$tm_log")" == *"GITHUB_REPO=owner/myrepo"* ]]
    rm -f "$tm_log" "$counter_file"
}

@test "todo backend: claims and processes a task from TODO.md" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID
    local todo_file
    todo_file="$(mktemp --suffix=.md)"
    printf '%s\n' "- [ ] Fix the widget" > "$todo_file"

    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"TODO-1\",\"summary\":\"Fix the widget\"}\n'
    else
        exit 1
    fi
    ;;
  *) ;;
esac
"
    local impl_log
    impl_log="$(mktemp)"
    stub_script implement "echo \"\$*\" >> '$impl_log'"

    run env TASK_MANAGER=todo TODO_ASSIGNEE=agent1 \
        "$LOOP" --project "$todo_file"
    [[ "$(cat "$impl_log")" == *"TODO-1"* ]]
    rm -f "$todo_file" "$counter_file" "$impl_log"
}

# ── task-manager claim invocation ─────────────────────────────────────────────

@test "task-manager claim is called with --project and --account-id" {
    local tm_log counter_file
    tm_log="$(mktemp)"
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script task-manager "
echo \"\$*\" >> '$tm_log'
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\"}\n'
    else
        exit 1
    fi
    ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$tm_log")" == *"claim --project PROJ --account-id acc123"* ]]
    rm -f "$tm_log" "$counter_file"
}

@test "github backend: task-manager claim is called with owner/repo as --project and github username as --account-id" {
    unset JIRA_SITE JIRA_EMAIL JIRA_TOKEN JIRA_ASSIGNEE_ACCOUNT_ID
    local tm_log counter_file
    tm_log="$(mktemp)"
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script task-manager "
echo \"\$*\" >> '$tm_log'
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    if [ \"\$count\" -eq 0 ]; then
        printf '{\"key\":\"42\",\"summary\":\"Fix widget\"}\n'
    else
        exit 1
    fi
    ;;
  *) ;;
esac
"
    run env TASK_MANAGER=github GH_TOKEN=tok GH_ASSIGNEE=myuser \
        "$LOOP" --project "owner/myrepo"
    [[ "$(cat "$tm_log")" == *"claim --project owner/myrepo --account-id myuser"* ]]
    rm -f "$tm_log" "$counter_file"
}

# ── --max-tasks ───────────────────────────────────────────────────────────────

@test "--max-tasks: stops after N tasks" {
    local impl_log counter_file real_tm
    impl_log="$(mktemp)"
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script implement "echo \"\$*\" >> '$impl_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    printf '{\"key\":\"PROJ-%s\",\"summary\":\"Task %s\"}\n' \"\$count\" \"\$count\"
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    run "$LOOP" --project PROJ --max-tasks 2
    local lines
    lines=$(wc -l < "$impl_log")
    [[ "$lines" -eq 2 ]]
    rm -f "$impl_log" "$counter_file"
}

@test "--max-tasks: stops after N tasks in planning mode" {
    local plan_log counter_file real_tm
    plan_log="$(mktemp)"
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script plan "echo \"\$*\" >> '$plan_log'"

    stub_script task-manager "
case \"\$1\" in
  claim)
    count=\$(cat '$counter_file')
    echo \$((count + 1)) > '$counter_file'
    printf '{\"key\":\"PROJ-%s\",\"summary\":\"Task %s\"}\n' \"\$count\" \"\$count\"
    ;;
  *)
    exec '$real_tm' \"\$@\"
    ;;
esac
"
    run "$LOOP" --project PROJ --for-planning --max-tasks 2
    local lines
    lines=$(wc -l < "$plan_log")
    [[ "$lines" -eq 2 ]]
    rm -f "$plan_log" "$counter_file"
}
