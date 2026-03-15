#!/usr/bin/env bats
# Loop integration tests with real APIs, real agent calls, and real git pushes.

LOOP="$BATS_TEST_DIRNAME/loop"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.test"
BIN_DIR="$REPO_ROOT/bin"
ORIGINAL_PATH="$PATH"

github_repo_from_git_url() {
    local url="$1"
    url="${url#https://github.com/}"
    url="${url#git@github.com:}"
    url="${url%.git}"
    printf '%s\n' "$url"
}

setup_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        skip "No env file found ($ENV_FILE)"
    fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE
    export TEST_JIRA_PROJECT="$PROJECT"
    export TEST_GITHUB_REPO="$(github_repo_from_git_url "$GIT_REPO_URL")"

    if ! command -v acli >/dev/null 2>&1; then
        fail "acli not found"
    fi
    if ! command -v gh >/dev/null 2>&1; then
        fail "gh not found"
    fi
    if ! command -v claude >/dev/null 2>&1; then
        fail "claude not found"
    fi
    if ! command -v copilot >/dev/null 2>&1; then
        fail "copilot not found"
    fi

    if ! acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
        printf '%s' "$JIRA_TOKEN" \
            | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token >/dev/null
    fi
    if ! gh auth status >/dev/null 2>&1; then
        fail "gh auth not ready"
    fi
    if [[ -z "$TEST_JIRA_PROJECT" ]]; then
        fail "PROJECT is required in $ENV_FILE for Jira tests"
    fi
    if [[ -z "$TEST_GITHUB_REPO" ]]; then
        fail "GIT_REPO_URL must point at a GitHub repository for GitHub tests"
    fi
    if [[ -z "${GH_ASSIGNEE:-}" ]]; then
        fail "GH_ASSIGNEE is required in $ENV_FILE"
    fi

    for label in needs-plan skip-plan plan-approved in-progress in-planning in-review awaiting-plan-review; do
        gh label create "$label" --repo "$TEST_GITHUB_REPO" --color "0075ca" --force >/dev/null 2>&1 || true
    done

    CLEANUP_FILE="$(mktemp)"
    export CLEANUP_FILE
}

teardown_file() {
    if [[ -f "${CLEANUP_FILE:-}" ]]; then
        while IFS='|' read -r tracker key branch; do
            [[ -z "$tracker" || -z "$key" ]] && continue
            case "$tracker" in
                jira)
                    acli jira workitem delete "$key" --force >/dev/null 2>&1 || true
                    ;;
                github)
                    gh issue close "$key" --repo "$TEST_GITHUB_REPO" >/dev/null 2>&1 || true
                    ;;
            esac
            if [[ -n "$branch" && -n "${GIT_REPO_URL:-}" ]]; then
                git push "$GIT_REPO_URL" --delete "$branch" >/dev/null 2>&1 || true
            fi
        done < "$CLEANUP_FILE"
        rm -f "$CLEANUP_FILE"
    fi
}

setup() {
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    JIRA_SITE="${JIRA_SITE#https://}"
    JIRA_SITE="${JIRA_SITE%/}"
    export JIRA_SITE

    unset TASK_MANAGER FEATURE_BRANCHES PLAN_BY_DEFAULT GITHUB_REPO
    export NO_ISSUES_WAIT=3600
    export INTER_ISSUE_WAIT=3600
    export PATH="$BIN_DIR:$ORIGINAL_PATH"

    LOOP_WORK_DIR="$(mktemp -d)"
    export LOOP_WORK_DIR
}

teardown() {
    rm -rf "${AGENT_ADAPTER_DIR:-}"
    rm -rf "${LOOP_WORK_DIR:-}"
}

use_claude_agent_adapter() {
    AGENT_ADAPTER_DIR="$(mktemp -d)"
    cat > "$AGENT_ADAPTER_DIR/agent" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
case "$cmd" in
    init)
        exit 0
        ;;
    run)
        prompt="${2:-}"
        unset CLAUDECODE
        exec claude --dangerously-skip-permissions --model claude-haiku-4-5-20251001 -p "$prompt"
        ;;
    *)
        echo "Usage: agent <init|run>" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$AGENT_ADAPTER_DIR/agent"
    export PATH="$AGENT_ADAPTER_DIR:$BIN_DIR:$ORIGINAL_PATH"
}

use_copilot_agent_adapter() {
    if timeout 5 copilot --allow-all --no-ask-user -p "" </dev/null 2>&1 | grep -q "Cannot find"; then
        fail "Copilot not installed"
    fi

    AGENT_ADAPTER_DIR="$(mktemp -d)"
    cat > "$AGENT_ADAPTER_DIR/agent" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
case "$cmd" in
    init)
        exit 0
        ;;
    run)
        prompt="${2:-}"
        exec copilot --allow-all --no-ask-user --model gpt-5-mini -p "$prompt"
        ;;
    *)
        echo "Usage: agent <init|run>" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$AGENT_ADAPTER_DIR/agent"
    export PATH="$AGENT_ADAPTER_DIR:$BIN_DIR:$ORIGINAL_PATH"
}

create_jira_issue() {
    local label="${1:-}"
    local summary="[itest][loop][jira] $(date +%s%N)"
    local json key
    json=$(acli jira workitem create --summary "$summary" --project "$TEST_JIRA_PROJECT" --type "Task" --description "Write a new file containing a short joke. Pick a unique filename." --json 2>&1)
    key=$(printf '%s' "$json" | jq -r '.key // empty')
    [[ -z "$key" ]] && { echo "create failed: $json" >&3; return 1; }

    if [[ -n "$label" ]]; then
        acli jira workitem edit --key "$key" --labels "$label" --yes >/dev/null 2>&1 || true
        sleep 8
    fi

    echo "jira|$key|" >> "$CLEANUP_FILE"
    echo "$key"
}

jira_issue_status() {
    acli jira workitem view "$1" --json 2>/dev/null | jq -r '.fields.status.name // empty'
}

create_gh_issue() {
    local label="${1:-}"
    local title="[itest][loop][github] $(date +%s%N)"
    local url number
    url=$(gh issue create --repo "$TEST_GITHUB_REPO" --title "$title" --body "Write a new file containing a short joke. Pick a unique filename.")
    number=$(basename "$url")
    [[ -z "$number" || ! "$number" =~ ^[0-9]+$ ]] && return 1

    if [[ -n "$label" ]]; then
        gh issue edit "$number" --repo "$TEST_GITHUB_REPO" --add-label "$label" >/dev/null 2>&1 || true
    fi

    echo "github|$number|" >> "$CLEANUP_FILE"
    echo "$number"
}

gh_issue_state() {
    gh issue view "$1" --repo "$TEST_GITHUB_REPO" --json state | jq -r '.state | ascii_downcase'
}

gh_issue_labels() {
    gh issue view "$1" --repo "$TEST_GITHUB_REPO" --json labels | jq -r '[.labels[].name] | join(",")'
}

plan_exists_in_repo() {
    local key="$1"
    local tmp
    tmp=$(mktemp -d)
    git clone "$GIT_REPO_URL" "$tmp/repo" -q >/dev/null 2>&1 || return 1
    [[ -f "$tmp/repo/plans/$key.md" ]]
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
}

@test "planning loop with gh task management using copilot (default planning)" {
    use_copilot_agent_adapter
    export TASK_MANAGER=github
    export GITHUB_REPO="$TEST_GITHUB_REPO"

    local number
    number=$(create_gh_issue)

    export PLAN_BY_DEFAULT=true
    local start=$SECONDS
    run timeout 300 "$LOOP" --project "$TEST_GITHUB_REPO" --for-planning --max-tasks 1
    echo "# elapsed: $((SECONDS - start))s" >&3

    echo "# output: $output" >&3
    [[ "$output" == *"Planning phase complete for $number"* ]]
    plan_exists_in_repo "$number"

    local labels
    labels=$(gh_issue_labels "$number")
    [[ "$labels" == *"awaiting-plan-review"* || "$labels" == *"in-planning"* ]]
}

@test "implementation loop with gh task management using claude (no feature branches)" {
    use_claude_agent_adapter
    export TASK_MANAGER=github
    export GITHUB_REPO="$TEST_GITHUB_REPO"

    local number
    number=$(create_gh_issue)

    export FEATURE_BRANCHES=false
    local start=$SECONDS
    run timeout 300 "$LOOP" --project "$TEST_GITHUB_REPO" --max-tasks 1
    echo "# elapsed: $((SECONDS - start))s" >&3

    echo "# output: $output" >&3
    [[ "$output" == *"Completed $number"* ]]
    [[ "$(gh_issue_state "$number")" == "closed" ]]
}

@test "planning loop with jira task management using claude (needs-plan label)" {
    use_claude_agent_adapter
    export TASK_MANAGER=jira

    local key
    key=$(create_jira_issue "needs-plan")

    acli jira workitem assign --key "$key" --remove-assignee --yes >/dev/null 2>&1 || true
    export PLAN_BY_DEFAULT=false

    local start=$SECONDS
    run timeout 300 "$LOOP" --project "$TEST_JIRA_PROJECT" --for-planning --max-tasks 1
    echo "# elapsed: $((SECONDS - start))s" >&3

    echo "# output: $output" >&3
    [[ "$output" == *"Planning phase complete for $key"* ]]
    plan_exists_in_repo "$key"

    local s
    s=$(jira_issue_status "$key")
    [[ "$s" == "Awaiting Plan Review" || "$s" == "Planning" ]]
}

@test "implementation loop with jira task management using copilot (feature branches)" {
    use_copilot_agent_adapter
    export TASK_MANAGER=jira

    local key
    key=$(create_jira_issue)
    echo "jira|$key|feature/$key" >> "$CLEANUP_FILE"

    acli jira workitem assign --key "$key" --remove-assignee --yes >/dev/null 2>&1 || true
    export FEATURE_BRANCHES=true

    local start=$SECONDS
    run timeout 300 "$LOOP" --project "$TEST_JIRA_PROJECT" --max-tasks 1
    echo "# elapsed: $((SECONDS - start))s" >&3

    echo "# output: $output" >&3
    [[ "$output" == *"Completed $key"* ]]

    local ref
    ref=$(git ls-remote "$GIT_REPO_URL" "refs/heads/feature/$key" | awk '{print $1}')
    [[ -n "$ref" ]]

    local s
    s=$(jira_issue_status "$key")
    [[ "$s" == "In Review" || "$s" == "Done" || "$s" == "In Progress" ]]
}
