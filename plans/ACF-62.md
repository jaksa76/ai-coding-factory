# Plan: ACF-62 — Support issues in TODO.md

## Problem

The system currently supports two task backends: `jira` and `github`. Both require external services. There is no way to use the loop with a simple local `TODO.md` file, which would be useful for lightweight setups, local testing, and self-hosted workflows.

## Goal

Add a `todo` backend for `task-manager` that reads and writes tasks from a local `TODO.md` file. The loop can then operate against a TODO.md in the project repository without any external service dependency.

## Design

### TODO.md format

Standard GFM checkbox syntax, extended with additional checkbox characters to encode state:

| Checkbox | State                  |
|----------|------------------------|
| `- [ ]`  | Open (claimable)       |
| `- [>]`  | In Progress            |
| `- [?]`  | In Planning            |
| `- [~]`  | Awaiting Plan Review   |
| `- [x]`  | Done                   |

Example:
```markdown
- [ ] Add dark mode to the UI
- [>] Fix login page crash (#1)
- [x] Set up CI pipeline
```

### Issue keys

Each task is identified by its 1-based line number in the TODO.md file: `TODO-<N>` (e.g., `TODO-3`). Line numbers are stable during a task's lifetime because claiming and transitioning only changes the checkbox character in-place, not the line structure.

### `--project` parameter

For the `todo` backend, `--project` is the path to the TODO.md file (absolute or relative to the working directory). Example:

```bash
TASK_MANAGER=todo loop --project /repo/TODO.md --agent "claude ..."
```

### Planning labels

TODO.md items do not have labels. The planning workflow (`PLAN_BY_DEFAULT`, `needs-plan`, `skip-plan`) is simplified:

- `--for-planning`: claim items marked `- [ ]` that contain `[needs-plan]` in their text (or all items if `PLAN_BY_DEFAULT=true`)
- Implementation: claim items marked `- [ ]` that do **not** contain `[needs-plan]` (or those with `[skip-plan]` or `[plan-approved]` if `PLAN_BY_DEFAULT=true`)
- Fallback: if no label conventions are used, all open `- [ ]` items are eligible for implementation

### Race conditions

For single-machine use this is a local file; no distributed locking is needed. `tm_claim` reads, picks the first matching line, rewrites the file atomically, and returns the key. This is sufficient for single-worker scenarios.

### `tm_comment`

TODO.md does not natively support comments per item. `tm_comment` writes a comment line prefixed with `  - Note:` immediately below the matching task line:

```
- [>] Fix login page crash
  - Note: Implemented fix in src/auth.js, PR created
```

### `tm_assign`

Accepts `--account-id` for interface compatibility but is a no-op for the todo backend (single-user local file; ownership is implied).

### `tm_auth`

No-op — no credentials required.

### `tm_transitions` / `tm_transition`

Returns a fixed list: `["In Progress", "In Review", "Planning", "Awaiting Plan Review", "Done"]`. `tm_transition` maps each status to a checkbox character update.

## `loop` integration

Add a `todo` branch to the backend-selection block in `loop`:

```bash
elif [[ "${TASK_MANAGER:-jira}" == "todo" ]]; then
    [[ -z "${TODO_ASSIGNEE:-}" ]] && error_exit "TODO_ASSIGNEE is not set"
    ASSIGNEE_ID="$TODO_ASSIGNEE"
    export TODO_FILE="$PROJECT"
fi
```

`TODO_ASSIGNEE` is an arbitrary username string (e.g., `agent1`) used only for display/interface compatibility.

## Files to create / modify

| File | Action |
|------|--------|
| `task-manager/backends/todo` | **Create** — todo backend implementing all `tm_*` functions |
| `task-manager/task-manager.bats` | **Modify** — add tests for the `todo` backend |
| `loop/loop` | **Modify** — add `todo` backend branch to the env-var validation block |
| `loop/loop.bats` | **Modify** — add a test verifying loop works with `TASK_MANAGER=todo` |

## Implementation: `task-manager/backends/todo`

### Key helpers

```bash
_todo_file() {
    echo "${TODO_FILE:-${1:-TODO.md}}"
}

_todo_parse_line() {
    local file="$1" lineno="$2"
    sed -n "${lineno}p" "$file"
}

_todo_find_open() {
    local file="$1"
    grep -n '^\- \[ \]' "$file" | head -1
}

_todo_set_state() {
    local file="$1" lineno="$2" char="$3"
    sed -i "${lineno}s/^\(- \[.\]\)/- [${char}]/" "$file"
}
```

### `tm_claim`

1. Find first `- [ ]` line matching the planning/implementation filter
2. Replace `[ ]` with `[>]` (or `[?]` for planning) in-place
3. Output `{"key": "TODO-<N>", "summary": "<text>", "description": ""}`

### `tm_list`

Scan file for `- [ ]` lines (with planning filter applied), output:
```json
[{"key": "TODO-3", "summary": "Fix login page crash"}]
```

### `tm_view`

Read the line at the given number, strip checkbox prefix, return normalized JSON.

### `tm_transition`

Map status string → checkbox char, call `_todo_set_state`.

## Test cases

### `task-manager/backends/todo` (in `task-manager.bats`)

1. `todo: dispatcher selects todo backend` — TASK_MANAGER=todo auth exits 0
2. `todo: list: returns open items as JSON array`
3. `todo: list: excludes in-progress and done items`
4. `todo: list: --for-planning returns only needs-plan items when PLAN_BY_DEFAULT unset`
5. `todo: list: --for-planning returns all open items when PLAN_BY_DEFAULT=true`
6. `todo: claim: marks first open item as in-progress`
7. `todo: claim: --for-planning marks first eligible item as in-planning`
8. `todo: claim: returns correct JSON with key, summary, description`
9. `todo: claim: waits and retries when no open items found`
10. `todo: view: returns normalized JSON for given key`
11. `todo: transition: Done marks item as [x]`
12. `todo: transition: In Progress marks item as [>]`
13. `todo: transition: Awaiting Plan Review marks item as [~]`
14. `todo: comment: appends note line below the task`
15. `todo: transitions: returns JSON array of available statuses`

### `loop/loop.bats`

16. `loop: TASK_MANAGER=todo: claims and processes a task from TODO.md`

## Out of scope

- Concurrent multi-worker locking (file-level locking, flock)
- Inline labels/metadata beyond the `[needs-plan]`/`[skip-plan]`/`[plan-approved]` text conventions
- Persistence of comments across TODO.md rewrites
