#!/usr/bin/env bats
# Integration tests for claim/claim — uses the real Jira API.
#
# Prerequisites:
#   - .env exists at the repo root with JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN
#   - acli is authenticated (tests will authenticate if needed)
#   - JIRA_SITE may include https:// prefix; tests strip it automatically
#
# These tests create and delete real Jira issues in the SCRUM project.

CLAIM="$BATS_TEST_DIRNAME/claim"
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

    # Load credentials
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    # acli expects just the hostname, not https://hostname/
    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE

    # Authenticate if needed
    if ! acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
        printf '%s' "$JIRA_TOKEN" \
            | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token 2>&1
    fi

    # Create an unassigned test issue that claim can pick up
    local json
    json=$(acli jira workitem create \
        --summary "[test] claim integration test - $(date +%s)" \
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

    # Stub sleep to avoid waiting during tests
    STUB_DIR="$(mktemp -d)"
    printf '#!/usr/bin/env bash\n' > "$STUB_DIR/sleep"
    chmod +x "$STUB_DIR/sleep"
    export PATH="$STUB_DIR:$PATH"
}

teardown() {
    rm -rf "${STUB_DIR:-}"
}

# ── tests ─────────────────────────────────────────────────────────────────────

@test "authentication: acli reports authenticated with provided credentials" {
    run acli jira auth status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Authenticated"* ]]
    [[ "$output" == *"jaksa.atlassian.net"* ]]
}

@test "claim: exits 0 and prints claimed issue key" {
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    echo "# output: $output" >&3
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed"* ]]
}

@test "claim: output contains valid JSON with expected fields" {
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]

    # Extract the JSON block (from first { to matching })
    local json
    json=$(printf '%s\n' "$output" | awk '/^\{/,/^\}/')
    echo "# json: $json" >&3

    [[ -n "$json" ]]
    printf '%s' "$json" | jq -e '.key'        >/dev/null
    printf '%s' "$json" | jq -e '.summary'    >/dev/null
    printf '%s' "$json" | jq -e '.status'     >/dev/null
}

@test "claim: issue is actually assigned in Jira after claim" {
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]

    # Parse the claimed key from the JSON block
    local claimed_key
    claimed_key=$(printf '%s\n' "$output" | awk '/^\{/,/^\}/' | jq -r '.key // empty')
    echo "# claimed key: $claimed_key" >&3
    [[ -n "$claimed_key" ]]

    # Verify directly in Jira
    local assignee
    assignee=$(acli jira workitem view "$claimed_key" --json 2>/dev/null \
        | jq -r '.fields.assignee.accountId // empty')
    echo "# assignee: $assignee" >&3
    [[ "$assignee" == "$ACCOUNT_ID" ]]
}

@test "claim: issue is transitioned to In Progress after claim" {
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]

    local claimed_key
    claimed_key=$(printf '%s\n' "$output" | awk '/^\{/,/^\}/' | jq -r '.key // empty')
    echo "# claimed key: $claimed_key" >&3
    [[ -n "$claimed_key" ]]

    local status_name
    status_name=$(acli jira workitem view "$claimed_key" --json 2>/dev/null \
        | jq -r '.fields.status.name // empty')
    echo "# status: $status_name" >&3
    [[ "$status_name" == "In Progress" ]]
}

@test "claim: no unassigned issues — exits once an issue becomes available" {
    # Unassign the test issue so we know there's exactly one available,
    # then re-run claim against that specific project
    acli jira workitem assign --key "$TEST_ISSUE_KEY" --remove-assignee --yes 2>/dev/null || true

    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully claimed"* ]]
}
