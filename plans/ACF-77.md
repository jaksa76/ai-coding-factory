# ACF-77: assessments: project setup

## Summary

Add a `project-setup` subcommand to the `assess` script (defined in ACF-76). This subcommand invokes the agent to inspect the target project for the prerequisites that improve an AI agent's working experience: documentation, instruction files, build scripts, build/test instructions, test types (unit, integration, e2e, UI), and static analysis configuration. Missing or inadequate items are filed as proposed issues in the task management system, following the same pattern as the other `assess` subcommands.

**Depends on ACF-76**: `loop/assess` and `task-manager create` must exist before this can be implemented.

## Files to Change

| File | Change |
|---|---|
| `loop/assess` | Add `project-setup` case to the subcommand `case` block with its `ASPECT` prompt |
| `loop/assess.bats` | Add tests for `project-setup` subcommand |

No other files need to change — the plumbing (agent invocation, issue creation, transition) is already handled by the `assess` script added in ACF-76.

## Implementation Steps

### 1. Add the `project-setup` subcommand to `loop/assess`

In the `case "$SUBCOMMAND"` block, add a new entry alongside the existing ones:

```bash
project-setup)  ASPECT="project setup: missing or inadequate prerequisites that reduce an AI agent's effectiveness when working in this codebase.

Check for the following and flag anything absent or insufficient:
- Documentation: README, architecture docs, ADRs, API docs, or equivalent
- Agent instruction files: CLAUDE.md, AGENTS.md, .cursorrules, Copilot instructions, or any file that guides an AI assistant
- Build scripts or equivalent: Makefile, package.json scripts, justfile, taskfile, shell scripts, or CI configuration that shows how to build the project
- Build and test instructions: clear, runnable steps for building and running the test suite (in a README, CONTRIBUTING, or similar)
- Test types present: unit, integration, end-to-end, and UI tests where applicable to the project's stack
- Static analysis: linter configuration, type-checker setup, formatter config, or security scanner integration

For each gap found, produce a concise, actionable issue with a suggested remedy." ;;
```

Also update the `usage()` function to list the new subcommand:

```bash
echo "  project-setup   Check project prerequisites for agent effectiveness"
```

### 2. Add tests to `loop/assess.bats`

Add a test group for `project-setup` following the same patterns used for the other subcommands:

- **Routes correctly**: `assess project-setup --project PROJ` selects the right aspect text and calls the agent. Stub `agent` to write a minimal valid JSON array `[{"summary":"Missing CLAUDE.md","description":"Add a CLAUDE.md"}]` to `$ISSUES_FILE`; stub `task-manager create` to return `PROJ-1`; stub `task-manager transition` to succeed. Assert exit 0 and that `task-manager create` was called.
- **Transition fallback**: same setup but `task-manager transition` exits 1 — assert overall exit is still 0.
- **Empty result**: stub `agent` to write `[]` — assert 0 issues created, exit 0.

These tests follow the identical scaffolding already planned for the other subcommands in `assess.bats`.

## Testing

```bash
bats loop/assess.bats
```

Run the `project-setup`-specific tests individually during development:

```bash
bats loop/assess.bats -f "project-setup"
```

For manual validation, run against a real project that is missing some prerequisites and verify issues appear in the task manager.

## Risks / Edge Cases

1. **ACF-76 dependency**: This ticket cannot be implemented until `loop/assess` exists. The change is a one-liner addition to that file, so it can be merged into the ACF-76 PR or follow immediately after.

2. **Prompt specificity vs. false positives**: The agent may flag optional items (e.g., UI tests for a CLI-only project) as missing. The prompt uses "where applicable to the project's stack" to mitigate this, but some tuning may be needed after first runs.

3. **Instruction file naming variety**: Agent instruction files have no standard name (CLAUDE.md, AGENTS.md, .cursorrules, etc.). The prompt lists known names; new conventions may need to be added over time as the ecosystem evolves.

4. **No new plumbing needed**: The subcommand reuses all existing infrastructure (agent invocation, `$ISSUES_FILE`, `task-manager create`, transition). No new environment variables, no new external tools.

5. **Aspect text length**: The `project-setup` aspect prompt is longer than the others because it enumerates specific checks. This is intentional — the more specific the prompt, the more actionable the output. Keep it under ~500 words to avoid agent context overhead.
