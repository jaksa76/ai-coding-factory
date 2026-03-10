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

    # Default stubs — overridden per test as needed
    stub acli ""
    stub agent ""

    # task-manager claim: succeed once (return JSON), then exit 1 to break the loop.
    # Other subcommands (view, comment, transition, transitions) delegate to the real
    # task-manager dispatcher, which calls the stubbed acli.
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

    # git: create WORK_DIR/.git on clone; no-op for other subcommands
    stub_script git '
case "$1" in
  clone) mkdir -p "${@: -1}/.git" ;;
  *) ;;
esac
'
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

# ── feature branch ────────────────────────────────────────────────────────────

@test "feature branch: creates feature/<ISSUE-KEY> when FEATURE_BRANCHES=true" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"

    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *symbolic-ref*) echo "refs/remotes/origin/main" ;;
      *show-ref*) exit 1 ;;
      *) ;;
    esac
    '
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" == *"checkout -b feature/PROJ-1 main"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: resets existing feature branch if present" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"

    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *symbolic-ref*) echo "refs/remotes/origin/main" ;;
      *show-ref*) exit 0 ;;
      *) ;;
    esac
    '
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" == *"branch -f feature/PROJ-1 main"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: skip-branch label disables feature branch even if FEATURE_BRANCHES=true" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    stub_script git 'echo "$*" >> '$git_log'; case "$*" in clone*) mkdir -p "${@: -1}/.git" ;; *) ;; esac'
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["skip-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" != *"checkout -b feature"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: needs-branch label enables feature branch even if FEATURE_BRANCHES is false" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *show-ref*) exit 1 ;;
      *) ;;
    esac
    '
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    unset FEATURE_BRANCHES
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" == *"checkout -b feature/PROJ-1"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: skip-branch label takes precedence over needs-branch" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    stub_script git 'echo "$*" >> '$git_log'; case "$*" in clone*) mkdir -p "${@: -1}/.git" ;; *) ;; esac'
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch","skip-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" != *"checkout -b feature"* ]]
    rm -f "$git_log" "$acli_log"
}

# ── happy path ────────────────────────────────────────────────────────────────

@test "happy path: claims issue, clones repo, runs agent, pushes, comments, transitions" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"
    stub_script acli "echo \"\$*\" >> '$acli_log'"

    run "$LOOP" --project PROJ
    # git clone was called
    [[ "$(cat "$git_log")" == *"clone"* ]]
    # git push was called
    [[ "$(cat "$git_log")" == *"push"* ]]
    # acli comment was called
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    # acli transition was called
    [[ "$(cat "$acli_log")" == *"transition"* ]]
    [[ "$(cat "$acli_log")" == *"Done"* ]]

    rm -f "$git_log" "$acli_log"
}

@test "agent receives issue key, summary and description in prompt" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug"}}'"'"' ;;
  *) ;;
esac
'

    run "$LOOP" --project PROJ
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" == *"Bug details"* ]]

    rm -f "$agent_log"
}

@test "pulls instead of clones when repo directory already exists" {
    local git_log
    git_log="$(mktemp)"

    # Pre-create the repo directory to simulate existing clone
    mkdir -p "$WORK_TMPDIR/repo/.git"

    stub_script git "echo \"\$*\" >> '$git_log'"

    run "$LOOP" --project PROJ
    # pull was called
    [[ "$(cat "$git_log")" == *"pull"* ]]
    # clone was NOT called
    [[ "$(cat "$git_log")" != *"clone"* ]]

    rm -f "$git_log"
}

@test "git credentials are stored in credential store, not embedded in URL" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ
    # credentials must NOT appear embedded in any git URL
    [[ "$(cat "$git_log")" != *"gituser:gittoken@"* ]]
    # git credential helper must be configured via git config
    [[ "$(cat "$git_log")" == *"credential.helper"* ]]

    rm -f "$git_log"
}

@test "git user.name and user.email are configured globally" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$git_log")" == *"user.name gituser"* ]]
    [[ "$(cat "$git_log")" == *"user.email test@example.com"* ]]

    rm -f "$git_log"
}

@test "comment failure is non-fatal: warning printed, loop continues" {
    stub_script acli '
case "$*" in
  *comment*) exit 1 ;;
  *) ;;
esac
'
    run "$LOOP" --project PROJ
    [[ "$output" == *"Warning: could not post comment on PROJ-1"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]
}

@test "transition failure is non-fatal: warning printed, loop continues" {
    stub_script acli '
case "$*" in
  *transition*) exit 1 ;;
  *) ;;
esac
'
    run "$LOOP" --project PROJ
    [[ "$output" == *"Warning: could not transition PROJ-1 to Done"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]
}

@test "claim output with progress messages: JSON is correctly extracted" {
    # Simulate task-manager claim printing progress messages before the JSON
    local counter_file real_tm
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

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
    [[ "$output" == *"Working on PROJ-2: Add feature"* ]]
    [[ "$output" == *"Completed PROJ-2"* ]]

    rm -f "$counter_file"
}

# ── rate limit handling ───────────────────────────────────────────────────────

@test "rate limit: agent retries after waiting when output contains 'rate limit'" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    # Agent fails with a rate limit message on first call, succeeds on second
    stub_script agent "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'API rate limit exceeded. Please retry after 30 seconds.'
    exit 1
fi
"
    run "$LOOP" --project PROJ
    # The issue was completed after retry
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$counter_file"
}

@test "rate limit: wait duration is parsed from agent output" {
    local counter_file sleep_log
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script agent "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'Rate limit exceeded. Retry after 120 seconds.'
    exit 1
fi
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"120"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "rate limit: default wait used when no retry time parseable from output" {
    local counter_file sleep_log
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script agent "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'too many requests'
    exit 1
fi
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"60"* ]]

    rm -f "$counter_file" "$sleep_log"
}


@test "rate limit: non-rate-limit agent errors are not retried" {
    stub_script agent "echo 'Some unexpected error occurred'; exit 1"

    run "$LOOP" --project PROJ
    [ "$status" -ne 0 ]
    [[ "$output" != *"Completed PROJ-1"* ]]
}

@test "no issues: waits and polls again when claim exits 2" {
    local counter_file real_tm
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

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
    [[ "$output" == *"Working on PROJ-1"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$counter_file"
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

# ── plan file handling ────────────────────────────────────────────────────────

@test "plan file: contents included in agent prompt when plans/<ISSUE-KEY>.md exists" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    # Create the plans directory and plan file in the work dir that git clone will create
    stub_script git "
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" \"\${@: -1}/plans\"
         echo 'This is the approved plan.' > \"\${@: -1}/plans/PROJ-1.md\" ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$agent_log")" == *"This is the approved plan."* ]]

    rm -f "$agent_log"
}

@test "plan file: agent proceeds normally when no plan file exists" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    run "$LOOP" --project PROJ
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]

    rm -f "$agent_log"
}

@test "plan file: plan file for a different issue key is not used" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    stub_script git "
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" \"\${@: -1}/plans\"
         echo 'Other issue plan.' > \"\${@: -1}/plans/PROJ-99.md\" ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ
    [[ "$(cat "$agent_log")" != *"Other issue plan."* ]]

    rm -f "$agent_log"
}

@test "inter-issue sleep: default wait is 1200 seconds" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    run "$LOOP" --project PROJ
    [[ "$(cat "$sleep_log")" == *"1200"* ]]

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

@test "rate limit: 'overloaded' in output triggers retry" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script agent "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'The API is currently overloaded. Please try again later.'
    exit 1
fi
"
    run "$LOOP" --project PROJ
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$counter_file"
}

# ── pull request ──────────────────────────────────────────────────────────────

# Helper: shared setup for feature-branch PR tests
# Sets up git, acli, and gh stubs; FEATURE_BRANCHES=true
_setup_feature_branch_pr_test() {
    local git_log="$1" acli_log="$2" gh_log="$3"

    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *symbolic-ref*) echo "refs/remotes/origin/main" ;;
      *show-ref*) exit 1 ;;
      *) ;;
    esac
    '
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    stub_script gh 'echo "$*" >> '$gh_log'; echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true
}

@test "feature branch: opens PR with gh after agent completes" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ
    # gh pr create called with correct base, head, and title
    [[ "$(cat "$gh_log")" == *"--base main"* ]]
    [[ "$(cat "$gh_log")" == *"--head feature/PROJ-1"* ]]
    [[ "$(cat "$gh_log")" == *"[PROJ-1] Fix the bug"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: PR body contains Jira link" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ
    [[ "$(cat "$gh_log")" == *"test.atlassian.net/browse/PROJ-1"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: posts Jira comment with PR URL after PR opened" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    # comment includes the PR URL
    [[ "$(cat "$acli_log")" == *"https://github.com/org/repo/pull/42"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: transitions issue to In Review after PR opened" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ
    [[ "$(cat "$acli_log")" == *"transition"* ]]
    [[ "$(cat "$acli_log")" == *"In Review"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: PR failure is non-fatal - warning printed, loop continues" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"

    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *symbolic-ref*) echo "refs/remotes/origin/main" ;;
      *show-ref*) exit 1 ;;
      *) ;;
    esac
    '
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    stub_script gh 'exit 1'
    export FEATURE_BRANCHES=true

    run "$LOOP" --project PROJ
    [[ "$output" == *"Warning: could not open pull request for PROJ-1"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$git_log" "$acli_log"
}

@test "feature branch: In Review transition failure is non-fatal" {
    local git_log gh_log
    git_log="$(mktemp)"
    gh_log="$(mktemp)"

    stub_script git '
    echo "$*" >> '$git_log'
    case "$*" in
      clone*) mkdir -p "${@: -1}/.git" ;;
      *symbolic-ref*) echo "refs/remotes/origin/main" ;;
      *show-ref*) exit 1 ;;
      *) ;;
    esac
    '
    stub_script acli '
case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":{"accountId":"acc1"},"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *transition*) exit 1 ;;
  *) ;;
esac
'
    stub_script gh 'echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true

    run "$LOOP" --project PROJ
    [[ "$output" == *"Warning: could not transition PROJ-1 to In Review"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$git_log" "$gh_log"
}

# ── planning mode ─────────────────────────────────────────────────────────────

# Helper: stub the agent to create plans/PROJ-1.md (required for planning loop
# to reach git-add/commit/push without the real agent running)
_setup_planning_agent_stub() {
    stub_script agent '
mkdir -p plans
echo "# Plan" > "plans/PROJ-1.md"
'
}

@test "planning mode: happy path: claims issue, clones repo, runs agent, commits plan, transitions to Awaiting Plan Review" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"
    stub_script acli "
echo \"\$*\" >> '$acli_log'
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"In Progress\"},{\"name\":\"Awaiting Plan Review\"},{\"name\":\"Done\"}]' ;;
esac
"
    _setup_planning_agent_stub

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"Working on planning for PROJ-1"* ]]
    [[ "$output" == *"Cloning"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]

    # git clone was called
    [[ "$(cat "$git_log")" == *"clone"* ]]
    # git push was called
    [[ "$(cat "$git_log")" == *"push"* ]]
    # acli comment was called
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    # acli transition to Awaiting Plan Review was called
    [[ "$(cat "$acli_log")" == *"Awaiting Plan Review"* ]]

    rm -f "$git_log" "$acli_log"
}

@test "planning mode: plan file is written at plans/<ISSUE-KEY>.md in the target repository" {
    stub_script agent '
mkdir -p plans
echo "# Implementation Plan" > "plans/PROJ-1.md"
'
    stub_script git '
case "$1" in
  clone) mkdir -p "${@: -1}/.git" ;;
  *) ;;
esac
'

    run "$LOOP" --project PROJ --for-planning

    [[ -f "$WORK_TMPDIR/repo/plans/PROJ-1.md" ]]
    [[ "$(cat "$WORK_TMPDIR/repo/plans/PROJ-1.md")" == *"Implementation Plan"* ]]
}

@test "planning mode: pulls instead of clones when repo directory already exists" {
    local git_log
    git_log="$(mktemp)"

    # Pre-create the repo directory to simulate existing clone
    mkdir -p "$WORK_TMPDIR/repo/.git"
    mkdir -p "$WORK_TMPDIR/repo/plans"

    stub_script git "echo \"\$*\" >> '$git_log'"
    _setup_planning_agent_stub

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"Pulling latest changes"* ]]
    [[ "$(cat "$git_log")" == *"pull"* ]]
    [[ "$(cat "$git_log")" != *"clone"* ]]

    rm -f "$git_log"
}

@test "planning mode: comment failure is non-fatal: warning printed, loop continues" {
    _setup_planning_agent_stub
    stub_script acli '
case "$*" in
  *comment*) exit 1 ;;
  *) ;;
esac
'

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"Warning: could not post plan comment on PROJ-1"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "planning mode: transition failure is non-fatal: warning printed, loop continues" {
    _setup_planning_agent_stub
    stub_script acli "
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"Awaiting Plan Review\"}]' ;;
  *transition*) exit 1 ;;
esac
"

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"Warning: could not transition PROJ-1 to Awaiting Plan Review"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "planning mode: Awaiting Plan Review status absent: warning printed, transition skipped, loop continues" {
    _setup_planning_agent_stub
    stub_script acli '
case "$*" in
  *transitions*) echo '"'"'[{"name":"In Progress"},{"name":"Done"}]'"'"' ;;
  *) ;;
esac
'

    run "$LOOP" --project PROJ --for-planning

    [[ "$output" == *"Warning: Awaiting Plan Review status is absent from the workflow"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "planning mode: agent receives issue key, summary and description in prompt" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "
echo \"\$*\" >> '$agent_log'
mkdir -p plans
echo '# Plan' > plans/PROJ-1.md
"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug"}}'"'"' ;;
  *) ;;
esac
'

    run "$LOOP" --project PROJ --for-planning

    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" == *"Bug details"* ]]

    rm -f "$agent_log"
}

@test "planning mode: no issues: waits and polls again when claim exits 2" {
    local counter_file real_tm
    counter_file="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    _setup_planning_agent_stub

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
    [[ "$output" == *"Working on planning for PROJ-1"* ]]

    rm -f "$counter_file"
}

@test "planning mode: NO_ISSUES_WAIT overrides default wait" {
    local counter_file sleep_log real_tm
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    real_tm="$BATS_TEST_DIRNAME/../task-manager/task-manager"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"
    _setup_planning_agent_stub

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

    rm -f "$counter_file" "$sleep_log"
}

@test "planning mode: comment contains GitHub blob URL for the plan file" {
    local acli_log
    acli_log="$(mktemp)"

    _setup_planning_agent_stub
    stub_script acli "
echo \"\$*\" >> '$acli_log'
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"Awaiting Plan Review\"}]' ;;
esac
"

    run "$LOOP" --project PROJ --for-planning

    [[ "$(cat "$acli_log")" == *"github.com/gituser/repo/blob/main/plans/PROJ-1.md"* ]]

    rm -f "$acli_log"
}

@test "planning mode: plan file git-added with correct path before commit" {
    local git_log
    git_log="$(mktemp)"

    _setup_planning_agent_stub
    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"

    run "$LOOP" --project PROJ --for-planning

    # git add must include the plan file path
    [[ "$(cat "$git_log")" == *"add plans/PROJ-1.md"* ]]
    # git commit follows
    [[ "$(cat "$git_log")" == *"commit"* ]]

    rm -f "$git_log"
}
