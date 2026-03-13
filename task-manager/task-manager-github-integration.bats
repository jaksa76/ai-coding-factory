#!/usr/bin/env bats
# Integration tests for task-manager — uses the real GitHub API.
#
# Prerequisites:
#   - .env.test exists at the repo root with GH_TOKEN, GH_USERNAME, GITHUB_REPO
#   - GITHUB_REPO is in owner/repo format, e.g. jaksa76/dummy-project (also used by loop)
#   - The repo must have labels: needs-plan, skip-plan, in-progress, in-planning
#
# These tests create and delete real GitHub issues in the configured repo.
# They assume the repo has no other matching unassigned open issues between runs.

TASK_MANAGER="$BATS_TEST_DIRNAME/task-manager"
ENV_FILE="${ENV_FILE:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env.test}"

# ── helpers ───────────────────────────────────────────────────────────────────

create_test_issue() {
    local label="${1:-}"
    local url number
    url=$(gh issue create \
        --repo "$REPO" \
        --title "[test] task-manager-github-integration $(date +%s%N)" \
        --body "Automated test issue" 2>&1)
    number="${url##*/}"
    [[ -z "$number" || ! "$number" =~ ^[0-9]+$ ]] && { echo "create failed: $url" >&3; return 1; }
    if [[ -n "$label" ]]; then
        gh issue edit "$number" --repo "$REPO" --add-label "$label" >/dev/null 2>&1 || true
        sleep 3
    fi
    echo "$number" >> "$GH_CLEANUP_FILE"
    echo "$number"
}

issue_assignee() {
    gh issue view "$1" --repo "$REPO" --json assignees 2>/dev/null \
        | jq -r '.assignees[0].login // empty'
}

issue_has_label() {
    gh issue view "$1" --repo "$REPO" --json labels 2>/dev/null \
        | jq -r --arg l "$2" '[.labels[].name] | index($l) != null'
}

# ── file-level setup / teardown ───────────────────────────────────────────────

setup_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "SKIP: $ENV_FILE not found" >&3
        skip "No env file found"
    fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    export GH_TOKEN
    REPO="${GITHUB_REPO}"
    export REPO

    if ! gh auth status &>/dev/null; then
        echo "$GH_TOKEN" | gh auth login --with-token 2>&1
    fi

    for label in needs-plan skip-plan in-progress in-planning; do
        gh label create "$label" --repo "$REPO" --color "#0075ca" 2>/dev/null || true
    done

    GH_CLEANUP_FILE=$(mktemp)
    export GH_CLEANUP_FILE
}

teardown_file() {
    if [[ -f "${GH_CLEANUP_FILE:-}" ]]; then
        while IFS= read -r number; do
            [[ -z "$number" ]] && continue
            gh issue delete "$number" --repo "$REPO" --yes 2>/dev/null || true
            echo "# Deleted test issue: #$number" >&3
        done < "$GH_CLEANUP_FILE"
        rm -f "$GH_CLEANUP_FILE"
    fi
}

# ── per-test setup ─────────────────────────────────────────────────────────────

setup() {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No env file found"; fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    export GH_TOKEN
    REPO="${GITHUB_REPO}"
    export REPO
    ASSIGNEE="${GH_USERNAME}"
    export ASSIGNEE

    unset PLAN_BY_DEFAULT

    CLEANUP_BASELINE=$(wc -l < "$GH_CLEANUP_FILE" 2>/dev/null || echo 0)
    export CLEANUP_BASELINE
}

teardown() {
    if [[ -f "${GH_CLEANUP_FILE:-}" ]]; then
        tail -n +"$((CLEANUP_BASELINE + 1))" "$GH_CLEANUP_FILE" | while IFS= read -r number; do
            [[ -z "$number" ]] && continue
            gh issue delete "$number" --repo "$REPO" --yes 2>/dev/null || true
            echo "# [teardown] Deleted #$number" >&3
        done
    fi
}

# ── auth ──────────────────────────────────────────────────────────────────────

@test "auth: gh reports authenticated with provided credentials" {
    run env TASK_MANAGER=github "$TASK_MANAGER" auth
    [ "$status" -eq 0 ]
}

# ── Planning mode (--for-planning) ────────────────────────────────────────────

@test "P1: --for-planning, PLAN_BY_DEFAULT=false, no label — issue NOT claimed" {
    NUMBER=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run timeout 15 env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --for-planning --project "$REPO" --account-id "$ASSIGNEE"
    assignee=$(issue_assignee "$NUMBER")
    [[ "$assignee" != "$ASSIGNEE" ]]
}

@test "P2: --for-planning, PLAN_BY_DEFAULT=false, needs-plan label — claimed + in-planning" {
    NUMBER=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --for-planning --project "$REPO" --account-id "$ASSIGNEE"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$NUMBER")" == "$ASSIGNEE" ]]
    [[ "$(issue_has_label "$NUMBER" "in-planning")" == "true" ]]
}

@test "P3: --for-planning, PLAN_BY_DEFAULT=false, skip-plan label — issue NOT claimed" {
    NUMBER=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 15 env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --for-planning --project "$REPO" --account-id "$ASSIGNEE"
    assignee=$(issue_assignee "$NUMBER")
    [[ "$assignee" != "$ASSIGNEE" ]]
}

@test "P4: --for-planning, PLAN_BY_DEFAULT=true, no label — claimed + in-planning" {
    NUMBER=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --for-planning --project "$REPO" --account-id "$ASSIGNEE"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$NUMBER")" == "$ASSIGNEE" ]]
    [[ "$(issue_has_label "$NUMBER" "in-planning")" == "true" ]]
}

@test "P5: --for-planning, PLAN_BY_DEFAULT=true, skip-plan label — issue NOT claimed" {
    NUMBER=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run timeout 15 env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --for-planning --project "$REPO" --account-id "$ASSIGNEE"
    assignee=$(issue_assignee "$NUMBER")
    [[ "$assignee" != "$ASSIGNEE" ]]
}

# ── Implementation mode (no --for-planning) ───────────────────────────────────

@test "I1: no --for-planning, PLAN_BY_DEFAULT=false, no label — claimed + in-progress" {
    NUMBER=$(create_test_issue)
    export PLAN_BY_DEFAULT=false
    run env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --project "$REPO" --account-id "$ASSIGNEE"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$NUMBER")" == "$ASSIGNEE" ]]
    [[ "$(issue_has_label "$NUMBER" "in-progress")" == "true" ]]
}

@test "I2: no --for-planning, PLAN_BY_DEFAULT=false, needs-plan label — issue NOT claimed" {
    NUMBER=$(create_test_issue "needs-plan")
    export PLAN_BY_DEFAULT=false
    run timeout 15 env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --project "$REPO" --account-id "$ASSIGNEE"
    assignee=$(issue_assignee "$NUMBER")
    [[ "$assignee" != "$ASSIGNEE" ]]
}

@test "I3: no --for-planning, PLAN_BY_DEFAULT=false, skip-plan label — claimed + in-progress" {
    NUMBER=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=false
    run env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --project "$REPO" --account-id "$ASSIGNEE"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$NUMBER")" == "$ASSIGNEE" ]]
    [[ "$(issue_has_label "$NUMBER" "in-progress")" == "true" ]]
}

@test "I4: no --for-planning, PLAN_BY_DEFAULT=true, no label — issue NOT claimed" {
    NUMBER=$(create_test_issue)
    export PLAN_BY_DEFAULT=true
    run timeout 15 env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --project "$REPO" --account-id "$ASSIGNEE"
    assignee=$(issue_assignee "$NUMBER")
    [[ "$assignee" != "$ASSIGNEE" ]]
}

@test "I5: no --for-planning, PLAN_BY_DEFAULT=true, skip-plan label — claimed + in-progress" {
    NUMBER=$(create_test_issue "skip-plan")
    export PLAN_BY_DEFAULT=true
    run env TASK_MANAGER=github GH_TOKEN="$GH_TOKEN" "$TASK_MANAGER" claim --project "$REPO" --account-id "$ASSIGNEE"
    [ "$status" -eq 0 ]
    [[ "$(issue_assignee "$NUMBER")" == "$ASSIGNEE" ]]
    [[ "$(issue_has_label "$NUMBER" "in-progress")" == "true" ]]
}
