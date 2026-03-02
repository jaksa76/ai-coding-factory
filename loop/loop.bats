#!/usr/bin/env bats
# Tests for loop/loop

LOOP="$BATS_TEST_DIRNAME/loop"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    # Per-test stub directory on PATH
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"

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

    # claim: succeed once (return JSON), then exit 1 to break the loop
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"
    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\",\"description\":\"Bug details\",\"status\":\"In Progress\"}\n'
else
    exit 1
fi
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
    run "$LOOP" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "error: missing --agent" {
    run "$LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--agent"* ]]
}

@test "error: unknown option" {
    run "$LOOP" --project "PROJ" --agent "agent" --unknown
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
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

@test "error: JIRA_EMAIL not set" {
    unset JIRA_EMAIL
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_EMAIL"* ]]
}

@test "error: JIRA_TOKEN not set" {
    unset JIRA_TOKEN
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_TOKEN"* ]]
}

@test "error: JIRA_ASSIGNEE_ACCOUNT_ID not set" {
    unset JIRA_ASSIGNEE_ACCOUNT_ID
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_ASSIGNEE_ACCOUNT_ID"* ]]
}

@test "error: GIT_REPO_URL not set" {
    unset GIT_REPO_URL
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_REPO_URL"* ]]
}

@test "error: GIT_USERNAME not set" {
    unset GIT_USERNAME
    run "$LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_USERNAME"* ]]
}

@test "error: GIT_TOKEN not set" {
    unset GIT_TOKEN
    run "$LOOP" --project "PROJ" --agent "agent"
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
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ --agent agent
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
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ --agent agent
    [[ "$(cat "$git_log")" == *"branch -f feature/PROJ-1 main"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: skip-branch label disables feature branch even if FEATURE_BRANCHES=true" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    stub_script git 'echo "$*" >> '$git_log'; case "$*" in clone*) mkdir -p "${@: -1}/.git" ;; *) ;; esac'
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["skip-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ --agent agent
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
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    unset FEATURE_BRANCHES
    run "$LOOP" --project PROJ --agent agent
    [[ "$(cat "$git_log")" == *"checkout -b feature/PROJ-1"* ]]
    rm -f "$git_log" "$acli_log"
}

@test "feature branch: skip-branch label takes precedence over needs-branch" {
    local git_log acli_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    stub_script git 'echo "$*" >> '$git_log'; case "$*" in clone*) mkdir -p "${@: -1}/.git" ;; *) ;; esac'
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch","skip-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    export FEATURE_BRANCHES=true
    run "$LOOP" --project PROJ --agent agent
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

    run "$LOOP" --project PROJ --agent agent

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

    run "$LOOP" --project PROJ --agent agent

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

    run "$LOOP" --project PROJ --agent agent

    # pull was called
    [[ "$(cat "$git_log")" == *"pull"* ]]
    # clone was NOT called
    [[ "$(cat "$git_log")" != *"clone"* ]]

    rm -f "$git_log"
}

@test "git credentials are injected into clone URL" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$git_log")" == *"gituser:gittoken"* ]]

    rm -f "$git_log"
}

@test "comment failure is non-fatal: warning printed, loop continues" {
    stub_script acli '
case "$*" in
  *comment*) exit 1 ;;
  *) ;;
esac
'
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

    [[ "$output" == *"Warning: could not transition PROJ-1 to Done"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]
}

@test "claim output with progress messages: JSON is correctly extracted" {
    # Simulate claim printing progress messages before the JSON
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'Searching for unassigned open issues in project PROJ...'
    echo 'Attempting to claim PROJ-2...'
    echo 'Successfully claimed PROJ-2.'
    printf '{\"key\":\"PROJ-2\",\"summary\":\"Add feature\",\"description\":\"Details here\",\"status\":\"In Progress\"}\n'
else
    exit 1
fi
"
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$sleep_log")" == *"60"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "rate limit: RATE_LIMIT_WAIT overrides default wait" {
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
    export RATE_LIMIT_WAIT=300
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$sleep_log")" == *"300"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "rate limit: non-rate-limit agent errors are not retried" {
    stub_script agent "echo 'Some unexpected error occurred'; exit 1"

    run "$LOOP" --project PROJ --agent agent

    [ "$status" -ne 0 ]
    [[ "$output" != *"Completed PROJ-1"* ]]
}

@test "no issues: waits and polls again when claim exits 2" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'No unassigned open issues found in project PROJ.'
    exit 2
elif [ \"\$count\" -eq 1 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\",\"description\":\"Bug details\",\"status\":\"In Progress\"}\n'
else
    exit 1
fi
"
    run "$LOOP" --project PROJ --agent agent

    [[ "$output" == *"Working on PROJ-1"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$counter_file"
}

@test "no issues: default wait is 60 seconds" {
    local counter_file sleep_log
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'No unassigned open issues found in project PROJ.'
    exit 2
elif [ \"\$count\" -eq 1 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\",\"description\":\"Bug details\",\"status\":\"In Progress\"}\n'
else
    exit 1
fi
"
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$sleep_log")" == *"60"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "no issues: NO_ISSUES_WAIT overrides default wait" {
    local counter_file sleep_log
    counter_file="$(mktemp)"
    sleep_log="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'No unassigned open issues found in project PROJ.'
    exit 2
elif [ \"\$count\" -eq 1 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Fix the bug\",\"description\":\"Bug details\",\"status\":\"In Progress\"}\n'
else
    exit 1
fi
"
    export NO_ISSUES_WAIT=120
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$agent_log")" == *"This is the approved plan."* ]]

    rm -f "$agent_log"
}

@test "plan file: agent proceeds normally when no plan file exists" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$agent_log")" != *"Other issue plan."* ]]

    rm -f "$agent_log"
}

@test "inter-issue sleep: default wait is 1200 seconds" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$sleep_log")" == *"1200"* ]]

    rm -f "$sleep_log"
}

@test "inter-issue sleep: INTER_ISSUE_WAIT overrides default wait" {
    local sleep_log
    sleep_log="$(mktemp)"

    stub_script sleep "echo \"\$*\" >> '$sleep_log'"

    export INTER_ISSUE_WAIT=5
    run "$LOOP" --project PROJ --agent agent

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
    run "$LOOP" --project PROJ --agent agent

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
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    stub_script gh 'echo "$*" >> '$gh_log'; echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true
}

@test "feature branch: opens PR with gh after agent completes" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ --agent agent

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

    run "$LOOP" --project PROJ --agent agent

    [[ "$(cat "$gh_log")" == *"test.atlassian.net/browse/PROJ-1"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: posts Jira comment with PR URL after PR opened" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$LOOP" --project PROJ --agent agent

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

    run "$LOOP" --project PROJ --agent agent

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
    stub_script acli 'if [[ "$*" == *"--field labels"* ]]; then printf '"'"'["needs-branch"]\n'"'"'; else echo "$*" >> '$acli_log'; fi'
    stub_script gh 'exit 1'
    export FEATURE_BRANCHES=true

    run "$LOOP" --project PROJ --agent agent

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
  *"--field labels"*) printf '"'"'["needs-branch"]\n'"'"' ;;
  *transition*) exit 1 ;;
  *) ;;
esac
'
    stub_script gh 'echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true

    run "$LOOP" --project PROJ --agent agent

    [[ "$output" == *"Warning: could not transition PROJ-1 to In Review"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$git_log" "$gh_log"
}
