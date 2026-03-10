# Plan: ACF-45 — The planner exits without an error message. Improve logging.

## Problem

`run_planning_loop` (and `run_implementation_loop`) can exit silently in several situations:

1. **Fatal claim failure** — when `task-manager claim` returns a non-0, non-2 exit code, the loop calls `exit "$CLAIM_EXIT"` with no preceding message (lines 351 and 176 in `loop`).
2. **Agent failure** — when `run_agent_with_retry` returns non-zero, the loop exits (via `set -euo pipefail`) with no message identifying the issue key or the nature of the failure.
3. **Git failures** — the planning loop's `git add / commit / push` block runs under `set -e` with no surrounding error handling, so any git failure causes a silent exit.

## Goal

Every exit from the planner (and implementation loop) must be preceded by a human-readable error message on stderr that identifies what failed and why.

## Changes

### 1. Log before fatal claim failure exit

In both `run_planning_loop` and `run_implementation_loop`, replace the bare `exit "$CLAIM_EXIT"` with a call to `error_exit`:

```bash
# before
elif [[ "$CLAIM_EXIT" -ne 0 ]]; then
    exit "$CLAIM_EXIT"
fi

# after
elif [[ "$CLAIM_EXIT" -ne 0 ]]; then
    error_exit "task-manager claim failed for project $PROJECT (exit $CLAIM_EXIT)"
fi
```

`error_exit` already prints to stderr and exits with code 1, which is sufficient. If preserving the original exit code matters, inline the message:

```bash
elif [[ "$CLAIM_EXIT" -ne 0 ]]; then
    echo "Error: task-manager claim failed for project $PROJECT (exit $CLAIM_EXIT)" >&2
    exit "$CLAIM_EXIT"
fi
```

Use the second form to preserve the original exit code.

### 2. Log agent failure

After `run_agent_with_retry`, check its return code and emit a message before exiting:

```bash
set +e
run_agent_with_retry "$PROMPT" "$ISSUE_KEY"
AGENT_EXIT=$?
set -e
if [[ "$AGENT_EXIT" -ne 0 ]]; then
    echo "Error: agent failed for $ISSUE_KEY (exit $AGENT_EXIT)" >&2
    exit "$AGENT_EXIT"
fi
```

Apply this in both loops.

### 3. Log git failures in the planning loop

Wrap the git operations in the planning loop with error handling:

```bash
# before
git -C "$WORK_DIR" add "plans/$ISSUE_KEY.md"
git -C "$WORK_DIR" commit -m "Add plan for $ISSUE_KEY"
git -C "$WORK_DIR" push "$GIT_REPO_URL" HEAD

# after
echo "Committing and pushing plan for $ISSUE_KEY..."
set +e
git -C "$WORK_DIR" add "plans/$ISSUE_KEY.md"
git -C "$WORK_DIR" commit -m "Add plan for $ISSUE_KEY"
GIT_EXIT=$?
set -e
if [[ "$GIT_EXIT" -ne 0 ]]; then
    echo "Error: git commit failed for $ISSUE_KEY (exit $GIT_EXIT)" >&2
    exit "$GIT_EXIT"
fi

set +e
git -C "$WORK_DIR" push "$GIT_REPO_URL" HEAD
GIT_EXIT=$?
set -e
if [[ "$GIT_EXIT" -ne 0 ]]; then
    echo "Error: git push failed for $ISSUE_KEY (exit $GIT_EXIT)" >&2
    exit "$GIT_EXIT"
fi
```

The same pattern applies to the implementation loop's push steps (already partially handled but worth making consistent).

## Files to modify

| File | Changes |
|------|---------|
| `loop/loop` | Add error messages before all `exit` calls in `run_planning_loop` and `run_implementation_loop` |
| `loop/loop.bats` | Add tests verifying error messages appear on stderr for each failure path |

## Test cases to add in `loop/loop.bats`

1. `planning loop: prints error and exits when claim fails with non-2 exit` — mock `task-manager` to exit 1; assert stderr contains "claim failed".
2. `planning loop: prints error and exits when agent fails` — mock agent to exit 1; assert stderr contains "agent failed".
3. `planning loop: prints error and exits when git commit fails` — mock git to exit 1 on commit; assert stderr contains "git commit failed".
4. `planning loop: prints error and exits when git push fails` — mock git to exit 1 on push; assert stderr contains "git push failed".
5. `implementation loop: prints error and exits when claim fails with non-2 exit` — same pattern as (1) for the implementation loop.
6. `implementation loop: prints error and exits when agent fails` — same pattern as (2) for the implementation loop.

## Out of scope

- Structured/JSON logging
- Log levels or verbosity flags
- Changes to `task-manager` internals
