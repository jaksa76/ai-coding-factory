#!/usr/bin/env bats
# Tests for loop/plan

PLAN="$BATS_TEST_DIRNAME/plan"

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

    # Default acli stub: returns basic issue info
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
    run "$PLAN"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── agent prompt ──────────────────────────────────────────────────────────────

@test "runs agent with correct planning prompt including issue summary and description" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'
mkdir -p plans
echo '# Plan' > plans/PROJ-1.md
"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug","labels":[],"status":{"name":"To Do"},"assignee":null}}'"'"' ;;
  *) ;;
esac
'

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" == *"Bug details"* ]]
    [[ "$(cat "$agent_log")" == *"plans/PROJ-1.md"* ]]
    [[ "$(cat "$agent_log")" == *"Explore the codebase"* ]]
    [[ "$(cat "$agent_log")" == *"Implementation Steps"* ]]
    [[ "$(cat "$agent_log")" == *"Testing"* ]]
    [[ "$(cat "$agent_log")" == *"Risks"* ]]

    rm -f "$agent_log"
}

@test "uses PLANNING_PROMPT env var when set instead of default prompt" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "echo \"\$*\" >> '$agent_log'
mkdir -p plans
echo '# Plan' > plans/PROJ-1.md
"

    stub_script acli '
case "$*" in
  "jira workitem view"*"--json") echo '"'"'{"key":"PROJ-1","fields":{"description":"Bug details","summary":"Fix the bug","labels":[],"status":{"name":"To Do"},"assignee":null}}'"'"' ;;
  *) ;;
esac
'

    export PLANNING_PROMPT="Custom planning instructions for my project"

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$agent_log")" == *"Custom planning instructions for my project"* ]]
    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Fix the bug"* ]]
    [[ "$(cat "$agent_log")" != *"Explore the codebase"* ]]

    unset PLANNING_PROMPT
    rm -f "$agent_log"
}

# ── git operations ────────────────────────────────────────────────────────────

@test "commits plans/<key>.md and pushes after agent succeeds" {
    local git_log
    git_log="$(mktemp)"

    stub_script agent "
mkdir -p plans
echo '# Plan' > plans/PROJ-1.md
"
    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$git_log")" == *"add plans/PROJ-1.md"* ]]
    [[ "$(cat "$git_log")" == *"commit"* ]]
    [[ "$(cat "$git_log")" == *"push"* ]]

    rm -f "$git_log"
}

@test "pulls instead of clones when repo directory already exists" {
    local git_log
    git_log="$(mktemp)"

    mkdir -p "$WORK_TMPDIR/repo/.git"
    mkdir -p "$WORK_TMPDIR/repo/plans"

    stub_script agent "echo '# Plan' > plans/PROJ-1.md"
    stub_script git "echo \"\$*\" >> '$git_log'"

    run "$PLAN" "PROJ-1"
    [[ "$(cat "$git_log")" == *"pull"* ]]
    [[ "$(cat "$git_log")" != *"clone"* ]]

    rm -f "$git_log"
}

@test "git credentials are stored in credential store, not embedded in URL" {
    local git_log
    git_log="$(mktemp)"

    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"

    run "$PLAN" "PROJ-1"
    [[ "$(cat "$git_log")" != *"gituser:gittoken@"* ]]
    [[ "$(cat "$git_log")" == *"credential.helper"* ]]

    rm -f "$git_log"
}

@test "git user.name and user.email are configured globally" {
    local git_log
    git_log="$(mktemp)"

    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"

    run "$PLAN" "PROJ-1"
    [[ "$(cat "$git_log")" == *"user.name gituser"* ]]
    [[ "$(cat "$git_log")" == *"user.email test@example.com"* ]]

    rm -f "$git_log"
}

# ── comment and transition ────────────────────────────────────────────────────

@test "posts comment with plan URL" {
    local acli_log
    acli_log="$(mktemp)"

    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script acli "
echo \"\$*\" >> '$acli_log'
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"Awaiting Plan Review\"}]' ;;
esac
"

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"comment"* ]]
    [[ "$(cat "$acli_log")" == *"github.com/gituser/repo/blob/main/plans/PROJ-1.md"* ]]

    rm -f "$acli_log"
}

@test "transitions issue to Awaiting Plan Review when status is available" {
    local acli_log
    acli_log="$(mktemp)"

    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script acli "
echo \"\$*\" >> '$acli_log'
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"In Progress\"},{\"name\":\"Awaiting Plan Review\"},{\"name\":\"Done\"}]' ;;
esac
"

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$(cat "$acli_log")" == *"Awaiting Plan Review"* ]]

    rm -f "$acli_log"
}

@test "falls back gracefully when Awaiting Plan Review is not in transitions" {
    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script acli '
case "$*" in
  *transitions*) echo '"'"'[{"name":"In Progress"},{"name":"Done"}]'"'"' ;;
  *) ;;
esac
'

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: Awaiting Plan Review status is absent from the workflow"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "comment failure is non-fatal: warning printed, plan continues" {
    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script acli '
case "$*" in
  *comment*) exit 1 ;;
  *) ;;
esac
'

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: could not post plan comment on PROJ-1"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "transition failure is non-fatal: warning printed, plan continues" {
    stub_script agent "mkdir -p plans && echo '# Plan' > plans/PROJ-1.md"
    stub_script acli "
case \"\$*\" in
  *transitions*) echo '[{\"name\":\"Awaiting Plan Review\"}]' ;;
  *transition*) exit 1 ;;
esac
"

    run "$PLAN" "PROJ-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: could not transition PROJ-1 to Awaiting Plan Review"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}
