# Plan: ACF-65 — Refactor the loop script for readability

## Problem

The `loop` script is hard to read because:

1. **Duplicated claim logic** — `run_implementation_loop()` and `run_planning_loop()` both contain identical issue-claiming and JSON-parsing boilerplate (awk + jq extraction, exit-code handling, no-issues wait).
2. **Cryptic one-liners** — `awk '/^\{/{f=1} f'` to extract JSON is not self-documenting.
3. **`set +e` / `set -e` sandwich** repeated 8 times for optional commands — creates visual noise that obscures the real logic.
4. **Mixed abstraction levels** — high-level steps (claim, work, push) are mixed with low-level implementation details (jq parsing, git remote URL construction) inside the same loop body.
5. **Long prompt-building blocks** interleaved with conditionals are hard to follow.
6. **Feature branch decision matrix** is spread across four separate `if` blocks with no named abstraction.

## Goal

Improve readability of `loop/loop` without changing behaviour. All existing tests must continue to pass.

## Approach

### 1. Extract `parse_claim_output()`

Replace the duplicated `awk '/^\{/{f=1} f'` pattern with a named function:

```bash
parse_claim_output() {
    local output="$1"
    printf '%s\n' "$output" | awk '/^\{/{f=1} f'
}
```

Called as: `ISSUE_JSON="$(parse_claim_output "$CLAIM_OUTPUT")"`

### 2. Extract `claim_issue()`

Pull the shared claim-and-wait block out of both loops into a single function:

```bash
# Usage: claim_issue [--for-planning]
# Sets ISSUE_KEY, ISSUE_SUMMARY, ISSUE_DESCRIPTION.
# Returns 0 on success, sleeps and returns 1 when no issues are available,
# exits on other errors.
claim_issue() { ... }
```

Both `run_implementation_loop()` and `run_planning_loop()` call this instead of repeating the same 15 lines.

### 3. Extract `use_feature_branch()`

Replace the four sequential `if` blocks that compute `USE_FEATURE_BRANCH` with a single predicate function:

```bash
# Prints "true" or "false"
use_feature_branch() {
    local labels_json="$1"
    ...
}
```

Makes the decision matrix explicit and testable.

### 4. Extract `try_task_manager()`

Replace every `set +e` / cmd / `set -e` / `if [[ $exit -ne 0 ]]; then warn` block with a small wrapper:

```bash
# Run a task-manager command, printing a warning on failure instead of exiting.
try_task_manager() {
    local desc="$1"; shift
    set +e
    "$@" 2>/dev/null
    local rc=$?
    set -e
    [[ $rc -ne 0 ]] && echo "Warning: $desc"
    return $rc
}
```

Usage:
```bash
try_task_manager "could not post comment on $ISSUE_KEY" \
    task-manager comment "$ISSUE_KEY" --comment "..."
```

Eliminates 8 repeated `set +e` / capture-exit / `set -e` / warn blocks.

### 5. Extract `build_implementation_prompt()` and `build_planning_prompt()`

Move prompt construction into dedicated functions that take issue key/summary/description and return the assembled prompt. This removes multi-line string-building mixed into the loop body.

### 6. Use `local` in all functions

Audit every function. Variables that are only needed within a function (`tmpout`, `agent_exit`, `parsed`, `wait_secs`, etc.) should be declared `local` to prevent accidental global state.

## Files to modify

| File | Changes |
|------|---------|
| `loop/loop` | Extract helpers as described above; simplify loop bodies |
| `loop/loop.bats` | No behavioural changes expected; verify all tests still pass |

## Out of scope

- Splitting loop into separate files (covered by ACF-68)
- Changing task-manager, agent, or git interfaces
- Adding new functionality or changing wait defaults

## Test plan

1. Run `bats loop/loop.bats` — all existing tests must pass without modification.
2. Manually verify that the `parse_claim_output`, `use_feature_branch`, and `try_task_manager` helpers can be unit-tested in isolation if desired (pure functions / no side effects).
