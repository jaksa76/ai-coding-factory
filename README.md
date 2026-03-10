# AI Coding Factory

Autonomous AI agents that pull issues from a task manager, implement them, and push code — continuously. Inspired by [AI Coding Factories](https://jaksa.wordpress.com/2025/08/07/ai-coding-factories/).

## How it works

Workers poll a task manager for unassigned issues, claim one, clone the repo, invoke an AI agent to implement it, commit and push the result, then loop back for the next issue. The task manager is the single source of truth — no local task store.

The task management backend is pluggable via the `TASK_MANAGER` environment variable (default: `jira`).

```
[Jira] ← issues queue
   ↓  workers poll for unassigned open issues
[Worker pool: claude | copilot | codex | ...]
   ↓  push to trunk, post comments, transition status
[Jira + Git]
```

## Installation

Clone the repository and run the setup script:

```bash
git clone https://github.com/jaksa76/ai-coding-factory.git
cd ai-coding-factory
./setup.sh
```

`setup.sh` will:
1. Check prerequisites (`docker`, `git`)
2. Ask which AI agent you want to use (claude, copilot, ...)
3. Create symlinks in `bin/` for all tools (`loop`, `factory`, `task-manager`, `worker-builder`, `agent`)
4. Add `bin/` to your `PATH` in your shell config
5. Collect your credentials and write them to an env file (e.g. `.env.factory`)

Re-run `setup.sh` at any time to update credentials or change the agent.

## Configuration

All configuration is passed via environment variables. `setup.sh` writes these to an env file for you, but you can also set them manually.

### Task manager

The default backend is `jira`. Provide your Jira credentials:

```bash
export TASK_MANAGER=jira   # optional, jira is the default
export JIRA_SITE=mycompany.atlassian.net
export JIRA_EMAIL=worker@mycompany.com
export JIRA_TOKEN=<jira-api-token>
export JIRA_ASSIGNEE_ACCOUNT_ID=<jira-account-id>
export JIRA_PROJECT=MYPROJ
```

For GitHub Issues, use:

```bash
export TASK_MANAGER=github
export GITHUB_ASSIGNEE=myuser
export GH_TOKEN=<github-pat>
```

### Git

```bash
export GIT_REPO_URL=https://github.com/myorg/myrepo.git
export GIT_USERNAME=myuser
export GIT_TOKEN=<github-pat>
```

### AI agent

**Claude (API key):**
```bash
export ANTHROPIC_API_KEY=<your-api-key>
```

**Claude (subscription):** log in with `claude login` first, then import your credentials (see below). Or set them manually from `~/.claude/.credentials.json`:
```bash
export CLAUDE_ACCESS_TOKEN=<access-token>
export CLAUDE_REFRESH_TOKEN=<refresh-token>
export CLAUDE_TOKEN_EXPIRES_AT=<timestamp>
export CLAUDE_SUBSCRIPTION_TYPE=pro
```

**GitHub Copilot:**
```bash
export GH_TOKEN=<your-github-token>
export GH_USERNAME=<your-github-username>
```

## Running

There are three ways to run workers: directly, via Docker, or via the factory.

### Directly

Run the `loop` script directly on your machine (no Docker required):

```bash
loop --project MYPROJ
```

This uses whatever `agent` script is on your `PATH` (set by `setup.sh`) and the environment variables in your current shell. Useful for development and testing.

### Via Docker

Build a worker image and run it with your env file:

```bash
docker build -f workers/claude/Dockerfile -t worker-claude .
docker run --env-file .env.factory worker-claude
```

### Via the factory (multiple workers)

Use `factory` to manage multiple Docker workers at once:

```bash
factory workers                          # start 1 implementation worker
factory workers 3                        # start 3 implementation workers
factory workers --env-file .env.factory  # pass credentials to workers
```

This uses the `worker-claude` image by default. Override with `FACTORY_WORKER_IMAGE=<image>`.

You can also set the env file globally:

```bash
export FACTORY_ENV_FILE=.env.factory
factory workers 3
```

Monitor and control workers:

```bash
factory status              # list running workers
factory logs <worker-id>    # stream a worker's output
factory stop <worker-id>    # stop a specific worker
factory stop --all          # stop all workers
```

For lower-level control (e.g. a specific image):

```bash
factory add --image worker-copilot 2
```

### Importing Claude credentials

If you use a Claude subscription, OAuth tokens expire periodically. After running `claude login` to refresh them, import the new credentials into your env file with:

```bash
factory import-claude-credentials --env-file .env.factory
```

This reads `~/.claude/.credentials.json` and updates the `CLAUDE_*` variables in your env file in place.

---

## Planning

If your workflow requires a planning step before implementation, run planner workers alongside your regular workers. Planners claim issues, generate a written plan, commit it to `plans/<ISSUE-KEY>.md` in the repo, and move on. A human reviews the plan; once approved, a regular implementation worker picks the issue up.

### Build the planner image

```bash
docker build -f planner/Dockerfile -t planner-claude .
```

### Start planner workers

```bash
factory planners                          # start 1 planning worker
factory planners 2                        # start 2 planning workers
factory planners --env-file .env.factory  # pass environment variables to planners
```

This uses the `planner-claude` image by default. Override with `FACTORY_PLANNER_IMAGE=<image>`.

### Workflow

1. Planner claims an eligible issue and generates `plans/<ISSUE-KEY>.md`
2. Issue is transitioned to **Awaiting Plan Review**
3. Human reviews and approves the plan (transitions issue to **Plan Approved**)
4. Regular implementation worker picks it up from the **Plan Approved** queue

### Opt-in / opt-out

By default, planning is **opt-in**. Add a `needs-plan` label to a Jira issue to require a planning step for that specific issue.

To require planning for all issues by default, set:

```bash
export PLAN_BY_DEFAULT=true
```

Individual issues can bypass planning with the `skip-plan` label (takes precedence over `PLAN_BY_DEFAULT=true`).

