# ACF-79: support SCRUM projects

## Summary

The Jira backend currently claims any unassigned issue matching the project/status/label filters, regardless of sprint membership. SCRUM teams organise work into sprints, so workers picking up backlog issues outside the active sprint is incorrect behaviour.

Add a `JIRA_CURRENT_SPRINT` environment variable (boolean, default unset/false). When set to `true`, the JQL for both planning and implementation queries gains an additional clause `AND sprint in openSprints()`, restricting claimed issues to the active sprint only.

The factory already passes env vars to workers via `--env-file` / the ECS task definition, so no factory-side changes are needed — adding the variable to the env file is sufficient.

## Files to Change

| File | Change |
|---|---|
| `task-manager/backends/jira` | Append `AND sprint in openSprints()` to both JQL builders when `JIRA_CURRENT_SPRINT=true` |
| `task-manager/task-manager.bats` | Add tests for JQL with/without `JIRA_CURRENT_SPRINT` |
| `CLAUDE.md` | Document the new env var in the environment variable table |

## Implementation Steps

### 1. Update `_build_search_jql_for_planning` and `_build_search_jql_for_implementation`

Both functions in `task-manager/backends/jira` build a JQL string and `echo` it. Add a helper that appends the sprint clause when the env var is set, then call it at the end of each function.

Introduce a small helper right before the two functions:

```bash
_sprint_clause() {
    if [[ "${JIRA_CURRENT_SPRINT:-false}" == "true" ]]; then
        echo " AND sprint in openSprints()"
    fi
}
```

Then modify each function to append the clause before `ORDER BY`:

`_build_search_jql_for_planning` (lines 16-23):

```bash
_build_search_jql_for_planning() {
    local project="$1"
    local sprint
    sprint=$(_sprint_clause)
    if [[ "${PLAN_BY_DEFAULT:-false}" == "true" ]]; then
        echo "project = \"$project\" AND assignee is EMPTY AND status = \"To Do\" AND (labels NOT IN (\"skip-plan\") OR labels is EMPTY)${sprint} ORDER BY rank ASC"
    else
        echo "project = \"$project\" AND assignee is EMPTY AND status = \"To Do\" AND labels IN (\"needs-plan\")${sprint} ORDER BY rank ASC"
    fi
}
```

Apply the same pattern to `_build_search_jql_for_implementation`.

### 2. Document the new env var in `CLAUDE.md`

Add a row to the environment variable table under `JIRA_PROJECT`:

```
| `JIRA_CURRENT_SPRINT` | When `true`, restrict claimed issues to the active sprint (`sprint in openSprints()`) (jira backend) |
```

### 3. Add tests to `task-manager/task-manager.bats`

Following the existing JQL test pattern (lines 336–430), add two tests in the `# ── claim: planning filter / JQL ──` section:

- **`JIRA_CURRENT_SPRINT=true` includes sprint clause** — stub `acli` to echo `--jql` argument, set `JIRA_CURRENT_SPRINT=true`, call `task-manager claim`, assert output contains `openSprints`.
- **`JIRA_CURRENT_SPRINT` unset does not include sprint clause** — same setup without the var, assert output does not contain `openSprints`.

Also add the equivalent two tests for `--for-planning`.

## Testing

Run the unit tests for the task-manager:

```bash
bats task-manager/task-manager.bats
```

Run sprint-specific tests only during development:

```bash
bats task-manager/task-manager.bats -f "sprint"
```

For manual validation: set `JIRA_CURRENT_SPRINT=true` in the env file, start a worker, and confirm it only picks up issues from the active sprint.

## Risks / Edge Cases

1. **Kanban projects**: `openSprints()` is only valid for SCRUM boards. On a Kanban project, the JQL clause returns an error. The feature is opt-in (`JIRA_CURRENT_SPRINT=true` is not the default), so Kanban users are unaffected as long as they don't set the flag.

2. **Multiple open sprints**: `sprint in openSprints()` matches issues in *any* currently open sprint. Most SCRUM teams have exactly one open sprint, but if a team has two (e.g. a carry-over sprint), both will be included. This is the correct intuitive behaviour.

3. **No sprint**: If no sprint is active (e.g. between sprints), `openSprints()` returns an empty set and the query returns no issues. Workers will wait and retry via the normal `NO_ISSUES_WAIT` loop — no special handling required.

4. **No factory changes required**: The factory already propagates all env vars from `--env-file` into the container (Docker `--env-file` / ECS environment array). Users add `JIRA_CURRENT_SPRINT=true` to their existing env file and restart their workers.

5. **GitHub backend unaffected**: GitHub issues don't have a sprint concept; `task-manager/backends/github` is unchanged.
