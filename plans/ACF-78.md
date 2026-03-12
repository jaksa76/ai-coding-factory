# ACF-78: assessments: refactorings

## Summary

Add a `refactorings` subcommand to the `assess` script (defined in ACF-76). This subcommand invokes the agent to inspect the target project for design issues: overengineering, tight coupling, violations of the single responsibility principle, and poor readability. Opportunities for improvement are filed as proposed issues in the task management system, following the same pattern as all other `assess` subcommands.

**Depends on ACF-76**: `loop/assess` and `task-manager create` must exist before this can be implemented.

## Files to Change

| File | Change |
|---|---|
| `loop/assess` | Add `refactorings` case to the subcommand `case` block and update `usage()` |
| `loop/assess.bats` | Add tests for `refactorings` subcommand |

No other files need to change — agent invocation, issue creation, and transition are already handled by the `assess` script added in ACF-76.

## Implementation Steps

### 1. Add the `refactorings` subcommand to `loop/assess`

In the `case "$SUBCOMMAND"` block, add alongside the existing entries:

```bash
refactorings)   ASPECT="refactoring opportunities: design issues that make the codebase harder to understand, extend, or maintain.

Check for the following and flag specific files or components where they apply:
- Overengineering: unnecessary abstraction layers, premature generalisation, over-configured systems, helpers or utilities used only once, and features added for hypothetical future requirements
- Tight coupling: components that are hard to change independently, direct dependencies on concrete implementations instead of interfaces or thin wrappers, and shared mutable state between modules
- Single responsibility violations: functions or modules that do more than one distinct job, mixed concerns (e.g. business logic alongside I/O), and types or files that are too large because they own too many responsibilities
- Readability: unclear variable or function names, non-obvious logic without explanation, inconsistent formatting or conventions, and functions that are too long to understand at a glance

For each issue found, produce a concise, actionable issue with the specific location (file and function/section) and a suggested remedy." ;;
```

Also update the `usage()` function to list the new subcommand:

```bash
echo "  refactorings    Identify overengineering, coupling, SRP, and readability issues"
```

### 2. Add tests to `loop/assess.bats`

Add a test group for `refactorings` following the same patterns used for the other subcommands:

- **Routes correctly**: `assess refactorings --project PROJ` selects the right aspect text and calls the agent. Stub `agent` to write a minimal valid JSON array `[{"summary":"Tight coupling in parser","description":"Extract interface"}]` to `$ISSUES_FILE`; stub `task-manager create` to return `PROJ-1`; stub `task-manager transition` to succeed. Assert exit 0 and that `task-manager create` was called.
- **Transition fallback**: same setup but `task-manager transition` exits 1 — assert overall exit is still 0.
- **Empty result**: stub `agent` to write `[]` — assert 0 issues created, exit 0.

These tests follow the identical scaffolding already used for the other subcommands in `assess.bats`.

## Testing

```bash
bats loop/assess.bats
```

Run the `refactorings`-specific tests individually during development:

```bash
bats loop/assess.bats -f "refactorings"
```

For manual validation, run against a real project and verify issues appear in the task manager.

## Risks / Edge Cases

1. **ACF-76 dependency**: This ticket cannot be implemented until `loop/assess` exists. The change is a two-line addition to that file (one `case` entry + one `usage` line), so it can be merged into the ACF-76 PR or follow immediately after.

2. **Prompt specificity**: The `refactorings` aspect lists four distinct concerns. The agent may produce overlapping issues (e.g. a tight-coupling finding that is also a readability finding). This is acceptable — duplicates are cheap to close manually, and missing a real issue costs more than a false positive.

3. **Subjectivity**: Readability and overengineering judgements are inherently subjective. The prompt asks for specific locations (file + function) to anchor findings in concrete evidence rather than vague opinions, which reduces noise.

4. **No new plumbing needed**: The subcommand reuses all existing infrastructure (agent invocation, `$ISSUES_FILE`, `task-manager create`, transition). No new environment variables, no new external tools.

5. **Aspect text length**: The `refactorings` prompt enumerates four categories with examples. Keep total length under ~500 words to avoid agent context overhead — the current draft is within that budget.
