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
loop/           CLI tool — agent-agnostic claim/work loop
worker-builder/ CLI tool — build worker Docker images from a project devcontainer
factory/        CLI tool — start/stop/scale/monitor worker containers

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI
  codex/        Dockerfile: loop + Codex CLI

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

A standalone CLI that implements the claim/work/report cycle. The agent to run is passed as an argument, making it work with any AI CLI tool.

```bash
loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p"
loop --project MYPROJ --agent "copilot -p"
```

### Loop flow

```
loop:
  1. jira pick --project $PROJECT --account-id $JIRA_ASSIGNEE_ACCOUNT_ID
  2. git pull / clone $GIT_REPO_URL
  3. invoke $AGENT with issue title + description as prompt
  4. git commit + push to trunk
  5. jira comment <issueKey> with summary
  6. jira transition <issueKey> "Done"
  goto 1
```

`loop` shells out to `jira` for all Jira operations and to `git` for repo operations.

### Environment variables

| Variable | Purpose |
|---|---|
| `JIRA_SITE` | Jira host, e.g. `mycompany.atlassian.net` |
| `JIRA_EMAIL` | Worker's Jira account email |
| `JIRA_TOKEN` | Jira API token |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Account ID used for self-assignment |
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

## What this drops vs. the legacy hub

- No local task store (Jira is the store)
- No pipeline stages written to disk (Jira comments serve as the log)
- No Jira import step (workers read Jira directly)
- No background sync loop reconciling Docker ↔ file state
- No web server or browser UI

## Other notes
- All workers share the same Jira and Git credentials, read from environment variables. No per-worker authentication.
- All tools implemented as bash scripts

