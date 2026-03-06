# Plan: ACF-40 — Support GitHub Issues

## Goal

Allow projects to use GitHub Issues as the task source instead of Jira.
The task backend is selected at the project level via a `TASK_BACKEND` env var.

## Motivation

Some projects track work in GitHub Issues, not Jira. Workers should be able
to claim, work on, and close GitHub issues using the same `loop` / `planner-loop`
infrastructure, with no Jira credentials required.

## Design overview

Introduce `TASK_BACKEND=github` (default: `jira`). When set to `github`:

- `loop` and `planner-loop` skip Jira env-var validation and Jira API calls.
- Issue claiming is handled by a new `claim-github` script.
- Post-work operations (comment, close/transition) use the `gh` CLI instead of `acli jira`.

The `gh` CLI is already installed in the copilot worker and is readily available
on most GitHub-connected machines.

## New env vars

| Variable | Purpose |
|---|---|
| `TASK_BACKEND` | `jira` (default) or `github` |
| `GITHUB_ASSIGNEE` | GitHub username used for self-assignment |

`GH_TOKEN` already exists and is reused for GitHub API auth.
When `TASK_BACKEND=github`, Jira vars (`JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN`,
`JIRA_ASSIGNEE_ACCOUNT_ID`) are not required.

The `--project` argument to `loop` / `planner-loop` accepts `owner/repo` format
when using the GitHub backend (instead of a Jira project key like `ACF`).

## GitHub Issues workflow

### Claiming (implementation)

1. List open issues without an assignee and without an `in-progress` label.
   For `PLAN_BY_DEFAULT=true`: exclude issues with `needs-plan` unless they also
   have `skip-plan`. For plain claiming: exclude issues with `needs-plan`.
2. Self-assign the issue + add the `in-progress` label via `gh api`.
3. Wait 5 seconds, re-fetch. If assignee is no longer self, retry (optimistic locking).
4. Output JSON: `{ "key": "<number>", "summary": "<title>", "description": "<body>" }`.

### Claiming (planning)

1. List open issues without an assignee that have `needs-plan` label
   (or all issues if `PLAN_BY_DEFAULT=true`, excluding `skip-plan`).
2. Same assign-and-verify flow, output same JSON shape.

### Post-work operations

| Operation | GitHub equivalent |
|---|---|
| Fetch description | Already in claim output; or `gh issue view <num> --json body` |
| Get labels | `gh issue view <num> --json labels` |
| Add comment | `gh issue comment <num> --body "..."` |
| Close issue (Done) | `gh issue close <num>` |
| Transition to In Review | Add `in-review` label, remove `in-progress` |
| Transition to Planning | Add `in-planning` label, remove `in-progress` |
| Transition to Awaiting Plan Review | Add `awaiting-review` label, remove `in-planning` |

There are no Jira workflow statuses to check for presence; label operations
always succeed (graceful by nature).

## Files to create

### `claim/claim-github`

Standalone bash script. Interface mirrors `claim`:

```
claim-github --repo <owner/repo> [--for-planning]

Environment:
  GH_TOKEN          GitHub personal access token
  GITHUB_ASSIGNEE   GitHub username for self-assignment
```

Internal functions:
- `build_issue_filter [--for-planning]` — produce `jq` filter selecting claimable issues
- `assign_and_verify <number>` — assign + add `in-progress` label, wait 5 s, re-fetch
- `label_issue <number> <add-label> [remove-label]` — add/remove labels via `gh api`
- Main loop: search → assign → verify → output JSON

Output (stdout): single JSON object `{ "key": "42", "summary": "...", "description": "..." }`.
Exit 2 when no issues are available (same convention as `claim`).

### `claim/claim-github.bats`

Unit tests with `gh` stubbed. Key cases:
- Finds and claims first eligible issue.
- Retries on assignment race (another process grabbed the issue).
- Exits 2 when no eligible issues exist.
- Respects `PLAN_BY_DEFAULT` and `needs-plan` / `skip-plan` labels.
- `--for-planning` selects issues with `needs-plan` label.

## Files to modify

### `loop/loop`

1. **`TASK_BACKEND` detection**: read `TASK_BACKEND` (default `jira`) after
   arg parsing.

2. **Validation**: make Jira env-var checks conditional on `TASK_BACKEND=jira`;
   add GitHub env-var checks when `TASK_BACKEND=github`:
   ```bash
   if [[ "${TASK_BACKEND:-jira}" == "github" ]]; then
       [[ -z "${GH_TOKEN:-}" ]]        && error_exit "GH_TOKEN is not set"
       [[ -z "${GITHUB_ASSIGNEE:-}" ]] && error_exit "GITHUB_ASSIGNEE is not set"
   else
       # existing Jira checks
   fi
   ```

3. **`git config user.email`**: fall back to
   `$GITHUB_ASSIGNEE@users.noreply.github.com` when `TASK_BACKEND=github`.

4. **Step 1 — claim**: dispatch to `claim-github` or `claim`:
   ```bash
   if [[ "${TASK_BACKEND:-jira}" == "github" ]]; then
       CLAIM_OUTPUT="$(claim-github --repo "$PROJECT")"
   else
       CLAIM_OUTPUT="$(claim --project "$PROJECT" --account-id "$JIRA_ASSIGNEE_ACCOUNT_ID")"
   fi
   ```

5. **Step 2.5 — labels for feature branch**: use
   `gh issue view "$ISSUE_KEY" --json labels` when GitHub backend.

6. **Step 3 — description**: description is already in `claim-github` output
   (included in the JSON); no separate fetch needed for GitHub.

7. **Step 5/6 — comment and close**:
   ```bash
   if [[ "${TASK_BACKEND:-jira}" == "github" ]]; then
       gh issue comment "$ISSUE_KEY" --repo "$PROJECT" --body "Implemented: $ISSUE_SUMMARY"
       gh issue close "$ISSUE_KEY" --repo "$PROJECT"
   else
       # existing acli jira calls
   fi
   ```

8. **Step 7 — In Review transition** (feature branch path):
   ```bash
   if [[ "${TASK_BACKEND:-jira}" == "github" ]]; then
       gh issue edit "$ISSUE_KEY" --repo "$PROJECT" \
           --add-label "in-review" --remove-label "in-progress"
   else
       # existing acli jira transition
   fi
   ```

9. **`usage`**: document `TASK_BACKEND`, `GITHUB_ASSIGNEE`.

### `planner/planner-loop`

Same structural changes as `loop` but for the planning phase:

1. Conditional env-var validation.
2. `git config user.email` fallback.
3. Use `claim-github --repo "$PROJECT" --for-planning` when GitHub backend.
4. After plan is committed and pushed:
   - **Comment**: `gh issue comment "$ISSUE_KEY" --repo "$PROJECT" --body "Created plan: $PLAN_URL"`
   - **Transition to Awaiting Plan Review**:
     `gh issue edit "$ISSUE_KEY" --repo "$PROJECT" --add-label "awaiting-review" --remove-label "in-planning"`
   (Graceful: label add/remove never fails fatally — just log warnings.)

### `loop/loop.bats` and `planner/planner-loop.bats`

Add test cases for `TASK_BACKEND=github`:
- Validation rejects missing `GH_TOKEN` / `GITHUB_ASSIGNEE`.
- Dispatches to `claim-github` (stubbed) instead of `claim`.
- Posts comment via `gh issue comment` instead of `acli jira comment add`.
- Closes issue via `gh issue close` instead of Jira transition.

### `ARCHITECTURE.md`

Update env-var table and loop-flow description to mention `TASK_BACKEND`.

### `CLAUDE.md`

Add `GH_TOKEN`, `GITHUB_ASSIGNEE`, and `TASK_BACKEND` to the environment
variable table.

## Implementation steps

1. Create `claim/claim-github` with full claim logic.
2. Create `claim/claim-github.bats` and verify tests pass.
3. Modify `loop/loop` to support `TASK_BACKEND=github` (validation, dispatch, post-work).
4. Add `TASK_BACKEND=github` test cases to `loop/loop.bats`.
5. Modify `planner/planner-loop` to support `TASK_BACKEND=github`.
6. Add corresponding test cases to `planner/planner-loop.bats`.
7. Update `ARCHITECTURE.md` and `CLAUDE.md`.
8. Run all bats test suites and confirm no regressions.

## Dependencies

- `gh` CLI must be installed and authenticated (`GH_TOKEN` in env).
  The copilot worker already has `gh` installed; other workers may need it added.
- No changes required to `claim`, `worker-builder`, or `factory`.
- The planner planning-phase label convention (`needs-plan`, `skip-plan`,
  `plan-approved`) is reused verbatim — only the state-transition mechanism
  changes from Jira status to GitHub labels.
