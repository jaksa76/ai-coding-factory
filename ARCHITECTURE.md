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
jira/           CLI tool — query, claim, transition, and comment on Jira issues
loop/           CLI tool — agent-agnostic claim/work loop
worker-builder/ CLI tool — build worker Docker images from a project devcontainer
manager/        CLI tool — start/stop/scale/monitor worker containers

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI
  codex/        Dockerfile: loop + Codex CLI

legacy/         Previous hub-based implementation (reference only)
```

## `jira` — Jira CLI tool

A standalone CLI for interacting with Jira. Usable independently of the rest of the system.

```bash
jira issues --project MYPROJ --status "To Do" --unassigned
jira assign MYPROJ-42 --account-id <id>
jira get MYPROJ-42
jira transition MYPROJ-42 --to "In Progress"
jira comment MYPROJ-42 --body "Implemented in commit abc123"
```

Reads `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN` from environment.

## `loop` — Agent-agnostic work loop

A standalone CLI that implements the claim/work/report cycle. The agent to run is passed as an argument, making it work with any AI CLI tool.

```bash
loop --project MYPROJ --agent "claude --dangerously-skip-permissions -p"
loop --project MYPROJ --agent "gh copilot suggest -t shell"
```

### Claim flow (optimistic locking via Jira)

```
loop:
  1. jira issues --project $PROJECT --unassigned → pick one
  2. jira assign <issueKey>
  3. wait 10 seconds
  4. jira get <issueKey> — if assignee != self, goto 1
  5. jira transition <issueKey> "In Progress"
  6. git pull / clone $GIT_REPO_URL
  7. invoke $AGENT with issue title + description as prompt
  8. git commit + push to trunk
  9. jira comment <issueKey> with summary
  10. jira transition <issueKey> "Done"
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
| `GIT_TOKEN` | Push credentials |

### Git strategy

- Push directly to trunk (main/master) initially.
- Feature branches and PRs to be introduced later.

## `worker-builder` — Worker image builder

A CLI tool that generates a project-specific worker Docker image by layering a chosen agent on top of the project's devcontainer. Workers run inside the same environment as the project's developers — same tools, same dependencies.

```bash
worker-builder \
  --devcontainer ./path/to/project/.devcontainer \
  --type claude \
  --tag myorg/myproject-worker:latest
```

**Flow:**
1. Read `.devcontainer/devcontainer.json` to determine base image and setup commands
2. Generate a Dockerfile that extends the devcontainer base with:
   - The chosen agent CLI installed (`claude`, `gh copilot`, `codex`, …)
   - The `loop` and `jira` tools installed
3. Build (and optionally push) the image

## `manager` — Worker pool CLI

A CLI for operating the worker pool. Talks directly to Docker, no server process.

```bash
manager start --image myorg/myproject-worker:latest --type claude --count 3
manager stop <worker-id>
manager stop --all
manager scale --type claude --count 5
manager status                 # list workers + current Jira ticket
manager logs <worker-id>
manager logs --all
```

Reads config (Jira credentials, git URL, image name, etc.) from a local config file or env vars.

## Workers (`workers/`)

Thin Dockerfiles. Each one installs a specific agent CLI on top of a base image, then sets `loop` as the entrypoint with the appropriate `--agent` flag. The heavy lifting is in `loop` and `jira`.

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

## Open questions

- Should all workers share one Jira account, or have individual accounts? Individual accounts make the assignee field meaningful but require more Jira setup.
- Automatic recovery for crashed/stuck "In Progress" tickets (e.g. requeue after N minutes with no heartbeat).
- When to introduce feature branches and PRs instead of pushing to trunk.
- Config file format for `manager` and `loop` (TOML / YAML / `.env`?).
- Implementation language for the CLI tools (shell scripts, Node.js, Python, Go?).
