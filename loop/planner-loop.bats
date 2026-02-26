#!/usr/bin/env bats
# Tests for loop/planner-loop

PLANNER_LOOP="$BATS_TEST_DIRNAME/planner-loop"

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
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Implement feature\",\"description\":\"Feature details\",\"status\":\"Planning\"}\n'
else
    exit 1
fi
"

    # git: create WORK_DIR/.git on clone; simulate plan file creation on agent run
    stub_script git '
case "$1" in
  clone) mkdir -p "${@: -1}/.git" ;;
  *) ;;
esac
'

    # agent: create the plan file in the current directory
    stub_script agent '
# Create the plans directory and plan file as expected
mkdir -p plans
echo "# Plan" > "plans/PROJ-1.md"
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
    run "$PLANNER_LOOP" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--project"* ]]
}

@test "error: missing --agent" {
    run "$PLANNER_LOOP" --project "PROJ"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--agent"* ]]
}

@test "error: unknown option" {
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "--help prints usage" {
    run "$PLANNER_LOOP" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
    run "$PLANNER_LOOP" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── environment variable validation ──────────────────────────────────────────

@test "error: JIRA_SITE not set" {
    unset JIRA_SITE
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_SITE"* ]]
}

@test "error: JIRA_EMAIL not set" {
    unset JIRA_EMAIL
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_EMAIL"* ]]
}

@test "error: JIRA_TOKEN not set" {
    unset JIRA_TOKEN
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_TOKEN"* ]]
}

@test "error: JIRA_ASSIGNEE_ACCOUNT_ID not set" {
    unset JIRA_ASSIGNEE_ACCOUNT_ID
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"JIRA_ASSIGNEE_ACCOUNT_ID"* ]]
}

@test "error: GIT_REPO_URL not set" {
    unset GIT_REPO_URL
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_REPO_URL"* ]]
}

@test "error: GIT_USERNAME not set" {
    unset GIT_USERNAME
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_USERNAME"* ]]
}

@test "error: GIT_TOKEN not set" {
    unset GIT_TOKEN
    run "$PLANNER_LOOP" --project "PROJ" --agent "agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GIT_TOKEN"* ]]
}

# ── happy path ────────────────────────────────────────────────────────────────

@test "happy path: claims issue, clones repo, runs agent, commits plan, transitions to Awaiting Plan Review" {
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

    stub_script agent '
mkdir -p plans
echo "# Plan" > "plans/PROJ-1.md"
'

    run "$PLANNER_LOOP" --project PROJ --agent agent

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

@test "plan file is written at plans/<ISSUE-KEY>.md in the target repository" {
    # Agent writes plan file in the cloned repo directory
    stub_script agent '
mkdir -p plans
echo "# Implementation Plan" > "plans/PROJ-1.md"
'
    stub_script git '
echo "$*"
case "$1" in
  clone) mkdir -p "${@: -1}/.git" ;;
  *) ;;
esac
'

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ -f "$WORK_TMPDIR/repo/plans/PROJ-1.md" ]]
    [[ "$(cat "$WORK_TMPDIR/repo/plans/PROJ-1.md")" == *"Implementation Plan"* ]]
}

@test "pulls instead of clones when repo directory already exists" {
    local git_log
    git_log="$(mktemp)"

    # Pre-create the repo directory to simulate existing clone
    mkdir -p "$WORK_TMPDIR/repo/.git"
    mkdir -p "$WORK_TMPDIR/repo/plans"

    stub_script git "echo \"\$*\" >> '$git_log'"

    # Agent writes plan in the existing repo
    stub_script agent '
mkdir -p plans
echo "# Plan" > "plans/PROJ-1.md"
'

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$output" == *"Pulling latest changes"* ]]
    [[ "$(cat "$git_log")" == *"pull"* ]]
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

    run "$PLANNER_LOOP" --project PROJ --agent agent

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

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$output" == *"Warning: could not post plan comment on PROJ-1"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "transition failure is non-fatal: warning printed, loop continues" {
    stub_script acli '
case "$*" in
  *transition*) exit 1 ;;
  *) ;;
esac
'

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$output" == *"Warning: could not transition PROJ-1 to Awaiting Plan Review"* ]]
    [[ "$output" == *"Planning phase complete for PROJ-1"* ]]
}

@test "agent receives issue key, summary and description in prompt" {
    local agent_log
    agent_log="$(mktemp)"
    stub_script agent "
echo \"\$*\" >> '$agent_log'
mkdir -p plans
echo '# Plan' > plans/PROJ-1.md
"

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$(cat "$agent_log")" == *"PROJ-1"* ]]
    [[ "$(cat "$agent_log")" == *"Implement feature"* ]]
    [[ "$(cat "$agent_log")" == *"Feature details"* ]]

    rm -f "$agent_log"
}

@test "no issues: waits and polls again when claim exits 2" {
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    stub_script claim "
count=\$(cat '$counter_file')
echo \$((count + 1)) > '$counter_file'
if [ \"\$count\" -eq 0 ]; then
    echo 'No planning issues found.'
    exit 2
elif [ \"\$count\" -eq 1 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Implement feature\",\"description\":\"Feature details\",\"status\":\"Planning\"}\n'
else
    exit 1
fi
"

    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$output" == *"No planning issues available"* ]]
    [[ "$output" == *"Waiting"* ]]
    [[ "$output" == *"Working on planning for PROJ-1"* ]]

    rm -f "$counter_file"
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
    echo 'No planning issues found.'
    exit 2
elif [ \"\$count\" -eq 1 ]; then
    printf '{\"key\":\"PROJ-1\",\"summary\":\"Implement feature\",\"description\":\"Feature details\",\"status\":\"Planning\"}\n'
else
    exit 1
fi
"

    export NO_ISSUES_WAIT=120
    run "$PLANNER_LOOP" --project PROJ --agent agent

    [[ "$(cat "$sleep_log")" == *"120"* ]]

    rm -f "$counter_file" "$sleep_log"
}

@test "plan file git-added with correct path before commit" {
    local git_log
    git_log="$(mktemp)"

    stub_script git "
echo \"\$*\" >> '$git_log'
case \"\$1\" in
  clone) mkdir -p \"\${@: -1}/.git\" ;;
  *) ;;
esac
"

    run "$PLANNER_LOOP" --project PROJ --agent agent

    # git add must include the plan file path
    [[ "$(cat "$git_log")" == *"add plans/PROJ-1.md"* ]]
    # git commit follows
    [[ "$(cat "$git_log")" == *"commit"* ]]

    rm -f "$git_log"
}
