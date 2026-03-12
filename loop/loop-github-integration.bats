#!/usr/bin/env bats
# Integration tests for loop/loop — GitHub backend
# Uses the real GitHub API (gh CLI) and a local bare git repository.
#
# Prerequisites:
#   - .env.github at the repo root containing:
#       TASK_MANAGER=github
#       PROJECT=owner/repo
#       GH_TOKEN=...
#       GITHUB_ASSIGNEE=...
#       GIT_USERNAME=...
#       GIT_TOKEN=...
#   - gh CLI in PATH (authenticated via GH_TOKEN)
#
# Creates and closes real GitHub issues on PROJECT.

LOOP="$BATS_TEST_DIRNAME/loop"
REAL_TASK_MANAGER="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/task-manager/task-manager"
ENV_FILE="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/.env.github"

# ── helpers ───────────────────────────────────────────────────────────────────

# Create a test GitHub issue and optionally apply a label.
# Records the number in CLEANUP_FILE for teardown.
create_gh_issue() {
    local label="${1:-}"
    local url number
    url=$(gh issue create \
        --repo "$GITHUB_REPO" \
        --title "[test] loop-github-integration $(date +%s%N)" \
        --body "Test issue for loop integration" 2>/dev/null)
    number=$(basename "$url")
    [[ -z "$number" || ! "$number" =~ ^[0-9]+$ ]] && {
        echo "create failed: $url" >&3
        return 1
    }
    if [[ -n "$label" ]]; then
        gh issue edit "$number" --repo "$GITHUB_REPO" --add-label "$label" 2>/dev/null || true
        sleep 2
    fi
    echo "$number" >> "$CLEANUP_FILE"
    echo "$number"
}

issue_assignee() {
    gh issue view "$1" --repo "$GITHUB_REPO" --json assignees 2>/dev/null \
        | jq -r '.assignees[0].login // ""'
}

issue_labels() {
    gh issue view "$1" --repo "$GITHUB_REPO" --json labels 2>/dev/null \
        | jq -r '[.labels[].name] | join(",")'
}

issue_state() {
    gh issue view "$1" --repo "$GITHUB_REPO" --json state 2>/dev/null \
        | jq -r '.state | ascii_downcase'
}

# Returns 0 if plans/<key>.md exists in the bare repo, 1 otherwise.
plan_in_bare_repo() {
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
        skip "No .env.github file found"
    fi
    if ! command -v gh &>/dev/null; then
        skip "gh CLI not found"
    fi

    REAL_SLEEP="$(command -v sleep)"
    REAL_GH="$(command -v gh)"
    export REAL_SLEEP REAL_GH

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    export GITHUB_REPO="$PROJECT"

    # Ensure required labels exist on the test repo (idempotent via --force)
    for label in needs-plan skip-plan in-progress in-planning in-review awaiting-review; do
        gh label create "$label" --repo "$GITHUB_REPO" --color "0075ca" --force 2>/dev/null || true
    done

    CLEANUP_FILE=$(mktemp)
    export CLEANUP_FILE
}

teardown_file() {
    if [[ -f "${CLEANUP_FILE:-}" ]]; then
        while IFS= read -r number; do
            [[ -z "$number" ]] && continue
            gh issue close "$number" --repo "$GITHUB_REPO" 2>/dev/null || true
            echo "# Closed test issue #$number" >&3
        done < "$CLEANUP_FILE"
        rm -f "$CLEANUP_FILE"
    fi
}

# ── per-test setup / teardown ─────────────────────────────────────────────────

setup() {
    if [[ ! -f "$ENV_FILE" ]]; then skip "No .env.github file found"; fi
    if ! command -v gh &>/dev/null; then skip "gh CLI not found"; fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    export TASK_MANAGER=github
    export GITHUB_REPO="$PROJECT"

    # Local bare repo for git operations (avoids needing a real GitHub remote)
    REPO_TMPDIR="$(mktemp -d)"
    local bare_repo="$REPO_TMPDIR/test-repo.git"
    git init --bare "$bare_repo" >/dev/null 2>&1

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
    export BARE_REPO="$bare_repo"

    LOOP_TMPDIR="$(mktemp -d)"
    export LOOP_WORK_DIR="$LOOP_TMPDIR"

    # Stubs: no-op sleep + task-manager that delegates to real claim once then exits 1
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
    if [ "\$count" -gt 0 ]; then
        exit 1
    fi
    '$REAL_TASK_MANAGER' "\$@"
    rc=\$?
    if [ "\$rc" -eq 0 ]; then
        echo 1 > '$CLAIM_COUNTER'
    fi
    exit "\$rc"
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

    # Agent stub delegates to mock-agent
    cat > "$STUB_DIR/agent" << 'AGENT_EOF'
#!/usr/bin/env bash
exec mock-agent "$@"
AGENT_EOF
    chmod +x "$STUB_DIR/agent"

    # PATH: stubs first, then loop dir (contains mock-agent), then original PATH
    export PATH="$STUB_DIR:$BATS_TEST_DIRNAME:$PATH"

    CLEANUP_BASELINE=$(wc -l < "${CLEANUP_FILE:-/dev/null}" 2>/dev/null || echo 0)
    export CLEANUP_BASELINE
}

teardown() {
    rm -rf "${STUB_DIR:-}" "${LOOP_TMPDIR:-}" "${REPO_TMPDIR:-}" \
           "${PLANNER_BARE_REPO:-}" "${PLANNER_LOOP_TMPDIR:-}" "${PLANNER_STUB_DIR:-}"
    rm -f "${CLAIM_COUNTER:-}"

    if [[ -f "${CLEANUP_FILE:-}" ]]; then
        tail -n +"$((CLEANUP_BASELINE + 1))" "$CLEANUP_FILE" | while IFS= read -r number; do
            [[ -z "$number" ]] && continue
            gh issue close "$number" --repo "$GITHUB_REPO" 2>/dev/null || true
            echo "# [teardown] Closed #$number" >&3
        done
    fi
}

# ── implementation loop tests ─────────────────────────────────────────────────

@test "GH1: loop processes GitHub issue, closes it, and pushes work-log.md" {
    local number
    number=$(create_gh_issue)

    run timeout 120 "$LOOP" --project "$GITHUB_REPO"

    echo "# output: $output" >&3
    # status 124 means timeout — test failure
    [ "$status" -ne 124 ]

    local processed
    processed=$(printf '%s\n' "$output" | grep -oE 'Completed [0-9]+' | awk '{print $2}' | head -1)
    echo "# processed issue: $processed" >&3
    [[ -n "$processed" ]]

    [[ "$(issue_state "$processed")" == "closed" ]]

    local check_clone="$REPO_TMPDIR/verify"
    git clone "$BARE_REPO" "$check_clone" >/dev/null 2>&1
    [ -f "$check_clone/work-log.md" ]
}

@test "GH2: loop with FEATURE_BRANCHES=true pushes feature branch, stubs PR, transitions to in-review" {
    local number
    number=$(create_gh_issue)

    # Stub gh pr create — the local bare repo has no GitHub remote, so we bypass
    # the real pr create while forwarding all issue commands to the real gh.
    cat > "$STUB_DIR/gh" << STUB_EOF
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "create" ]]; then
    echo "https://github.com/test/repo/pull/99"
    exit 0
fi
exec '$REAL_GH' "\$@"
STUB_EOF
    chmod +x "$STUB_DIR/gh"

    export FEATURE_BRANCHES=true
    run timeout 120 "$LOOP" --project "$GITHUB_REPO"

    echo "# output: $output" >&3
    [ "$status" -ne 124 ]

    # Feature branch was pushed to the bare repo
    local branch_ref
    branch_ref=$(git ls-remote "$BARE_REPO" "refs/heads/feature/$number" 2>/dev/null | awk '{print $1}')
    echo "# feature branch ref: $branch_ref" >&3
    [[ -n "$branch_ref" ]]

    # Issue transitioned to in-review
    local labels
    labels=$(issue_labels "$number")
    echo "# labels: $labels" >&3
    [[ "$labels" == *"in-review"* ]]
}

# ── planning mode integration tests ──────────────────────────────────────────

_setup_planning_integration() {
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

    # Agent stub: extract issue number from prompt (appears as [<number>]) and write plan
    PLANNER_STUB_DIR=$(mktemp -d)
    cat > "$PLANNER_STUB_DIR/agent" << 'EOF'
#!/usr/bin/env bash
KEY=$(printf '%s' "$*" | grep -oE '\[[0-9]+\]' | head -1 | tr -d '[]')
mkdir -p plans
echo "# Plan for $KEY" > "plans/$KEY.md"
EOF
    chmod +x "$PLANNER_STUB_DIR/agent"

    # Prepend planner stubs; $STUB_DIR/task-manager from setup() is still active
    export PATH="$PLANNER_STUB_DIR:$PATH"
}

@test "GH3: loop --for-planning: PLAN_BY_DEFAULT=false, needs-plan label — claimed, plan committed, label set" {
    _setup_planning_integration
    local number
    number=$(create_gh_issue "needs-plan")
    export PLAN_BY_DEFAULT=false

    run timeout 120 "$LOOP" --project "$GITHUB_REPO" --for-planning
    echo "# output: $output" >&3

    [[ "$(issue_assignee "$number")" == "$GITHUB_ASSIGNEE" ]]
    plan_in_bare_repo "$number"
    local labels
    labels=$(issue_labels "$number")
    echo "# labels: $labels" >&3
    [[ "$labels" == *"awaiting-review"* || "$labels" == *"in-planning"* ]]
}

@test "GH4: loop --for-planning: PLAN_BY_DEFAULT=false, no label — issue NOT claimed" {
    _setup_planning_integration
    local number
    number=$(create_gh_issue)
    export PLAN_BY_DEFAULT=false

    run timeout 20 "$LOOP" --project "$GITHUB_REPO" --for-planning
    [[ "$(issue_assignee "$number")" != "$GITHUB_ASSIGNEE" ]]
}

@test "GH5: loop --for-planning: PLAN_BY_DEFAULT=true, no label — claimed, plan committed" {
    _setup_planning_integration
    local number
    number=$(create_gh_issue)
    export PLAN_BY_DEFAULT=true

    run timeout 120 "$LOOP" --project "$GITHUB_REPO" --for-planning
    echo "# output: $output" >&3

    [[ "$(issue_assignee "$number")" == "$GITHUB_ASSIGNEE" ]]
    plan_in_bare_repo "$number"
}
