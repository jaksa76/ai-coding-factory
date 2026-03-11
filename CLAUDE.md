# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Status

This project is complete and production-ready. The previous implementation is in `legacy/` for reference.
See `docs/ARCHITECTURE.md` for the full design and `docs/TESTING_STRATEGY.md` for how tests are structured and run.


## Repository layout

```
task-manager/   CLI tool — pluggable task management (bash, jira backend uses acli)
loop/           CLI tool — agent-agnostic work loop, implement, and plan scripts (bash)
worker-builder/ CLI tool — build worker images from a project devcontainer (bash)
factory/        CLI tool — start/stop/monitor worker containers (bash)

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI

planner/        Dockerfile: loop --for-planning + Claude CLI
plans/          Plan files generated during planning mode

legacy/         Previous hub-based implementation (reference only)
```


## Conventions

- All tools are bash scripts.
- Task management uses `task-manager`, a pluggable wrapper (default backend: `jira` via `acli`). (See `docs/acli.md` whenever interacting with Jira.)
- All tools read credentials from environment variables — no config files with secrets.
- `loop` shells out to `task-manager` for task operations; workers are thin Dockerfiles over `loop`.


## Environment variables

| Variable | Purpose |
|---|---|
| `TASK_MANAGER` | Task manager backend to use (default: `jira`) |
| `JIRA_SITE` | Jira host, e.g. `mycompany.atlassian.net` (jira backend) |
| `JIRA_EMAIL` | Jira account email (jira backend) |
| `JIRA_TOKEN` | Jira API token (jira backend) |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Jira account ID used for self-assignment (jira backend) |
| `JIRA_PROJECT` | Jira project key to pull issues from, e.g. `MYPROJ` (jira backend) |
| `GITHUB_ASSIGNEE` | GitHub username used for self-assignment (github backend) |
| `GH_TOKEN` | GitHub personal access token (github backend; also used by `workers/copilot`) |
| `GIT_REPO_URL` | Repository to work on |
| `GIT_USERNAME` | Git push credentials |
| `GIT_TOKEN` | Git push credentials |
| `PLAN_BY_DEFAULT` | Set to `true` to require a planning step for all issues |
| `FEATURE_BRANCHES` | Set to `true` to use feature branches for all issues |
| `NO_ISSUES_WAIT` | Seconds to wait when no issues are available (default: 60) |
| `INTER_ISSUE_WAIT` | Seconds to wait between issues (default: 1200; 300 in planning mode) |
| `IMPLEMENTATION_PROMPT` | Override the default implementation prompt sent to the agent |
| `PLANNING_PROMPT` | Override the default planning prompt sent to the agent |

Agent-specific vars (add on top of the above per worker type):

| Variable | Worker |
|---|---|
| `ANTHROPIC_API_KEY` | `workers/claude` |
| `GH_TOKEN` | `workers/copilot` |


## Testing

Make sure to have passing tests before pushing changes. Tests are in `.bats` files alongside the tools. See `docs/TESTING_STRATEGY.md` for details on how tests are structured and run. You can run an individual test with `bats <file>.bats -f <test name>`.

All tools have corresponding `.bats` test files. Run with `bats <file>`. We have 2 types of tests:
- Unit tests: test individual tools in isolation, using mocks for external dependencies (e.g. mock `acli` for Jira interactions).
- Integration tests: test the full flow of `loop` + worker, using real Jira interactions (against a test Jira instance) and real agent CLI calls.

**Mock external agent CLIs** (claude, copilot, etc.) in all integration tests except one final live smoke test. Create the mock binary inside the container at runtime (bind-mounting host files into Docker does not work from inside the devcontainer). Only the last test calls the real API, and it skips if `.env` is absent.

**Capture docker subprocess output** using detached mode: `docker run -d` → `docker wait` → `docker logs`. Foreground `docker run` does not reliably forward stdout from some binaries (e.g. the claude CLI) when they write after bash completes.

Always make sure to have passing tests.


## Code style

Implement the simplest solution that could possibly work.
Refactor agressively.
Keep the codebase decouplbed with well defined responsibilities.


## Working efficiently

**Time-box debugging.** If 3–4 attempts don't reveal the root cause, stop and reason from first principles before running more experiments.

**Trim tool output.** Pipe large command outputs through `| head -N` or redirect to files rather than dumping everything into the conversation context.

**Use `/compact`** when the conversation context grows large to reduce the cost of each subsequent request.