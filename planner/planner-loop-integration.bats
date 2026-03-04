#!/usr/bin/env bats
# Integration tests for planner/planner-loop — uses real Jira API, local bare git.
#
# Prerequisites:
#   - .env exists at the repo root with JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN,
#     and JIRA_ASSIGNEE_ACCOUNT_ID
#   - acli is on PATH (tests will authenticate if needed)
#   - JIRA_SITE may include https:// prefix; tests strip it automatically
#   - git is on PATH with a version that supports --bare and file:// remotes
#
# A stub agent writes a plan file; git operations target a local bare repository
# created per test run — no GitHub credentials needed.
#
# These tests create and delete real Jira issues in the SCRUM project.
# They assume the SCRUM project has no other matching unassigned issues between runs.

PLANNER_LOOP="$BATS_TEST_DIRNAME/planner-loop"
ENV_FILE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env"

# Account ID for jaksa76@gmail.com on jaksa.atlassian.net
ACCOUNT_ID="712020:2b77122e-3452-4f6b-8fb5-776644a6197c"
PROJECT="SCRUM"

# ── helpers ───────────────────────────────────────────────────────────────────

create_test_issue() {
    local label="${1:-}"
    local json key
    json=$(acli jira workitem create \
        --summary "[test] planner-loop-integration $(date +%s%N)" \
        --project "$PROJECT" --type "Task" --json 2>&1)
    key=$(printf '%s' "$json" | jq -r '.key // empty')
    [[ -z "$key" ]] && { echo "create failed: $json" >&3; return 1; }
    if [[ -n "$label" ]]; then
        acli jira workitem edit --key "$key" --labels "$label" --yes >/dev/null 2>&1 || true
        sleep 3  # allow label to propagate in Jira's JQL index
    fi
    echo "$key" >> "$PLANNER_CLEANUP_FILE"
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
    git clone "file://$BARE_REPO" "$tmp/clone" -q 2>/dev/null
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

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE

    if ! acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
        printf '%s' "$JIRA_TOKEN" \
            | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token 2>&1
    fi

    PLANNER_CLEANUP_FILE=$(mktemp)
    export PLANNER_CLEANUP_FILE
}

teardown_file() {
    if [[ -f "${PLANNER_CLEANUP_FILE:-}" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete "$key" --force 2>/dev/null || true
            echo "# Deleted test issue: $key" >&3
        done < "$PLANNER_CLEANUP_FILE"
        rm -f "$PLANNER_CLEANUP_FILE"
    fi
}

# ── per-test setup ─────────────────────────────────────────────────────────────

setup() {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env file found"; fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE
    export JIRA_EMAIL
    export JIRA_TOKEN
    export JIRA_ASSIGNEE_ACCOUNT_ID="$ACCOUNT_ID"

    unset PLAN_BY_DEFAULT

    CLEANUP_BASELINE=$(wc -l < "$PLANNER_CLEANUP_FILE" 2>/dev/null || echo 0)
    export CLEANUP_BASELINE

    # Local bare repository — avoids needing real remote Git credentials.
    BARE_REPO=$(mktemp -d)
    git init --bare "$BARE_REPO" -q
    # Seed with an initial commit so clones get a default branch and push works.
    local seed_dir
    seed_dir=$(mktemp -d)
    (
        git -C "$seed_dir" init -q
        GIT_AUTHOR_NAME="seed" GIT_AUTHOR_EMAIL="s@s.s" \
        GIT_COMMITTER_NAME="seed" GIT_COMMITTER_EMAIL="s@s.s" \
            git -C "$seed_dir" commit --allow-empty -m "init" -q
        git -C "$seed_dir" remote add origin "file://$BARE_REPO"
        git -C "$seed_dir" push -u origin HEAD:main -q
    )
    rm -rf "$seed_dir"
    export BARE_REPO
    export GIT_REPO_URL="file://$BARE_REPO"
    export GIT_USERNAME="testuser"
    export GIT_TOKEN="testtoken"

    # Working directory for planner-loop to clone into
    LOOP_WORK_TMPDIR=$(mktemp -d)
    export LOOP_WORK_DIR="$LOOP_WORK_TMPDIR"

    # Git identity so commits inside the cloned repo succeed without global config
    export GIT_AUTHOR_NAME="planner-loop-test"
    export GIT_AUTHOR_EMAIL="test@test.test"
    export GIT_COMMITTER_NAME="planner-loop-test"
    export GIT_COMMITTER_EMAIL="test@test.test"

    # Stub agent: extract the issue key from the prompt and write a plan file.
    STUB_DIR=$(mktemp -d)
    cat > "$STUB_DIR/agent" <<'EOF'
#!/usr/bin/env bash
KEY=$(printf '%s' "$*" | grep -oE '[A-Z]+-[0-9]+' | head -1)
mkdir -p plans
echo "# Plan for $KEY" > "plans/$KEY.md"
EOF
    chmod +x "$STUB_DIR/agent"
    export PATH="$STUB_DIR:$PATH"
}

teardown() {
    if [[ -f "${PLANNER_CLEANUP_FILE:-}" ]]; then
        tail -n +"$((CLEANUP_BASELINE + 1))" "$PLANNER_CLEANUP_FILE" | while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete --key "$key" -y 2>/dev/null || true
            echo "# [teardown] Deleted $key" >&3
        done
    fi
    rm -rf "${BARE_REPO:-}" "${LOOP_WORK_TMPDIR:-}" "${STUB_DIR:-}"
}

# ── tests ─────────────────────────────────────────────────────────────────────

@test "authentication: acli reports authenticated with provided credentials" {
    run acli jira auth status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Authenticated"* ]]
    [[ "$output" == *"jaksa.atlassian.net"* ]]
}

# ── PLAN_BY_DEFAULT=false ──────────────────────────────────────────────────────

@test "L1: PLAN_BY_DEFAULT=false, needs-plan — claimed, plan committed, transitioned" {
    KEY=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 120 "$PLANNER_LOOP" --project "$PROJECT" --agent agent
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    plan_in_repo "$KEY"
    local s
    s=$(issue_status "$KEY")
    [[ "$s" == "Awaiting Plan Review" || "$s" == "Planning" ]]
}

@test "L2: PLAN_BY_DEFAULT=false, no label — issue NOT claimed" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run timeout 20 "$PLANNER_LOOP" --project "$PROJECT" --agent agent
    [[ "$(issue_assignee "$KEY")" != "$ACCOUNT_ID" ]]
}

@test "L3: PLAN_BY_DEFAULT=false, skip-plan label — issue NOT claimed" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 20 "$PLANNER_LOOP" --project "$PROJECT" --agent agent
    [[ "$(issue_assignee "$KEY")" != "$ACCOUNT_ID" ]]
}

# ── PLAN_BY_DEFAULT=true ───────────────────────────────────────────────────────

@test "L4: PLAN_BY_DEFAULT=true, no label — claimed, plan committed, transitioned" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run timeout 120 "$PLANNER_LOOP" --project "$PROJECT" --agent agent
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    plan_in_repo "$KEY"
    local s
    s=$(issue_status "$KEY")
    [[ "$s" == "Awaiting Plan Review" || "$s" == "Planning" ]]
}

@test "L5: PLAN_BY_DEFAULT=true, skip-plan label — issue NOT claimed" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run timeout 20 "$PLANNER_LOOP" --project "$PROJECT" --agent agent
    [[ "$(issue_assignee "$KEY")" != "$ACCOUNT_ID" ]]
}
