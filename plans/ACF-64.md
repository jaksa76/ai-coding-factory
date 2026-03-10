# Plan: ACF-64 — Devise a strategy to resume tasks when a worker/planner crashes

## Problem

When a worker or planner container crashes (OOM, agent hang, network error, host restart) while an issue is "In Progress" and assigned to it, the issue is permanently orphaned. The JQL used by `claim` is:

```
project = "..." AND assignee is EMPTY AND statusCategory != Done
```

An issue assigned to the worker account is invisible to all future workers. Without intervention, the backlog silently shrinks as issues disappear into an orphaned "In Progress" state.

This is issue H2 from `docs/RELIABILITY_ANALYSIS.md`.

## Goal

Ensure that every issue eventually completes (or is retried) after a crash, with no manual Jira intervention required.

## Failure scenarios

| Crash point | State at crash | Work done |
|---|---|---|
| Before `clone_or_pull` | Assigned + In Progress | None |
| During agent execution | Assigned + In Progress | Partial (lost with container) |
| After agent, before push | Assigned + In Progress | Partial (lost with container) |
| After push, before comment/transition | Assigned + In Progress | Code pushed; Jira not updated |

In all cases the safe recovery is to unassign and reset to the pre-"In Progress" state so any worker can pick it up again. The push-then-crash case is idempotent: re-running the agent and re-pushing is safe (the agent will see the prior commits and can build on or supersede them).

## Strategy

Two complementary mechanisms, each simple enough to implement independently:

### 1. Self-recovery on loop startup (primary)

At the start of `loop`, before entering the claim/work loop, query the task manager for any issues currently assigned to this worker that are "In Progress". Reset each one by unassigning it and transitioning it back to "To Do" (or the workflow's equivalent open state).

When a container crashes and is restarted (via Docker restart policy), the loop cleans up its own mess before picking up new work.

```
loop starts
  → task-manager list --assignee-self --status "In Progress"
  → for each orphaned issue:
      task-manager unassign <key>
      task-manager transition <key> --status "To Do"
      echo "Recovered orphaned issue <key>"
  → enter normal claim/work loop
```

**Why self-recovery is sufficient for the common case:** Docker restart policies (`--restart=on-failure` or `--restart=unless-stopped`) restart the container automatically after a crash. The first thing the restarted loop does is sweep its own orphans. No external sweeper process needed.

**Scope:** `loop` calls `task-manager` already; this adds two new `task-manager` subcommands (`list` with filters and `unassign`). The `claim` script is not changed.

### 2. Docker restart policy enforcement (prerequisite)

Self-recovery is only useful if the container actually restarts. `factory add` must always pass `--restart=on-failure` (or `--restart=unless-stopped`) when starting worker containers. Without this, a crashed container stays stopped and the orphan is never recovered.

This is a one-line change to `factory/factory`.

### Optional: factory sweep command (secondary, for external recovery)

For cases where a container is permanently stopped (host decommissioned, manually killed), add a `factory sweep` subcommand that an operator or cron job can run to reset all stale "In Progress" issues across all worker accounts:

```
factory sweep --project <key> --older-than 2h
```

This queries `task-manager` for issues in "In Progress" with no recent activity and resets them. Implemented as a thin wrapper around `task-manager list` + `task-manager unassign` + `task-manager transition`. This is a **nice-to-have** and can be deferred until self-recovery is validated.

## Required task-manager changes

The `task-manager` wrapper needs two new operations, for both `jira` and `github` backends:

| Operation | CLI | Purpose |
|---|---|---|
| List assigned in-progress issues | `task-manager list --assignee-self --status "In Progress"` | Find orphaned issues owned by this worker |
| Unassign issue | `task-manager unassign <key>` | Release the issue so other workers can claim it |

The `transition` subcommand already exists. `unassign` is new (for `jira` backend: `acli jira issue assign <key> --unassign`; for `github` backend: remove assignee via `gh api`).

## Files to modify

| File | Change |
|---|---|
| `loop/loop` | Add `recover_orphaned_issues()` called once before main loop |
| `task-manager/task-manager` | Add `list` and `unassign` subcommands |
| `task-manager/backends/jira` | Implement `list` (JQL: `assignee = currentUser() AND status = "In Progress"`) and `unassign` |
| `task-manager/backends/github` | Implement `list` and `unassign` |
| `factory/factory` | Add `--restart=on-failure` to `docker run` in `add` subcommand |
| `loop/loop.bats` | Tests for `recover_orphaned_issues()`: no orphans, one orphan, recovery failure (non-fatal) |
| `task-manager/task-manager.bats` | Tests for `list` and `unassign` subcommands |

## Implementation detail: `recover_orphaned_issues()`

```bash
recover_orphaned_issues() {
    echo "Checking for orphaned in-progress issues assigned to this worker..."
    set +e
    ORPHANS="$(task-manager list --assignee-self --status "In Progress" 2>/dev/null)"
    LIST_EXIT=$?
    set -e

    if [[ "$LIST_EXIT" -ne 0 ]]; then
        echo "Warning: could not query for orphaned issues; skipping recovery"
        return 0
    fi

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        echo "Recovering orphaned issue $key..."
        set +e
        task-manager unassign "$key" 2>/dev/null
        task-manager transition "$key" --status "To Do" 2>/dev/null
        set -e
        echo "Recovered $key (reset to To Do, unassigned)"
    done <<< "$ORPHANS"
}
```

Recovery failures are non-fatal (logged as warnings). The loop proceeds even if recovery partially fails — the worst outcome is an issue stays orphaned, which is the current behaviour.

## Test plan

1. **Unit tests — `task-manager list`:** stub backend returns JSON list; verify keys printed one per line.
2. **Unit tests — `task-manager unassign`:** stub backend called with correct key; non-zero exit prints error.
3. **Unit tests — `recover_orphaned_issues()`:**
   - No orphans: function returns 0, no unassign/transition calls made.
   - One orphan: `task-manager unassign` and `task-manager transition` called with correct key.
   - `list` fails: warning printed, loop proceeds (no crash).
   - `unassign` fails: warning printed, remaining issues still processed.
4. **Integration test:** start a worker, manually set an issue to "In Progress" assigned to the worker account, restart the loop, verify the issue is reset to "To Do" and unassigned before the worker claims a new issue.
5. **`factory add` test:** verify `docker run` command includes `--restart=on-failure`.

## Out of scope

- Detecting *partial pushes* (code pushed but no comment/transition): handled by re-running the agent, which is idempotent.
- `factory sweep` command: deferred until self-recovery is validated.
- Configuring the stale-issue timeout threshold: not needed for self-recovery (any "In Progress" issue assigned to self at startup is by definition orphaned — a healthy worker never leaves one).
