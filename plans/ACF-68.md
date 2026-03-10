# Plan: ACF-68 — Extract scripts from loop

## Problem

The `loop` script contains all per-issue logic inline inside `run_planning_loop()` and `run_implementation_loop()`. This makes each step hard to test in isolation, hard to run manually for a single issue, and harder to reason about. The loop itself should only be responsible for claiming issues and delegating to focused per-issue scripts.

## Goal

Extract two standalone scripts from `loop`:

- `loop/plan` — creates a plan for a specific issue (git pull, agent invocation, commit, push, comment, transition)
- `loop/implement` — implements a specific issue (git pull, feature branching, plan detection, agent invocation, push, PR, comment, transition)

The loop script is then simplified to a claim-and-dispatch loop that calls these scripts.

## Approach

### 1. Create `loop/plan <issue-key>`

Extract the per-issue body of `run_planning_loop()` into a new script `loop/plan`.

**Responsibilities:**
- Accept `<issue-key>` as the only argument
- Read issue summary and description via `task-manager view`
- Call `clone_or_pull` (shared helper sourced from loop-lib or inlined)
- Build the planning prompt and run `run_agent_with_retry`
- Commit `plans/<issue-key>.md` and push
- Post a comment with the plan URL
- Transition the issue to "Awaiting Plan Review" (with graceful fallback)

**Environment variables required:** same as `loop` (git, task-manager backend vars)

**Interface:**
```
plan <issue-key>
```

### 2. Create `loop/implement <issue-key>`

Extract the per-issue body of `run_implementation_loop()` into a new script `loop/implement`.

**Responsibilities:**
- Accept `<issue-key>` as the only argument
- Read issue summary and description via `task-manager view`
- Call `clone_or_pull`
- Handle feature branch logic (FEATURE_BRANCHES env, `needs-branch`/`skip-branch` labels)
- Detect `plans/<issue-key>.md` and include its contents in the prompt if present
- Build the implementation prompt and run `run_agent_with_retry`
- Push changes (feature branch or HEAD)
- If feature branch: open a PR, comment with PR URL, transition to "In Review"
- If not feature branch: comment and transition to Done

**Environment variables required:** same as `loop`

**Interface:**
```
implement <issue-key>
```

### 3. Shared helpers: extract `loop/git-utils.sh`

Several functions are needed by both scripts and by `loop` itself:
- `setup_git_credentials`
- `configure_git_identity`
- `clone_or_pull`
- WORK_DIR / REPO_NAME derivation logic

Extract these into `loop/git-utils.sh` (sourced by `loop`, `plan`, and `implement`).

The rest can be repeated in both scripts for the time being.

### 4. Simplify `loop`

After extraction, `run_planning_loop()` becomes:
```bash
run_planning_loop() {
    while true; do
        CLAIM_OUTPUT="$(task-manager claim --project "$PROJECT" --account-id "$ASSIGNEE_ID" --for-planning)"
        # ... handle exit codes ...
        ISSUE_KEY="$(extract_issue_key "$CLAIM_OUTPUT")"
        plan "$ISSUE_KEY"
        sleep "${INTER_ISSUE_WAIT:-300}"
    done
}
```

And `run_implementation_loop()` becomes:
```bash
run_implementation_loop() {
    while true; do
        CLAIM_OUTPUT="$(task-manager claim --project "$PROJECT" --account-id "$ASSIGNEE_ID")"
        # ... handle exit codes ...
        ISSUE_KEY="$(extract_issue_key "$CLAIM_OUTPUT")"
        implement "$ISSUE_KEY"
        sleep "${INTER_ISSUE_WAIT:-1200}"
    done
}
```

## Files to create / modify

| File | Action |
|------|--------|
| `loop/git-utils.sh` | **Create** — shared helpers (setup_git_credentials, configure_git_identity, clone_or_pull, WORK_DIR logic) |
| `loop/plan` | **Create** — per-issue planning script |
| `loop/implement` | **Create** — per-issue implementation script |
| `loop/loop` | **Modify** — source git-utils.sh, replace loop bodies with calls to `plan`/`implement` |
| `loop/loop.bats` | **Modify** — update tests to reflect simplified loop; add tests for plan/implement dispatch |
| `loop/plan.bats` | **Create** — unit tests for `plan` script |
| `loop/implement.bats` | **Create** — unit tests for `implement` script |

## Test cases

### plan.bats
1. Runs agent with correct planning prompt including issue summary and description
2. Commits `plans/<key>.md` and pushes after agent succeeds
3. Posts comment with plan URL
4. Transitions issue to "Awaiting Plan Review" when status is available
5. Falls back gracefully when "Awaiting Plan Review" is not in transitions
6. Fails with usage error when no issue key provided

### implement.bats
1. Runs agent with correct implementation prompt (no feature branch)
2. Includes plan file contents in prompt when `plans/<key>.md` exists
3. Skips plan file when it does not exist
4. Creates feature branch when FEATURE_BRANCHES=true
5. Creates feature branch when `needs-branch` label is present
6. Skips feature branch when `skip-branch` label is present
7. Opens PR and transitions to "In Review" on feature branch path
8. Comments and transitions to Done on non-feature-branch path
9. Fails with usage error when no issue key provided

### loop.bats (updates)
1. Calls `plan <key>` when running in planning mode
2. Calls `implement <key>` when running in implementation mode
3. Sleeps correct duration between issues in each mode

## Out of scope

- Changing the agent invocation interface (`agent run`)
- Changing task-manager backend logic
- Modifying workers/ Dockerfiles
