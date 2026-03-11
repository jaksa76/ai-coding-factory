#!/usr/bin/env bats
# Integration tests for loop/loop — uses real Jira API and a local git repository.
#
# Prerequisites:
#   - .env exists at the repo root with JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN,
#     GIT_REPO_URL, GIT_USERNAME, GIT_TOKEN
#   - acli is authenticated
#
# Creates and deletes real Jira issues in the SCRUM project.

LOOP="$BATS_TEST_DIRNAME/loop"
REAL_TASK_MANAGER="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/task-manager/task-manager"
ENV_FILE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env"

# Account ID for jaksa76@gmail.com on jaksa.atlassian.net
ACCOUNT_ID="712020:2b77122e-3452-4f6b-8fb5-776644a6197c"
PROJECT="SCRUM"

# ── helpers ───────────────────────────────────────────────────────────────────

# Create a test Jira issue and optionally apply a label.
# Records the key in CLEANUP_FILE for teardown.
# Uses REAL_SLEEP (set in setup_file before any sleep stub) for label propagation.
create_test_issue() {
    local label="${1:-}"
    local json key
    json=$(acli jira workitem create \
        --summary "[test] loop-integration $(date +%s%N)" \
        --project "$PROJECT" --type "Task" --json 2>&1)
    key=$(printf '%s' "$json" | jq -r '.key // empty')
    [[ -z "$key" ]] && { echo "create failed: $json" >&3; return 1; }
    if [[ -n "$label" ]]; then
        acli jira workitem edit --key "$key" --labels "$label" --yes >/dev/null 2>&1 || true
        # Use real sleep (captured before stub is installed) so the label has
        # time to propagate into Jira's JQL search index.
        "${REAL_SLEEP}" 10
    fi
    echo "$key" >> "$CLEANUP_FILE"
    echo "$key"
}

issue_assignee() {
    acli jira workitem view "$1" --json 2>/dev/null \
        | jq -r '.fields.assignee.accountId // empty'
}

issue_status() {
    acli jira workitem view "$1" --json 2>/dev/null \
        | jq -r '.fields.status.name // empty'
}

# Returns 0 if plans/<KEY>.md exists in the bare repo, 1 otherwise.
plan_in_repo() {
    local key="$1"
    local tmp
    tmp=$(mktemp -d)
    git clone "file://$PLANNER_BARE_REPO" "$tmp/clone" -q 2>/dev/null
    local result=1
    [[ -f "$tmp/clone/plans/$key.md" ]] && result=0
    rm -rf "$tmp"
    return "$result"
}

# ── file-level setup / teardown ───────────────────────────────────────────────

setup_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "SKIP: $ENV_FILE not found" >&3
        skip "No .env file found"
    fi

    # Capture the real sleep binary before any per-test stub overrides PATH.
    REAL_SLEEP="$(command -v sleep)"
    export REAL_SLEEP

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE

    # Authenticate if needed
    if ! acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
        printf '%s' "$JIRA_TOKEN" \
            | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token 2>&1
    fi

    # Create an unassigned test issue for the implementation loop test
    local json
    json=$(acli jira workitem create \
        --summary "[test] loop integration test - $(date +%s)" \
        --description "Test issue for loop integration testing" \
        --project "$PROJECT" \
        --type "Task" \
        --json 2>&1)
    TEST_ISSUE_KEY=$(printf '%s' "$json" | jq -r '.key // empty')

    if [[ -z "$TEST_ISSUE_KEY" ]]; then
        echo "SKIP: could not create test issue: $json" >&3
        skip "Failed to create test Jira issue"
    fi

    export TEST_ISSUE_KEY
    echo "# Created test issue: $TEST_ISSUE_KEY" >&3

    # Shared file for tracking all test issues created during the run
    CLEANUP_FILE=$(mktemp)
    export CLEANUP_FILE
}

teardown_file() {
    # Delete the implementation loop test issue
    if [[ -n "${TEST_ISSUE_KEY:-}" ]]; then
        acli jira workitem delete "$TEST_ISSUE_KEY" --force 2>/dev/null || true
        echo "# Deleted test issue: $TEST_ISSUE_KEY" >&3
    fi

    # Delete any remaining planning test issues not already cleaned in teardown
    if [[ -f "${CLEANUP_FILE:-}" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete "$key" --force 2>/dev/null || true
            echo "# Deleted test issue: $key" >&3
        done < "$CLEANUP_FILE"
        rm -f "$CLEANUP_FILE"
    fi
}

# ── per-test setup / teardown ─────────────────────────────────────────────────

setup() {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE JIRA_EMAIL JIRA_TOKEN
    export JIRA_ASSIGNEE_ACCOUNT_ID="$ACCOUNT_ID"

    # Local bare git repository so loop can clone and push without a real remote
    REPO_TMPDIR="$(mktemp -d)"
    local bare_repo="$REPO_TMPDIR/test-repo.git"
    git init --bare "$bare_repo" >/dev/null 2>&1

    # Seed with an initial commit so clones get a non-empty repo with a HEAD
    local init_clone="$REPO_TMPDIR/init"
    git clone "$bare_repo" "$init_clone" >/dev/null 2>&1
    git -C "$init_clone" config user.email "test@example.com"
    git -C "$init_clone" config user.name "Test"
    echo "init" > "$init_clone/README.md"
    git -C "$init_clone" add README.md
    git -C "$init_clone" commit -m "initial commit" >/dev/null 2>&1
    git -C "$init_clone" push origin HEAD >/dev/null 2>&1
    rm -rf "$init_clone"

    export GIT_REPO_URL="$bare_repo"
    export GIT_USERNAME="testuser"
    export GIT_TOKEN="testtoken"
    export BARE_REPO="$bare_repo"

    # Temporary work dir for loop's clones
    LOOP_TMPDIR="$(mktemp -d)"
    export LOOP_WORK_DIR="$LOOP_TMPDIR"

    # Stub dir: no-op sleep + task-manager wrapper that delegates to real
    # task-manager claim once then exits 1 to terminate the loop's infinite loop.
    STUB_DIR="$(mktemp -d)"
    printf '#!/usr/bin/env bash\n' > "$STUB_DIR/sleep"
    chmod +x "$STUB_DIR/sleep"

    CLAIM_COUNTER="$(mktemp)"
    echo "0" > "$CLAIM_COUNTER"
    cat > "$STUB_DIR/task-manager" << STUB_EOF
#!/usr/bin/env bash
case "\$1" in
  claim)
    count=\$(cat '$CLAIM_COUNTER')
    echo \$((count + 1)) > '$CLAIM_COUNTER'
    if [ "\$count" -eq 0 ]; then
        exec '$REAL_TASK_MANAGER' "\$@"
    else
        exit 1
    fi
    ;;
  *)
    exec '$REAL_TASK_MANAGER' "\$@"
    ;;
esac
STUB_EOF
    chmod +x "$STUB_DIR/task-manager"

    # Git identity for commits made during tests
    export GIT_AUTHOR_NAME="Test Agent"
    export GIT_AUTHOR_EMAIL="agent@test.example.com"
    export GIT_COMMITTER_NAME="Test Agent"
    export GIT_COMMITTER_EMAIL="agent@test.example.com"

    # Create an 'agent' stub in STUB_DIR that delegates to mock-agent
    cat > "$STUB_DIR/agent" << 'AGENT_EOF'
#!/usr/bin/env bash
exec mock-agent "$@"
AGENT_EOF
    chmod +x "$STUB_DIR/agent"

    # PATH: stubs first, then loop dir (contains mock-agent), then original PATH
    export PATH="$STUB_DIR:$BATS_TEST_DIRNAME:$PATH"

    # Baseline for per-test planning issue cleanup in teardown
    CLEANUP_BASELINE=$(wc -l < "${CLEANUP_FILE:-/dev/null}" 2>/dev/null || echo 0)
    export CLEANUP_BASELINE
}

teardown() {
    rm -rf "${STUB_DIR:-}" "${LOOP_TMPDIR:-}" "${REPO_TMPDIR:-}" \
           "${PLANNER_BARE_REPO:-}" "${PLANNER_LOOP_TMPDIR:-}" "${PLANNER_STUB_DIR:-}"
    rm -f "${CLAIM_COUNTER:-}"


    # Delete test issues created by this specific test
    if [[ -f "${CLEANUP_FILE:-}" ]]; then
        tail -n +"$((CLEANUP_BASELINE + 1))" "$CLEANUP_FILE" | while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete --key "$key" -y 2>/dev/null || true
            echo "# [teardown] Deleted $key" >&3
        done
    fi
}

# ── implementation loop test ──────────────────────────────────────────────────

@test "loop: processes real Jira issue, transitions to Done, and pushes work-log.md" {
    # Ensure the test issue is unassigned so there is at least one issue to claim
    acli jira workitem transition --key "$TEST_ISSUE_KEY" --status "To Do" --yes 2>/dev/null || true
    acli jira workitem assign --key "$TEST_ISSUE_KEY" --remove-assignee --yes 2>/dev/null || true

    run "$LOOP" --project "$PROJECT"

    echo "# output: $output" >&3
    # Loop exits with status 1 when claim returns 1 on the second iteration
    [ "$status" -eq 1 ]

    # Extract which issue was actually processed
    local processed_key
    processed_key=$(printf '%s\n' "$output" | grep -o 'Completed [A-Z]*-[0-9]*' | awk '{print $2}')
    echo "# processed issue: $processed_key" >&3
    [[ -n "$processed_key" ]]

    # Jira issue is now in Done status
    local status_name
    status_name=$(acli jira workitem view "$processed_key" --json 2>/dev/null \
        | jq -r '.fields.status.name // empty')
    echo "# issue status after loop: $status_name" >&3
    [[ "$status_name" == "Done" ]]

    # mock-agent's work-log.md was committed and pushed to the repository
    local check_clone="$REPO_TMPDIR/verify"
    git clone "$BARE_REPO" "$check_clone" >/dev/null 2>&1
    [ -f "$check_clone/work-log.md" ]
    [[ "$(cat "$check_clone/work-log.md")" == *"$processed_key"* ]]
}

# ── planning mode integration tests (L1–L5) ───────────────────────────────────

_setup_planning_integration() {
    # Local bare repository for plan commits
    PLANNER_BARE_REPO=$(mktemp -d)
    git init --bare "$PLANNER_BARE_REPO" -q
    local seed_dir
    seed_dir=$(mktemp -d)
    (
        git -C "$seed_dir" init -q
        GIT_AUTHOR_NAME="seed" GIT_AUTHOR_EMAIL="s@s.s" \
        GIT_COMMITTER_NAME="seed" GIT_COMMITTER_EMAIL="s@s.s" \
            git -C "$seed_dir" commit --allow-empty -m "init" -q
        git -C "$seed_dir" remote add origin "file://$PLANNER_BARE_REPO"
        git -C "$seed_dir" push -u origin HEAD:main -q
    )
    rm -rf "$seed_dir"
    export PLANNER_BARE_REPO

    export GIT_REPO_URL="file://$PLANNER_BARE_REPO"
    export GIT_USERNAME="testuser"
    export GIT_TOKEN="testtoken"

    PLANNER_LOOP_TMPDIR=$(mktemp -d)
    export LOOP_WORK_DIR="$PLANNER_LOOP_TMPDIR"

    export GIT_AUTHOR_NAME="planner-loop-test"
    export GIT_AUTHOR_EMAIL="test@test.test"
    export GIT_COMMITTER_NAME="planner-loop-test"
    export GIT_COMMITTER_EMAIL="test@test.test"

    # Stub agent: extract the issue key from the prompt and write a plan file
    PLANNER_STUB_DIR=$(mktemp -d)
    cat > "$PLANNER_STUB_DIR/agent" <<'EOF'
#!/usr/bin/env bash
KEY=$(printf '%s' "$*" | grep -oE '[A-Z]+-[0-9]+' | head -1)
mkdir -p plans
echo "# Plan for $KEY" > "plans/$KEY.md"
EOF
    chmod +x "$PLANNER_STUB_DIR/agent"

    # Prepend the planner stub dir to PATH
    # ($STUB_DIR/task-manager from setup() is still the task-manager entry point)
    export PATH="$PLANNER_STUB_DIR:$PATH"
}

@test "L1: loop --for-planning: PLAN_BY_DEFAULT=false, needs-plan — claimed, plan committed, transitioned" {
    _setup_planning_integration
    KEY=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 120 "$LOOP" --project "$PROJECT" --for-planning
    [[ "$(issue_assignee "$KEY")" == "$JIRA_ASSIGNEE_ACCOUNT_ID" ]]
    plan_in_repo "$KEY"
    local s
    s=$(issue_status "$KEY")
    [[ "$s" == "Awaiting Plan Review" || "$s" == "Planning" ]]
}

@test "L2: loop --for-planning: PLAN_BY_DEFAULT=false, no label — issue NOT claimed" {
    _setup_planning_integration
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run timeout 20 "$LOOP" --project "$PROJECT" --for-planning
    [[ "$(issue_assignee "$KEY")" != "$JIRA_ASSIGNEE_ACCOUNT_ID" ]]
}

@test "L3: loop --for-planning: PLAN_BY_DEFAULT=false, skip-plan label — issue NOT claimed" {
    _setup_planning_integration
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 20 "$LOOP" --project "$PROJECT" --for-planning
    [[ "$(issue_assignee "$KEY")" != "$JIRA_ASSIGNEE_ACCOUNT_ID" ]]
}

@test "L4: loop --for-planning: PLAN_BY_DEFAULT=true, no label — claimed, plan committed, transitioned" {
    _setup_planning_integration
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run timeout 120 "$LOOP" --project "$PROJECT" --for-planning
    [[ "$(issue_assignee "$KEY")" == "$JIRA_ASSIGNEE_ACCOUNT_ID" ]]
    plan_in_repo "$KEY"
    local s
    s=$(issue_status "$KEY")
    [[ "$s" == "Awaiting Plan Review" || "$s" == "Planning" ]]
}

@test "L5: loop --for-planning: PLAN_BY_DEFAULT=true, skip-plan label — issue NOT claimed" {
    _setup_planning_integration
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run timeout 20 "$LOOP" --project "$PROJECT" --for-planning
    [[ "$(issue_assignee "$KEY")" != "$JIRA_ASSIGNEE_ACCOUNT_ID" ]]
}
