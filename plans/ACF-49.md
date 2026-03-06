# Plan: ACF-49 — Create a wrapper for task managers

## Goal

Decouple `claim`, `loop`, and `planner-loop` from Jira-specific tooling by
introducing a `task-manager` abstraction layer. The initial backend wraps the
existing Jira/`acli` integration. Future backends (GitHub Issues, Linear, etc.)
can be added by implementing the same interface without touching any of the
higher-level scripts.

## Motivation

`claim`, `loop`, and `planner-loop` all call `acli jira …` directly, and
there are already minor inconsistencies (`acli jira workitem transition` vs
`acli jira issue transition`, `acli jira comment add` vs `acli jira workitem
comment`). Any change in task manager — or even just the Jira CLI — requires
editing multiple scripts. A thin wrapper centralises all task manager calls
and makes the interface consistent.

## Interface

New script: `task-manager/task-manager`

Backend is selected via the `TASK_MANAGER` environment variable (default:
`jira`). The script sources a backend file from
`task-manager/backends/$TASK_MANAGER` which implements the required shell
functions.

### Commands

```
task-manager auth
    Authenticate with the task management backend.
    Jira: acli jira auth login / status

task-manager list --project <key> [--for-planning]
    List claimable issues.
    Returns JSON array: [{key, summary}]
    Jira: acli jira workitem search --jql … --json --paginate
    JQL logic (build_search_jql_for_planning / _for_implementation) moves here.

task-manager view <issue-key>
    Fetch full issue details.
    Returns JSON: {key, summary, description, labels: [], assignee: {accountId}}
    Jira: acli jira workitem view --json

task-manager assign <issue-key> --account-id <id>
    Assign the issue to the given account ID.
    Jira: acli jira workitem assign --key … --assignee … --yes

task-manager comment <issue-key> --comment <text>
    Add a comment to the issue.
    Jira: acli jira comment add --issue … --comment …

task-manager transition <issue-key> --status <status>
    Transition the issue to the given status.
    Jira: acli jira workitem transition --key … --status … --yes

task-manager transitions <issue-key>
    List the names of available transitions for the issue.
    Returns JSON array of strings.
    Jira: acli jira workitem transitions --key … --json | jq '[.[].name]'
```

## Environment variables

| Variable | Backend | Purpose |
|---|---|---|
| `TASK_MANAGER` | all | Backend to use (default: `jira`) |
| `JIRA_SITE` | jira | Jira host |
| `JIRA_EMAIL` | jira | Account email |
| `JIRA_TOKEN` | jira | API token |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | jira | Account ID for self-assignment (passed by callers) |
| `PLAN_BY_DEFAULT` | jira | Controls JQL for `list` (existing semantics, moves into backend) |

No existing env var names change; `TASK_MANAGER` is additive.

## Files to create

### `task-manager/task-manager`

Main dispatcher script. Validates `TASK_MANAGER`, sources
`task-manager/backends/$TASK_MANAGER`, parses the subcommand, and dispatches
to the backend function (`tm_auth`, `tm_list`, `tm_view`, `tm_assign`,
`tm_comment`, `tm_transition`, `tm_transitions`). Exits with an error if
`TASK_MANAGER` names an unknown backend. Must be executable.

### `task-manager/backends/jira`

Jira backend. Implements each `tm_*` function using normalised `acli jira …`
calls. Contains the JQL-building logic moved from `claim/claim`. This file is
sourced (not executed), so it needs no shebang or argument parsing of its own.

### `task-manager/task-manager.bats`

Unit tests for the dispatcher. Uses stub scripts to validate that the correct
backend function is called for each subcommand and that an unknown `TASK_MANAGER`
value produces an error.

## Files to modify

### `claim/claim`

- Remove `authenticate_jira()` → replace call with `task-manager auth`.
- Remove `build_search_jql_for_planning`, `build_search_jql_for_implementation`,
  `build_search_jql` functions (logic moves to jira backend).
- Replace `acli jira workitem search …` with `task-manager list --project … [--for-planning]`.
- Replace `acli jira workitem assign …` with `task-manager assign <key> --account-id <id>`.
- Replace `acli jira workitem view … | jq -r '.fields.assignee.accountId'` with
  `task-manager view <key> | jq -r '.assignee.accountId'`.
- Replace `acli jira workitem transition …` with `task-manager transition <key> --status …`.
- Replace final `acli jira workitem view … | jq …` with `task-manager view <key>`.

### `loop/loop`

- Replace `acli jira issue get … --field labels` with
  `task-manager view <key> | jq -r '.labels'`.
- Replace `acli jira workitem view … | jq -r '.fields.description'` with
  `task-manager view <key> | jq -r '.description'`.
- Replace `acli jira comment add …` with `task-manager comment <key> --comment …`.
- Replace `acli jira issue transition …` with `task-manager transition <key> --status …`.

### `planner/planner-loop`

- Replace `acli jira workitem view … | jq -r '.fields.description'` with
  `task-manager view <key> | jq -r '.description'`.
- Replace `acli jira workitem comment …` with `task-manager comment <key> --comment …`.
- Replace `acli jira workitem transitions …` with `task-manager transitions <key>`.
- Replace `acli jira workitem transition …` with `task-manager transition <key> --status …`.

## Test strategy

### New: `task-manager/task-manager.bats`

Stubs the jira backend functions (`tm_auth`, `tm_list`, etc.) to verify that
`task-manager` dispatches correctly. Key test cases:

- Each subcommand calls the corresponding `tm_*` function.
- Unknown `TASK_MANAGER` value exits non-zero with an error message.
- `--help` prints usage.

### Existing tests (`claim`, `loop`, `planner-loop`)

The existing tests stub `acli` at the PATH level. Because `task-manager`
(the jira backend) itself calls `acli`, the stubs continue to work provided
`task-manager` is also on PATH in the test environment.

Update the `setup()` in each test file to add `task-manager/` to PATH
(e.g. `export PATH="$BATS_TEST_DIRNAME/../task-manager:$PATH"`) so the real
dispatcher is found but `acli` remains stubbed. No other changes to existing
test bodies should be required.

## Implementation steps

1. Create `task-manager/backends/jira` with `tm_*` functions (moving JQL logic from `claim`).
2. Create `task-manager/task-manager` dispatcher and make it executable.
3. Write `task-manager/task-manager.bats`.
4. Update `claim/claim` to use `task-manager`.
5. Update `loop/loop` to use `task-manager`.
6. Update `planner/planner-loop` to use `task-manager`.
7. Update `setup()` in `claim/claim.bats`, `loop/loop.bats`, `loop/loop-integration.bats`,
   `planner/planner-loop.bats`, and `planner/planner-loop-integration.bats` to add
   `task-manager/` to PATH.
8. Run the full test suite to confirm no regressions.
