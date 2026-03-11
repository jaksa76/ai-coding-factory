#!/usr/bin/env bats
# Tests for loop/implement

IMPLEMENT="$BATS_TEST_DIRNAME/implement"

# ── helpers ──────────────────────────────────────────────────────────────────

setup() {
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$BATS_TEST_DIRNAME/../task-manager:$PATH"

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
    stub agent ""
    stub gh ""

    # Default acli stub: basic issue view
    stub_script acli "echo \"\$*\""

    # Default git stub: create WORK_DIR/.git on clone; no-op for other subcommands
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

# ── usage ─────────────────────────────────────────────────────────────────────

@test "fails with usage error when no issue key provided" {
    run "$IMPLEMENT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── agent prompt ──────────────────────────────────────────────────────────────

@test "runs agent with correct implementation prompt (no feature branch)" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug","labels":[],"status":{"name":"To Do"},"assignee":null}}'"'"' ;;
  *) ;;
esac
'

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" == *"Bug details"* ]]

    rm -f "$agent_log"
}

@test "includes plan file contents in prompt when plans/<key>.md exists" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    stub_script git "
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" \"\${@: -1}/plans\"
         echo 'This is the approved plan.' > \"\${@: -1}/plans/PROJ-1.md\" ;;
  *) ;;
esac
"

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"This is the approved plan."* ]]

    rm -f "$agent_log"
}

@test "skips plan file when it does not exist" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" != *"implementation plan"* ]]

    rm -f "$agent_log"
}

@test "uses IMPLEMENTATION_PROMPT env var when set instead of default prompt" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug","labels":[],"status":{"name":"To Do"},"assignee":null}}'"'"' ;;
  *) ;;
esac
'

    export IMPLEMENTATION_PROMPT="Custom implementation instructions for my project"

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"Custom implementation instructions for my project"* ]]
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" != *"Explore the codebase"* ]]

    unset IMPLEMENTATION_PROMPT
    rm -f "$agent_log"
}

@test "plan file for a different issue key is not used" {
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

    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$agent_log")" != *"Other issue plan."* ]]

    rm -f "$agent_log"
}

# ── feature branch ────────────────────────────────────────────────────────────

@test "creates feature branch when FEATURE_BRANCHES=true" {
    local git_log
    git_log="$(mktemp)"

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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) ;;
esac'
    export FEATURE_BRANCHES=true
    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$git_log")" == *"checkout -b feature/PROJ-1 main"* ]]
    rm -f "$git_log"
}

@test "creates feature branch when needs-branch label is present" {
    local git_log
    git_log="$(mktemp)"

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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) ;;
esac'
    unset FEATURE_BRANCHES
    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$git_log")" == *"checkout -b feature/PROJ-1"* ]]
    rm -f "$git_log"
}

@test "skips feature branch when skip-branch label is present" {
    local git_log
    git_log="$(mktemp)"

    stub_script git 'echo "$*" >> '$git_log'; case "$*" in clone*) mkdir -p "${@: -1}/.git" ;; *) ;; esac'
    stub_script acli 'case "$*" in
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["skip-branch"]}}'"'"' ;;
  *) ;;
esac'
    export FEATURE_BRANCHES=true
    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$git_log")" != *"checkout -b feature"* ]]
    rm -f "$git_log"
}

@test "resets existing feature branch if present" {
    local git_log
    git_log="$(mktemp)"

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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) ;;
esac'
    export FEATURE_BRANCHES=true
    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$git_log")" == *"branch -f feature/PROJ-1 main"* ]]
    rm -f "$git_log"
}

# ── happy path (no feature branch) ───────────────────────────────────────────

@test "happy path: clones repo, runs agent, pushes, comments, transitions to Done" {
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

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$git_log")" == *"clone"* ]]
    [[ "$(cat "$git_log")" == *"push"* ]]
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    [[ "$(cat "$acli_log")" == *"transition"* ]]
    [[ "$(cat "$acli_log")" == *"Done"* ]]

    rm -f "$git_log" "$acli_log"
}

@test "comment failure is non-fatal: warning printed, implement continues" {
    stub_script acli '
case "$*" in
  *comment*) exit 1 ;;
  *) ;;
esac
'

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: could not post comment on PROJ-1"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]
}

@test "transition failure is non-fatal: warning printed, implement continues" {
    stub_script acli '
case "$*" in
  *transition*) exit 1 ;;
  *) ;;
esac
'

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: could not transition PROJ-1 to Done"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]
}

# ── feature branch PR flow ────────────────────────────────────────────────────

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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    stub_script gh 'echo "$*" >> '$gh_log'; echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true
}

@test "feature branch: opens PR and transitions to In Review" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$gh_log")" == *"--base main"* ]]
    [[ "$(cat "$gh_log")" == *"--head feature/PROJ-1"* ]]
    [[ "$(cat "$acli_log")" == *"transition"* ]]
    [[ "$(cat "$acli_log")" == *"In Review"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: PR body contains Jira link" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$gh_log")" == *"test.atlassian.net/browse/PROJ-1"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: posts Jira comment with PR URL after PR opened" {
    local git_log acli_log gh_log
    git_log="$(mktemp)"
    acli_log="$(mktemp)"
    gh_log="$(mktemp)"

    _setup_feature_branch_pr_test "$git_log" "$acli_log" "$gh_log"

    run "$IMPLEMENT" "PROJ-1"
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    [[ "$(cat "$acli_log")" == *"https://github.com/org/repo/pull/42"* ]]

    rm -f "$git_log" "$acli_log" "$gh_log"
}

@test "feature branch: PR failure is non-fatal - warning printed, implement continues" {
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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *) echo "$*" >> '"'$acli_log'"' ;;
esac'
    stub_script gh 'exit 1'
    export FEATURE_BRANCHES=true

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
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
  *"workitem view"*) echo '"'"'{"key":"PROJ-1","fields":{"assignee":null,"summary":"Fix bug","description":"","status":{"name":"To Do"},"labels":["needs-branch"]}}'"'"' ;;
  *transition*) exit 1 ;;
  *) ;;
esac
'
    stub_script gh 'echo "https://github.com/org/repo/pull/42"'
    export FEATURE_BRANCHES=true

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: could not transition PROJ-1 to In Review"* ]]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$git_log" "$gh_log"
}

# ── rate limit handling ───────────────────────────────────────────────────────

@test "rate limit: agent retries after waiting when output contains 'rate limit'" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script agent "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'API rate limit exceeded. Please retry after 30 seconds.'
    exit 1
fi
"
    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Completed PROJ-1"* ]]

    rm -f "$counter_file"
}

@test "rate limit: non-rate-limit agent errors are not retried" {
    stub_script agent "echo 'Some unexpected error occurred'; exit 1"

    run "$IMPLEMENT" "PROJ-1"
    [ "$status" -ne 0 ]
    [[ "$output" != *"Completed PROJ-1"* ]]
}
