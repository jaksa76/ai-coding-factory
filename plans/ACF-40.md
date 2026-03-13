# Plan: ACF-40 — Support GitHub Issues

## Goal

Allow projects to use GitHub Issues as the task source instead of Jira by
adding a `github` backend to `task-manager`.

This plan depends on ACF-49 (task-manager abstraction). Once ACF-49 lands,
`loop` and `planner-loop` already call `task-manager` for all task operations;
this plan only adds a new backend implementation and makes no structural changes
to those scripts.

## Motivation

Some projects track work in GitHub Issues, not Jira. Workers should be able to
claim, work on, and close GitHub issues using the same `loop` / `planner-loop`
infrastructure, with no Jira credentials required.

## Design overview

Add `TASK_MANAGER=github` (the env var introduced in ACF-49; default: `jira`).
When set to `github`, `task-manager` sources `task-manager/backends/github`,
which maps each `tm_*` function to `gh` CLI calls.

The `gh` CLI is already installed in the copilot worker and is readily available
on most GitHub-connected machines.

## New env vars

| Variable | Purpose |
|---|---|
| `GH_ASSIGNEE` | GitHub username used for self-assignment |

`GH_TOKEN` already exists and is reused for GitHub API auth.
`TASK_MANAGER` is the selector introduced in ACF-49.

When `TASK_MANAGER=github`, Jira vars (`JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN`,
`JIRA_ASSIGNEE_ACCOUNT_ID`) are not required.

The `--project` argument to `loop` / `planner-loop` accepts `owner/repo` format
when using the GitHub backend (instead of a Jira project key like `ACF`).

## GitHub Issues workflow

### tm_claim (implementation)

1. List open issues without an assignee and without an `in-progress` label.
   For `PLAN_BY_DEFAULT=true`: exclude issues with `needs-plan` unless they also
   have `skip-plan`. For plain claiming: exclude issues with `needs-plan`.
2. Self-assign the issue + add the `in-progress` label via `gh api`.
3. Wait 5 seconds, re-fetch. If assignee is no longer self, retry (optimistic locking).
4. Output JSON: `{ "key": "<number>", "summary": "<title>", "description": "<body>" }`.

### tm_claim (planning)

1. List open issues without an assignee that have `needs-plan` label
   (or all issues if `PLAN_BY_DEFAULT=true`, excluding `skip-plan`).
2. Same assign-and-verify flow, output same JSON shape.

### Mapping of tm_* functions to gh CLI

| Function | GitHub equivalent |
|---|---|
| `tm_auth` | `gh auth status` / `gh auth login` |
| `tm_claim` | list → assign → verify → output JSON (see above) |
| `tm_list` | `gh issue list --json` filtered by assignee/labels |
| `tm_view` | `gh issue view <num> --json` mapped to `{key, summary, description, labels, assignee}` |
| `tm_assign` | `gh issue edit <num> --add-assignee <user>` |
| `tm_comment` | `gh issue comment <num> --body "..."` |
| `tm_transition` | add/remove labels to represent status (see table below) |
| `tm_transitions` | return fixed JSON array based on current labels |

### Status-to-label mapping for tm_transition

| Status argument | Labels added | Labels removed |
|---|---|---|
| `In Progress` | `in-progress` | — |
| `In Review` | `in-review` | `in-progress` |
| `Planning` | `in-planning` | `in-progress` |
| `Awaiting Plan Review` | `awaiting-review` | `in-planning` |
| `Done` | — | `in-progress`, `in-review` (and close issue) |

Label operations always succeed gracefully (never fatal).

## Files to create

### `task-manager/backends/github`

Sourced by `task-manager/task-manager` when `TASK_MANAGER=github`. Implements
all `tm_*` functions using the `gh` CLI. Contains:

- `tm_auth` — checks / performs `gh auth login`.
- `tm_claim` — full optimistic-lock claim loop (mirrors the logic in
  `task-manager/backends/jira`'s `tm_claim`, adapted for GitHub labels).
- `tm_list` — lists claimable issues via `gh issue list --json`, applies
  label-based filters equivalent to the Jira JQL logic.
- `tm_view` — fetches an issue and normalises the output to
  `{key, summary, description, labels, assignee: {accountId}}`.
- `tm_assign` — assigns via `gh issue edit --add-assignee`.
- `tm_comment` — posts a comment via `gh issue comment`.
- `tm_transition` — manipulates labels (and closes the issue for `Done`).
- `tm_transitions` — returns a hardcoded or label-derived JSON array of
  available transition names.

This file is sourced (not executed), so it needs no shebang or argument
parsing of its own.

## Files to modify

### `task-manager/task-manager.bats`

Add GitHub backend test cases (alongside the existing jira and dispatcher
tests):

- `claim` with `TASK_MANAGER=github`: finds and claims first eligible issue.
- Retries on assignment race.
- Exits non-zero when no eligible issues exist.
- Respects `PLAN_BY_DEFAULT` and `needs-plan` / `skip-plan` labels.
- `--for-planning` selects issues with `needs-plan` label.
- `tm_transition "Done"` closes the issue.

All tests stub the `gh` CLI at PATH level (same pattern as `acli` stubs).

### `loop/loop`

No structural changes. The only required update is validation:

- Make Jira env-var checks conditional on `TASK_MANAGER=jira` (or default).
- Add GitHub env-var checks when `TASK_MANAGER=github`:
  ```bash
  if [[ "${TASK_MANAGER:-jira}" == "github" ]]; then
      [[ -z "${GH_TOKEN:-}" ]]        && error_exit "GH_TOKEN is not set"
      [[ -z "${GH_ASSIGNEE:-}}" ]] && error_exit "GH_ASSIGNEE is not set"
  else
      # existing Jira checks
  fi
  ```
- `git config user.email`: fall back to
  `$GH_ASSIGNEE@users.noreply.github.com` when `TASK_MANAGER=github`.
- Update `usage` to document `TASK_MANAGER` and `GH_ASSIGNEE`.

All actual task operations (`claim`, `view`, `comment`, `transition`) are
already routed through `task-manager` after ACF-49 — no further changes needed.

### `planner/planner-loop`

Same validation-only changes as `loop/loop` above.

### `loop/loop.bats` and `planner/planner-loop.bats`

Add test cases for `TASK_MANAGER=github`:

- Validation rejects missing `GH_TOKEN` / `GH_ASSIGNEE`.
- With a stubbed `task-manager` (or real dispatcher + stubbed `gh`), the loop
  runs end-to-end for a GitHub issue.

### `ARCHITECTURE.md`

Update env-var table and loop-flow description to mention `TASK_MANAGER=github`
and `GH_ASSIGNEE`.

### `CLAUDE.md`

Add `GH_TOKEN`, `GH_ASSIGNEE` to the environment variable table and note
that `TASK_MANAGER` selects the backend.

## Implementation steps

1. Create `task-manager/backends/github` implementing all `tm_*` functions.
2. Add GitHub backend test cases to `task-manager/task-manager.bats`
   (stub `gh` CLI).
3. Update validation in `loop/loop` for `TASK_MANAGER=github`.
4. Add `TASK_MANAGER=github` test cases to `loop/loop.bats`.
5. Update validation in `planner/planner-loop` for `TASK_MANAGER=github`.
6. Add corresponding test cases to `planner/planner-loop.bats`.
7. Update `ARCHITECTURE.md` and `CLAUDE.md`.
8. Run all bats test suites and confirm no regressions.

## Dependencies

- ACF-49 must be merged first (`task-manager` dispatcher and jira backend must exist).
- `gh` CLI must be installed and authenticated (`GH_TOKEN` in env).
  The copilot worker already has `gh` installed; other workers may need it added.
- No changes required to `worker-builder` or `factory`.
- The label convention (`needs-plan`, `skip-plan`, `plan-approved`) is reused
  verbatim — only the state-transition mechanism changes from Jira status to
  GitHub labels.
