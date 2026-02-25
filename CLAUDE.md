# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This project is being built fresh. The previous implementation is in `legacy/` for reference.
See `ARCHITECTURE.md` for the full design and `TODO.md` for the ordered task list.

## Repository layout

```
claim/          CLI tool — claim a Jira issue (bash, uses acli)
loop/           CLI tool — agent-agnostic work loop (bash)
worker-builder/ CLI tool — build worker images from a project devcontainer (bash)
factory/        CLI tool — start/stop/monitor worker containers (bash)

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI
  codex/        Dockerfile: loop + Codex CLI

legacy/         Previous hub-based implementation (reference only)
```

## Conventions

- All tools are bash scripts.
- Jira operations use `acli` (Atlassian CLI).
- All tools read credentials from environment variables — no config files with secrets.
- `loop` shells out to `claim` for Jira operations; workers are thin Dockerfiles over `loop`.

## Environment variables

| Variable | Purpose |
|---|---|
| `JIRA_SITE` | Jira host, e.g. `mycompany.atlassian.net` |
| `JIRA_EMAIL` | Jira account email |
| `JIRA_TOKEN` | Jira API token |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | Jira account ID used for self-assignment |
| `GIT_REPO_URL` | Repository to work on |
| `GIT_USERNAME` | Git push credentials |
| `GIT_TOKEN` | Git push credentials |

Agent-specific vars (add on top of the above per worker type):

| Variable | Worker |
|---|---|
| `ANTHROPIC_API_KEY` | `workers/claude` |
| `GH_TOKEN` | `workers/copilot` |
| `OPENAI_API_KEY` | `workers/codex` |
