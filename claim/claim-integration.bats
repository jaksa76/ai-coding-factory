#!/usr/bin/env bats
# Integration tests for claim/claim — uses the real Jira API.
#
# Prerequisites:
#   - .env exists at the repo root with JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN
#   - acli is authenticated (tests will authenticate if needed)
#   - JIRA_SITE may include https:// prefix; tests strip it automatically
#
# These tests create and delete real Jira issues in the SCRUM project.
# They assume the SCRUM project has no other matching unassigned issues between runs.

CLAIM="$BATS_TEST_DIRNAME/claim"
ENV_FILE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env"

# Account ID for jaksa76@gmail.com on jaksa.atlassian.net
ACCOUNT_ID="712020:2b77122e-3452-4f6b-8fb5-776644a6197c"
PROJECT=${JIRA_PROJECT:-"ACFTEST"}

# ── helpers ───────────────────────────────────────────────────────────────────

create_test_issue() {
    local label="${1:-}"
    local json key
    json=$(acli jira workitem create \
        --summary "[test] claim-integration $(date +%s%N)" \
        --project "$PROJECT" --type "Task" --json 2>&1)
    key=$(printf '%s' "$json" | jq -r '.key // empty')
    [[ -z "$key" ]] && { echo "create failed: $json" >&3; return 1; }
    if [[ -n "$label" ]]; then
        acli jira workitem edit --key "$key" --labels "$label" --yes >/dev/null 2>&1 || true
        sleep 3  # allow label to propagate in Jira's JQL index
    fi
    echo "$key" >> "$CLAIM_CLEANUP_FILE"
    echo "$key"
}

issue_assignee() {   # returns accountId or empty
    acli jira workitem view "$1" --json 2>/dev/null \
        | jq -r '.fields.assignee.accountId // empty'
}

issue_status() {     # returns status name
    acli jira workitem view "$1" --json 2>/dev/null \
        | jq -r '.fields.status.name // empty'
}

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

    # Temp file to collect all created issue keys for cleanup
    CLAIM_CLEANUP_FILE=$(mktemp)
    export CLAIM_CLEANUP_FILE
}

teardown_file() {
    if [[ -f "${CLAIM_CLEANUP_FILE:-}" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete "$key" --force 2>/dev/null || true
            echo "# Deleted test issue: $key" >&3
        done < "$CLAIM_CLEANUP_FILE"
        rm -f "$CLAIM_CLEANUP_FILE"
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

    unset PLAN_BY_DEFAULT

    # Record how many issues have been registered so far so teardown can clean
    # up only the issues created by this test, preventing cross-test interference.
    CLEANUP_BASELINE=$(wc -l < "$CLAIM_CLEANUP_FILE" 2>/dev/null || echo 0)
    export CLEANUP_BASELINE
}

teardown() {
    if [[ -f "${CLAIM_CLEANUP_FILE:-}" ]]; then
        tail -n +"$((CLEANUP_BASELINE + 1))" "$CLAIM_CLEANUP_FILE" | while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            acli jira workitem delete --key "$key" -y 2>/dev/null || true
            echo "# [teardown] Deleted $key" >&3
        done
    fi
}

# ── tests ─────────────────────────────────────────────────────────────────────

@test "authentication: acli reports authenticated with provided credentials" {
    run acli jira auth status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Authenticated"* ]]
    [[ "$output" == *"jaksa.atlassian.net"* ]]
}

# ── Planning mode (--for-planning) ────────────────────────────────────────────

@test "P1: --for-planning, PLAN_BY_DEFAULT=false, no label — issue NOT claimed" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run timeout 15 "$CLAIM" --for-planning --project "$PROJECT" --account-id "$ACCOUNT_ID"
    assignee=$(issue_assignee "$KEY")
    [[ "$assignee" != "$ACCOUNT_ID" ]]
}

@test "P2: --for-planning, PLAN_BY_DEFAULT=false, needs-plan label — claimed + Planning" {
    KEY=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run "$CLAIM" --for-planning --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    [[ "$(issue_status "$KEY")" == "Planning" ]]
}

@test "P3: --for-planning, PLAN_BY_DEFAULT=false, skip-plan label — issue NOT claimed" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 15 "$CLAIM" --for-planning --project "$PROJECT" --account-id "$ACCOUNT_ID"
    assignee=$(issue_assignee "$KEY")
    [[ "$assignee" != "$ACCOUNT_ID" ]]
}

@test "P4: --for-planning, PLAN_BY_DEFAULT=true, no label — claimed + Planning" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run "$CLAIM" --for-planning --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    [[ "$(issue_status "$KEY")" == "Planning" ]]
}

@test "P5: --for-planning, PLAN_BY_DEFAULT=true, skip-plan label — issue NOT claimed" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run timeout 15 "$CLAIM" --for-planning --project "$PROJECT" --account-id "$ACCOUNT_ID"
    assignee=$(issue_assignee "$KEY")
    [[ "$assignee" != "$ACCOUNT_ID" ]]
}

# ── Implementation mode (no --for-planning) ───────────────────────────────────

@test "I1: no --for-planning, PLAN_BY_DEFAULT=false, no label — claimed + In Progress" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    [[ "$(issue_status "$KEY")" == "In Progress" ]]
}

@test "I2: no --for-planning, PLAN_BY_DEFAULT=false, needs-plan label — issue NOT claimed" {
    KEY=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 15 "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    assignee=$(issue_assignee "$KEY")
    [[ "$assignee" != "$ACCOUNT_ID" ]]
}

@test "I3: no --for-planning, PLAN_BY_DEFAULT=false, skip-plan label — claimed + In Progress" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    [[ "$(issue_status "$KEY")" == "In Progress" ]]
}

@test "I4: no --for-planning, PLAN_BY_DEFAULT=true, no label — issue NOT claimed" {
    KEY=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run timeout 15 "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    assignee=$(issue_assignee "$KEY")
    [[ "$assignee" != "$ACCOUNT_ID" ]]
}

@test "I5: no --for-planning, PLAN_BY_DEFAULT=true, skip-plan label — claimed + In Progress" {
    KEY=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
    [[ "$(issue_status "$KEY")" == "In Progress" ]]
}

@test "I6: no --for-planning, PLAN_BY_DEFAULT=true, Plan Approved status — claimed + In Progress" {
    KEY=$(create_test_issue)
    # Skip if Plan Approved transition is not in this workflow
    transitions=$(acli jira workitem transitions --key "$KEY" --json 2>/dev/null || echo "[]")
    if ! printf '%s' "$transitions" | jq -e '[.[].name] | map(select(. == "Plan Approved")) | length > 0' >/dev/null 2>&1; then
        skip "Plan Approved status not available in workflow"
    fi
    acli jira workitem transition --key "$KEY" --status "Plan Approved" --yes
    export PLAN_BY_DEFAULT=true
    run "$CLAIM" --project "$PROJECT" --account-id "$ACCOUNT_ID"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$KEY")" == "$ACCOUNT_ID" ]]
}
