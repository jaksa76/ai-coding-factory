# AI Coding Factory

Autonomous AI agents that pull Jira issues, implement them, and push code — continuously. Inspired by [AI Coding Factories](https://jaksa.wordpress.com/2025/08/07/ai-coding-factories/).

## How it works

Workers poll Jira for unassigned issues, claim one, clone the repo, invoke an AI agent to implement it, commit and push the result, then loop back for the next issue. Jira is the single source of truth — no local task store.

```
[Jira] ← issues queue
   ↓  workers poll for unassigned open issues
[Worker pool: claude | copilot | codex | ...]
   ↓  push to trunk, post comments, transition status
[Jira + Git]
```

## Prerequisites

- Docker (for running workers)
- A Jira project with issues to work on
- A Git repository for the codebase

## Configuration

### Configure Jira

Set these environment variables with your Jira credentials and project info:

```bash
export JIRA_SITE=mycompany.atlassian.net
export JIRA_EMAIL=worker@mycompany.com
export JIRA_TOKEN=<jira-api-token>
export JIRA_ASSIGNEE_ACCOUNT_ID=<jira-account-id>
export JIRA_PROJECT=MYPROJ
```

### Configure Git

You need to give the workers push access to the repository. The simplest way is to create a machine user with a personal access token and use those credentials:

```bash
export GIT_REPO_URL=https://github.com/myorg/myrepo.git
export GIT_USERNAME=myuser
export GIT_TOKEN=<github-pat>
```

### Configure AI agent

If you are using Claude Code with a Claude subscription, set the access token:
```bash
CLAUDE_ACCESS_TOKEN=<your-claude-access-token>
CLAUDE_REFRESH_TOKEN=<your-claude-refresh-token>
CLAUDE_TOKEN_EXPIRES_AT=<timestamp>
CLAUDE_SUBSCRIPTION_TYPE=<pro|pro-plus>
```
you can get all these values from `~/.claude/.credentials.json` after logging in with `claude login`.

If you are using a prepaid Anthropic API key, set it like this:

```bash
export ANTHROPIC_API_KEY=<your-api-key>   # for Claude workers
```

notice that if you have a subscription, you must use the `CLAUDE_ACCESS_TOKEN` method instead of `ANTHROPIC_API_KEY`, as the latter will use a different authentication flow that does not support the features of a subscription.

if you are using GitHub Copilot, set the token:

```bash
export GH_TOKEN=<your-github-token>   # for Copilot workers
export GH_USERNAME=<your-github-username>   # for Copilot workers
```


## Running

```bash
factory add --image worker-claude 1
```

This will start a single worker using Claude Code. You can start multiple workers or use different images for different agents.

You can monitor the workers with:

```bash
factory status              # list running workers
factory logs <worker-id>    # stream a worker's output
factory stop --all          # stop all workers
```

---

## Planning

If your workflow requires a planning step, use `planner-loop` to generate plans for issues before implementation. Planners create `plans/<ISSUE-KEY>.md` in the repo, which are reviewed by humans. Once approved, the regular `loop` picks them up for implementation.

---

## Tools

### `claim` — Claim a Jira issue

A standalone CLI that finds an unassigned open issue and claims it for a given account.

```bash
claim --project MYPROJ --account-id <jira-account-id>
```

Uses optimistic locking: assigns the issue, waits 10 seconds, re-checks the assignee. If another worker grabbed it in the meantime, retries with the next issue. Exits with code 2 when no issues are available.

**Options:**

| Flag | Description |
|---|---|
| `--project <key>` | Jira project key |
| `--account-id <id>` | Jira account ID to assign to |
| `--for-planning` | Claim issues requiring a planning step (transitions to Planning instead of In Progress) |

**Required environment variables:** `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN`

---

### `loop` — Agent-agnostic work loop

Implements the full claim → implement → push → report cycle. Pass any AI CLI as the `--agent`.

```bash
loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p"
loop --project MYPROJ --agent "codex -q"
```

**Options:**

| Flag | Description |
|---|---|
| `--project <key>` | Jira project key |
| `--agent <command>` | AI CLI command to invoke with the issue prompt |

**Required environment variables:**

| Variable | Purpose |
|---|---|
| `JIRA_SITE` | Jira host |
| `JIRA_EMAIL` | Jira account email |
| `JIRA_TOKEN` | Jira API token |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Account ID for self-assignment |
| `GIT_REPO_URL` | Repository to work on |
| `GIT_USERNAME` | Git push credentials |
| `GIT_TOKEN` | Git push credentials |

**Optional environment variables:**

| Variable | Default | Description |
|---|---|---|
| `NO_ISSUES_WAIT` | 60 | Seconds to wait when no issues are available before polling again |
| `RATE_LIMIT_WAIT` | 60 | Seconds to wait on agent rate limit errors |
| `INTER_ISSUE_WAIT` | 1200 | Seconds to wait between completing one issue and claiming the next |
| `FEATURE_BRANCHES` | false | Push to feature branches and open PRs instead of committing to trunk |
| `PLAN_BY_DEFAULT` | false | Require planning phase for all issues by default |

**Loop flow:**

1. Claim an unassigned issue from Jira
2. Clone or pull the repository
3. Invoke the agent with the issue title and description as the prompt
4. Commit and push changes
5. Comment on the Jira issue and transition it to Done
6. Sleep `INTER_ISSUE_WAIT` seconds, then repeat

**Feature branches** (opt-in via `FEATURE_BRANCHES=true` or `needs-branch` Jira label):

Instead of pushing to trunk, the loop creates `feature/<ISSUE-KEY>`, pushes it, opens a GitHub PR, comments the PR link on Jira, and transitions the issue to In Review.

---

### `planner-loop` — Planning phase loop

A companion to `loop` for a two-phase workflow. Planner workers generate implementation plans; implementation workers pick up approved plans.

```bash
planner-loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p"
```

The agent writes `plans/<ISSUE-KEY>.md` to the repository, the plan is committed and pushed, and the issue transitions to Awaiting Plan Review. When a human approves the plan (transitions to Plan Approved), the regular `loop` picks it up and implements according to the plan.

To require planning for specific issues, add the `needs-plan` Jira label. To require planning for all issues by default, set `PLAN_BY_DEFAULT=true`. Individual issues can opt out with the `skip-plan` label.

---

### `worker-builder` — Build worker images

Generates a project-specific Docker image by layering an AI agent on top of your project's devcontainer.

```bash
worker-builder build \
  --devcontainer .devcontainer/devcontainer.json \
  --type claude \
  --tag myproject-worker:latest \
  [--push]
```

**Options:**

| Flag | Description |
|---|---|
| `--devcontainer <path>` | Path to your project's `devcontainer.json` |
| `--type <claude\|copilot\|codex>` | Agent to install |
| `--tag <tag>` | Docker image tag (default: `worker-<type>:latest`) |
| `--push` | Push the image after building |

The generated image uses your devcontainer's base image so workers run in the same environment as your developers — same tools, same dependencies.

---

### `factory` — Manage worker containers

Controls the worker pool via Docker. No server process required.

```bash
factory status                             # list running workers
factory add --image <img> <count>          # start N workers
factory logs <worker-id>                   # stream a worker's logs
factory stop <worker-id>                   # stop one worker
factory stop --all                         # stop all workers
```

Workers are identified by the Docker label `ai-coding-factory.worker=true` and named `factory-worker-<timestamp>-<n>`. They restart automatically on failure (`--restart=on-failure`).

Pass extra Docker arguments after `--`:

```bash
factory add --image my-worker:latest 2 -- --env-file .env
```

---

## Workers

Pre-built Dockerfiles for common agents are in `workers/`. Each installs an agent CLI and sets `loop` as the entrypoint.

| Worker | Agent | Image location |
|---|---|---|
| `workers/claude` | Claude Code CLI | `workers/claude/Dockerfile` |
| `workers/copilot` | GitHub Copilot CLI | `workers/copilot/Dockerfile` |
| `workers/codex` | OpenAI Codex CLI | `workers/codex/Dockerfile` |

For project-specific images (matching your devcontainer), use `worker-builder` instead.

**Agent-specific environment variables:**

| Variable | Worker |
|---|---|
| `ANTHROPIC_API_KEY` | `workers/claude` |
| `GH_TOKEN` | `workers/copilot` |
| `OPENAI_API_KEY` | `workers/codex` |

---

## Environment variable reference

| Variable | Required | Description |
|---|---|---|
| `JIRA_SITE` | Yes | Jira host, e.g. `mycompany.atlassian.net` |
| `JIRA_EMAIL` | Yes | Jira account email |
| `JIRA_TOKEN` | Yes | Jira API token |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Yes | Jira account ID for self-assignment |
| `JIRA_PROJECT` | Yes | Jira project key, e.g. `MYPROJ` |
| `GIT_REPO_URL` | Yes | Repository URL to work on |
| `GIT_USERNAME` | Yes | Git push credentials (username) |
| `GIT_TOKEN` | Yes | Git push credentials (token/PAT) |
| `ANTHROPIC_API_KEY` | Claude only | API key for Claude |
| `GH_TOKEN` | Copilot only | GitHub token for Copilot |
| `OPENAI_API_KEY` | Codex only | API key for OpenAI Codex |
| `FEATURE_BRANCHES` | No | `true` to use feature branches + PRs |
| `PLAN_BY_DEFAULT` | No | `true` to require planning for all issues |
| `NO_ISSUES_WAIT` | No | Poll interval when queue is empty (default: 60s) |
| `RATE_LIMIT_WAIT` | No | Wait time on agent rate limit (default: 60s) |
| `INTER_ISSUE_WAIT` | No | Pause between issues (default: 1200s) |

---

## Jira workflow

The default flow requires these Jira statuses: **Open** → **In Progress** → **Done**

Optional statuses for the planning phase: **Planning** → **Awaiting Plan Review** → **Plan Approved** → **In Progress** → **Done**

Optional status for the feature branch flow: **In Review**

The tools warn and continue gracefully if optional statuses are absent from the workflow.

**Jira labels:**

| Label | Effect |
|---|---|
| `needs-plan` | Issue requires a planning step before implementation |
| `skip-plan` | Issue skips planning even when `PLAN_BY_DEFAULT=true` |
| `needs-branch` | Issue uses feature branch flow regardless of `FEATURE_BRANCHES` |
| `skip-branch` | Issue skips feature branch flow even when `FEATURE_BRANCHES=true` |
