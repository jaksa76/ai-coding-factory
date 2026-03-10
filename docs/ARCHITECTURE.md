# Architecture

## Overview

Worker-based pull model where agents poll Jira directly for work. Jira is the single source of truth — no local task store.

```
[Jira] ← single source of truth
   ↓  workers poll for unassigned/open issues
[Worker pool: claude | copilot | codex | ...]
   ↓  push to trunk, post comments, transition status
[Jira + Git]

[manager CLI] ← start/stop/scale/logs via terminal
```

## Repository layout

```
claim/          CLI tool — claim Jira issues
loop/           CLI tool — agent-agnostic claim/work loop (implementation and planning modes)
worker-builder/ CLI tool — build worker Docker images from a project devcontainer
factory/        CLI tool — start/stop/scale/monitor worker containers

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI
  codex/        Dockerfile: loop + Codex CLI

planner/        Dockerfile: loop --for-planning + Claude CLI

legacy/         Previous hub-based implementation (reference only)
```

## `claim` — Tool for claiming Jira issues

A standalone CLI for interacting with Jira. Usable independently of the rest of the system.

```bash
claim --project MYPROJ --account-id <id>  # claim an issue by assigning it to self
```

Implemented as a bash script on top of `acli`, the Atlassian command line tool.
Reads `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN` from environment.

### Claim flow (optimistic locking via Jira)

```
  1. list available issues and pick one
  2. assign to self
  3. wait 10 seconds
  4. re-fetch issue, if assignee != self, goto 1
  5. transition to "In Progress"
  6. print issue details
```

## `loop` — Agent-agnostic work loop

A standalone CLI that implements the claim/work/report cycle. The agent to run is passed as an argument, making it work with any AI CLI tool. Pass `--for-planning` to run in planning mode instead of implementation mode.

```bash
loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p"
loop --project MYPROJ --agent "copilot -p"
loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p" --for-planning
```

### Implementation loop flow (default)

```
loop:
  1. claim --project $PROJECT --account-id $JIRA_ASSIGNEE_ACCOUNT_ID
  2. git pull / clone $GIT_REPO_URL
  3. invoke $AGENT with issue title + description as prompt
  4. git commit + push to trunk
  5. jira comment <issueKey> with summary
  6. jira transition <issueKey> "Done"
  goto 1
```

### Planning loop flow (--for-planning)

```
loop --for-planning:
  1. claim --for-planning --project $PROJECT --account-id $JIRA_ASSIGNEE_ACCOUNT_ID
  2. git pull / clone $GIT_REPO_URL
  3. invoke $AGENT: "Create a plan … save it in plans/<KEY>.md"
  4. git add plans/<KEY>.md + commit + push
  5. jira comment <issueKey> with GitHub blob URL for the plan file
  6. jira transition <issueKey> "Awaiting Plan Review"
  goto 1
```

`loop` shells out to `claim` for Jira operations and to `git` for repo operations.

### Environment variables

| Variable | Purpose |
|---|---|
| `TASK_MANAGER` | Backend: `jira` (default) or `github` |
| `JIRA_SITE` | Jira host, e.g. `mycompany.atlassian.net` (jira backend) |
| `JIRA_EMAIL` | Worker's Jira account email (jira backend) |
| `JIRA_TOKEN` | Jira API token (jira backend) |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Account ID used for self-assignment (jira backend) |
| `GITHUB_ASSIGNEE` | GitHub username for self-assignment (github backend) |
| `GH_TOKEN` | GitHub personal access token (github backend) |
| `GIT_REPO_URL` | Repository to work on |
| `GIT_USERNAME` | Push credentials |
| `GIT_TOKEN` | Push credentials |

### Git strategy

- Push directly to main initially.
- Feature branches and PRs to be introduced later.

## `worker-builder` — Worker image builder

A CLI tool that generates a project-specific worker Docker image by layering a chosen agent on top of the project's devcontainer. Workers run inside the same environment as the project's developers — same tools, same dependencies.

```bash
worker-builder --project <url> --agent claude
```

**Flow:**
1. Retrieve the project's `devcontainer.json` (using `git archive`).
2. Read `.devcontainer/devcontainer.json` to determine base image and setup commands
3. Generate a Dockerfile that extends the devcontainer base with:
   - The chosen agent CLI installed (`claude`, `gh copilot`, `codex`, …)
   - The `loop` and `jira` tools installed
4. Build (and optionally push) the image

## factory

A CLI for operating the worker pool. Talks directly to Docker, no server process.

```bash
factory status                           # list workers
factory add --image <img> -- count <n>   # start n workers with the given image
factory logs <worker-id>
factory logs --all
factory stop <worker-id>
factory stop --all
```

Reads config (Jira credentials, git URL, image name, etc.) from a local config file or env vars.

## Workers (`workers/`)

Predefined Dockerfiles for nodejs development. Each one installs a specific agent CLI on top of a base image, then sets `loop` as the entrypoint with the appropriate `--agent` flag. The heavy lifting is in `loop` and `jira`.

| Worker | Agent installed | Entrypoint |
|---|---|---|
| `workers/claude` | Anthropic Claude CLI | `loop --agent "claude ..."` |
| `workers/copilot` | GitHub Copilot CLI | `loop --agent "gh copilot ..."` |
| `workers/codex` | OpenAI Codex CLI | `loop --agent "codex ..."` |

For project-specific images, use `worker-builder` instead of these generic ones.

## Configuration

At the root of the project there is a `.env` file (not checked in) that contains all necessary environment variables for Jira, Git and Copilot authentication.

```bash
# credentials for Jira
export JIRA_SITE=
export JIRA_EMAIL=
export JIRA_TOKEN=

# credentials for the project repository
export GIT_REPO_URL=
export GIT_USERNAME=
export GIT_TOKEN=

# credentials for Github Copilot
export GH_USERNAME=
export GH_TOKEN=
```

## What this drops vs. the legacy hub

- No local task store (Jira is the store)
- No pipeline stages written to disk (Jira comments serve as the log)
- No Jira import step (workers read Jira directly)
- No background sync loop reconciling Docker ↔ file state
- No web server or browser UI

## Other notes
- All workers share the same Jira and Git credentials, read from environment variables. No per-worker authentication.
- All tools implemented as bash scripts

