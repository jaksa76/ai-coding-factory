#!/usr/bin/env bats
# Integration tests for loop/loop — uses real Jira API and a local git repository.
#
# Prerequisites:
#   - .env exists at the repo root with JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN,
#     GIT_REPO_URL, GIT_USERNAME, GIT_TOKEN
#   - acli is authenticated
#
# Creates and deletes a real Jira issue in the SCRUM project.

LOOP="$BATS_TEST_DIRNAME/loop"
REAL_CLAIM="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/claim/claim"
ENV_FILE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env"

# Account ID for jaksa76@gmail.com on jaksa.atlassian.net
ACCOUNT_ID="712020:2b77122e-3452-4f6b-8fb5-776644a6197c"
PROJECT="SCRUM"

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

    # Authenticate if needed
    if ! acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
        printf '%s' "$JIRA_TOKEN" \
            | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token 2>&1
    fi

    # Create an unassigned test issue that loop can pick up
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
}

teardown_file() {
    if [[ -n "${TEST_ISSUE_KEY:-}" ]]; then
        acli jira workitem delete "$TEST_ISSUE_KEY" --force 2>/dev/null || true
        echo "# Deleted test issue: $TEST_ISSUE_KEY" >&3
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

    # Create a local bare git repository so loop can clone and push without
    # hitting the real remote repository
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

    # Stub dir: sleep stub + claim wrapper that calls real claim on the first
    # invocation and exits 1 on the second to terminate the infinite loop
    STUB_DIR="$(mktemp -d)"
    printf '#!/usr/bin/env bash\n' > "$STUB_DIR/sleep"
    chmod +x "$STUB_DIR/sleep"

    CLAIM_COUNTER="$(mktemp)"
    echo "0" > "$CLAIM_COUNTER"
    cat > "$STUB_DIR/claim" << STUB_EOF
#!/usr/bin/env bash
count=\$(cat '$CLAIM_COUNTER')
echo \$((count + 1)) > '$CLAIM_COUNTER'
if [ "\$count" -eq 0 ]; then
    exec '$REAL_CLAIM' "\$@"
else
    exit 1
fi
STUB_EOF
    chmod +x "$STUB_DIR/claim"

    # Git identity for mock-agent commits (overrides global config in the test env)
    export GIT_AUTHOR_NAME="Test Agent"
    export GIT_AUTHOR_EMAIL="agent@test.example.com"
    export GIT_COMMITTER_NAME="Test Agent"
    export GIT_COMMITTER_EMAIL="agent@test.example.com"

    # PATH: stubs first, then loop dir (contains mock-agent), then original PATH
    export PATH="$STUB_DIR:$BATS_TEST_DIRNAME:$PATH"
}

teardown() {
    rm -rf "${STUB_DIR:-}" "${LOOP_TMPDIR:-}" "${REPO_TMPDIR:-}"
    rm -f "${CLAIM_COUNTER:-}"
}

# ── tests ─────────────────────────────────────────────────────────────────────

@test "loop: processes real Jira issue, transitions to Done, and pushes work-log.md" {
    # Ensure the test issue is unassigned so there is at least one issue to claim
    acli jira workitem transition --key "$TEST_ISSUE_KEY" --status "To Do" --yes 2>/dev/null || true
    acli jira workitem assign --key "$TEST_ISSUE_KEY" --remove-assignee --yes 2>/dev/null || true

    run "$LOOP" --project "$PROJECT" --agent mock-agent

    echo "# output: $output" >&3
    # Loop exits with status 1 when claim returns 1 on the second iteration
    [ "$status" -eq 1 ]

    # Extract which issue was actually processed (claim picks oldest unassigned first,
    # which may differ from the test issue created in setup_file)
    local processed_key
    processed_key=$(printf '%s\n' "$output" | grep -o 'Completed [A-Z]*-[0-9]*' | awk '{print $2}')
    echo "# processed issue: $processed_key" >&3
    [[ -n "$processed_key" ]]

    # Jira issue is now in Done status
    local issue_status
    issue_status=$(acli jira workitem view "$processed_key" --json 2>/dev/null \
        | jq -r '.fields.status.name // empty')
    echo "# issue status after loop: $issue_status" >&3
    [[ "$issue_status" == "Done" ]]

    # mock-agent's work-log.md was committed and pushed to the repository
    local check_clone="$REPO_TMPDIR/verify"
    git clone "$BARE_REPO" "$check_clone" >/dev/null 2>&1
    [ -f "$check_clone/work-log.md" ]
    [[ "$(cat "$check_clone/work-log.md")" == *"$processed_key"* ]]
}
