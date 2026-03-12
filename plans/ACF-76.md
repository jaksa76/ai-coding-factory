# ACF-76: assess script

## Summary

Add a new `assess` script to `loop/` that invokes the agent CLI to analyse the project codebase and files proposed issues in the task management system. The script accepts a subcommand (`code-quality`, `security`, `testing`, `technical-debt`, `dependencies`) to focus the analysis. Each assessment run produces a JSON list of issues (written by the agent to a temp file), which the script then creates via a new `task-manager create` subcommand and attempts to transition to "Proposed" status (gracefully skipping if that status does not exist).

## Files to Change

| File | Change |
|---|---|
| `loop/assess` | **New** — main assess script |
| `task-manager/task-manager` | Add `create` subcommand dispatch + usage docs |
| `task-manager/backends/jira` | Add `tm_create()` via `acli jira workitem create` |
| `task-manager/backends/github` | Add `tm_create()` via `gh issue create` |
| `task-manager/backends/todo` | Add `tm_create()` appending a new checkbox line |
| `setup.sh` | Add `assess` entry to `setup_bin` entries array |
| `workers/claude/Dockerfile` | Add `COPY loop/assess` + `chmod` line |
| `workers/copilot/Dockerfile` | Same |
| `worker-builder/worker-builder` | Add `assess` to the generated `COPY`/`chmod` lines |
| `loop/assess.bats` | **New** — unit tests |
| `task-manager/task-manager.bats` | Add tests for `create` subcommand dispatch |
| `task-manager/backends/jira.bats` | Add tests for `tm_create()` |
| `task-manager/backends/github.bats` | Add tests for `tm_create()` |
| `task-manager/backends/todo.bats` | Add tests for `tm_create()` |

## Implementation Steps

### 1. Add `tm_create()` to the Jira backend (`task-manager/backends/jira`)

```bash
tm_create() {
    local project="" summary="" description=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)     project="$2";     shift 2 ;;
            --summary)     summary="$2";     shift 2 ;;
            --description) description="$2"; shift 2 ;;
            *) echo "Error: unknown option: $1" >&2; exit 1 ;;
        esac
    done
    [[ -z "$project" ]] && { echo "Error: --project <key> is required" >&2; exit 1; }
    [[ -z "$summary" ]] && { echo "Error: --summary <text> is required" >&2; exit 1; }

    tm_auth

    acli jira workitem create \
        --project "$project" \
        --summary "$summary" \
        --description "${description:-}" \
        --type Story \
        --yes \
        --json \
        | jq -r '.key'
}
```

> **Risk**: Run `acli jira workitem create --help` first to confirm exact flag names (`--type`, `--yes`, JSON output shape). Adjust if needed.

### 2. Add `tm_create()` to the GitHub backend (`task-manager/backends/github`)

```bash
tm_create() {
    local project="" summary="" description=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)     project="$2";     shift 2 ;;
            --summary)     summary="$2";     shift 2 ;;
            --description) description="$2"; shift 2 ;;
            *) echo "Error: unknown option: $1" >&2; exit 1 ;;
        esac
    done
    [[ -z "$project" ]] && { echo "Error: --project <key> is required" >&2; exit 1; }
    [[ -z "$summary" ]] && { echo "Error: --summary <text> is required" >&2; exit 1; }

    gh issue create \
        --repo "$project" \
        --title "$summary" \
        --body "${description:-}" \
        --json number \
        --jq '.number'
}
```

### 3. Add `tm_create()` to the TODO backend (`task-manager/backends/todo`)

```bash
tm_create() {
    local file="" summary="" description=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)     file="$2";        shift 2 ;;
            --summary)     summary="$2";     shift 2 ;;
            --description) description="$2"; shift 2 ;;
            *) echo "Error: unknown option: $1" >&2; exit 1 ;;
        esac
    done
    [[ -z "$file" ]]    && { echo "Error: --project <path> is required" >&2; exit 1; }
    [[ -z "$summary" ]] && { echo "Error: --summary <text> is required" >&2; exit 1; }
    [[ ! -f "$file" ]]  && { echo "Error: TODO file not found: $file" >&2; exit 1; }

    export TODO_FILE="$file"
    echo "- [ ] $summary" >> "$file"
    local lineno
    lineno=$(wc -l < "$file")
    echo "TODO-${lineno}"
}
```

"Proposed" is not in the TODO backend's status list, so the assess script's graceful fallback handles it automatically.

### 4. Add `create` case to `task-manager/task-manager`

In the `usage()` function add:
```
  create --project <key> --summary <text> [--description <text>]
                                            Create a new issue; prints its key
```

In the `case` dispatch add:
```bash
create) tm_create "$@" ;;
```

### 5. Create `loop/assess`

```bash
#!/usr/bin/env bash
set -euo pipefail

# assess — analyse the project and file proposed issues
#
# Usage:
#   assess <subcommand> --project <key>
#
# Subcommands:
#   code-quality    Analyse code quality issues
#   security        Analyse security vulnerabilities
#   testing         Analyse testing gaps
#   technical-debt  Analyse technical debt
#   dependencies    Analyse outdated/vulnerable dependencies
#
# Environment variables required: same as loop (git vars + task-manager backend vars)

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"

usage() {
    echo "Usage: assess <subcommand> --project <key>"
    echo ""
    echo "Subcommands:"
    echo "  code-quality    Analyse code quality"
    echo "  security        Analyse security issues"
    echo "  testing         Analyse testing gaps"
    echo "  technical-debt  Analyse technical debt"
    echo "  dependencies    Analyse dependencies"
    exit 1
}

[[ $# -lt 1 ]] && usage

SUBCOMMAND="$1"; shift

PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project <key> is required" >&2; exit 1; }

case "$SUBCOMMAND" in
    code-quality)   ASPECT="code quality: code smells, duplication, overly complex functions, poor naming, and maintainability issues" ;;
    security)       ASPECT="security: vulnerabilities, unsafe practices, hardcoded secrets, injection risks, and missing input validation" ;;
    testing)        ASPECT="testing: untested code paths, missing edge case coverage, flaky test patterns, and test gaps" ;;
    technical-debt) ASPECT="technical debt: TODO/FIXME comments, deprecated API usage, outdated patterns, and architectural issues" ;;
    dependencies)   ASPECT="dependencies: outdated packages, known vulnerabilities, unnecessary dependencies, and version conflicts" ;;
    --help|-h)      usage ;;
    *)              echo "Error: unknown subcommand: '$SUBCOMMAND'" >&2; usage ;;
esac

setup_git_credentials
configure_git_identity
derive_work_dir
clone_or_pull

ISSUES_FILE="$(mktemp --suffix=.json)"
trap 'rm -f "$ISSUES_FILE"' EXIT

PROMPT="Analyse this codebase for ${ASPECT}.

Identify the top issues (aim for 3–10 specific, actionable items).

Write a JSON array to ${ISSUES_FILE}. Each element must have exactly two keys:
  - summary: a concise one-line title (max 120 chars)
  - description: a clear explanation of the issue and a suggested fix

Write ONLY the JSON array to ${ISSUES_FILE} — no other output to that file."

echo "Running ${SUBCOMMAND} assessment..." >&2
(cd "$WORK_DIR" && agent run "$PROMPT")

if [[ ! -s "$ISSUES_FILE" ]]; then
    echo "Error: agent produced no issues file at $ISSUES_FILE" >&2
    exit 1
fi

created=0
while IFS= read -r item; do
    summary=$(printf '%s' "$item" | jq -r '.summary')
    description=$(printf '%s' "$item" | jq -r '.description')

    key=$(task-manager create \
        --project "$PROJECT" \
        --summary "$summary" \
        --description "$description")

    echo "Created $key: $summary" >&2

    task-manager transition "$key" --status "Proposed" 2>/dev/null \
        || echo "Note: could not transition $key to Proposed — status may not exist" >&2

    created=$((created + 1))
done < <(jq -c '.[]' "$ISSUES_FILE")

echo "Assessment complete: $created issue(s) created." >&2
```

### 6. Update `setup.sh` — add `assess` to `setup_bin`

In `setup_bin()`, add `"assess:$REPO_DIR/loop/assess"` to the `entries` array alongside `plan`.

### 7. Update worker Dockerfiles

In `workers/claude/Dockerfile` and `workers/copilot/Dockerfile`, after the existing `COPY loop/plan` line add:
```dockerfile
COPY loop/assess /usr/local/bin/assess
```
And extend the `chmod` line to include `assess`.

### 8. Update `worker-builder/worker-builder`

In the generated Dockerfile section (around line 178), add:
```bash
printf 'COPY loop/assess /usr/local/bin/assess\n'
```
And extend the `chmod` line to include `/usr/local/bin/assess`.

### 9. Write tests (`loop/assess.bats`)

Cover:
- No args → usage/exit 1
- Unknown subcommand → exit 1
- Missing `--project` → exit 1
- Successful run: stubs `agent` (writes valid JSON to `$ISSUES_FILE`), stubs `task-manager create` (returns `PROJ-1`), stubs `task-manager transition` (exits 0) — assert `task-manager create` called with correct args and exit 0
- Transition fallback: stubs `task-manager transition` to exit 1 — assert overall exit still 0
- Empty issues file (agent writes `[]`) — assert 0 issues created, exit 0
- Agent produces no file — assert exit 1

Also add `tm_create` unit tests to the relevant `backends/*.bats` files and a dispatch test to `task-manager.bats`.

## Testing

```bash
# Unit tests
bats loop/assess.bats
bats task-manager/task-manager.bats
bats task-manager/backends/jira.bats
bats task-manager/backends/github.bats
bats task-manager/backends/todo.bats
```

For integration testing, run `assess` manually against a real project with a live task-manager backend and verify issues appear in the "Proposed" column (or default status if absent).

## Risks / Edge Cases

1. **`acli jira workitem create` flags**: The exact CLI flags (`--type`, `--yes`, JSON output key for the new issue key) must be confirmed with `acli jira workitem create --help` before implementation. The `--type Story` may need to be omitted or changed if the project has custom issue types.

2. **Agent output format**: The agent may produce text around or instead of the JSON array. To guard against this, the assess script validates that `$ISSUES_FILE` is non-empty and parseable with `jq -c '.[]'`. If the agent embeds the JSON in prose, parsing will fail — the prompt must be explicit. Consider wrapping the `jq` call in error handling to print a clear message.

3. **"Proposed" status availability**: The transition is best-effort. If the status does not exist the script warns and continues, so issues are always created regardless of status. The TODO backend has no "Proposed" state; this is already handled.

4. **GitHub `gh issue create` output**: `gh issue create` prints the issue URL to stdout by default. The `--json number --jq '.number'` flags used here return the number, which is then used as the issue key. Confirm this works with the installed `gh` version.

5. **Description length limits**: Jira and GitHub have content limits. Very long agent-generated descriptions may need truncation. For now, rely on the prompt's guidance ("concise") and add truncation if issues arise in practice.

6. **`assess` not in planner**: The `planner/Dockerfile` does not need `assess` since it only runs the plan loop. Do not add it there.

7. **Parallelism / rate limiting**: Creating many issues in rapid succession may hit Jira/GitHub API rate limits. The simple sequential loop is fine for the expected batch size (3–10 issues); add retry logic only if it becomes a real problem.
