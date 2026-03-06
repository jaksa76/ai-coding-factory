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
factory workers        # start 1 implementation worker
factory workers 3      # start 3 implementation workers
```

This uses the `worker-claude` image by default. Override with `FACTORY_WORKER_IMAGE=<image>` if you want a different image.

For lower-level control (e.g. a different agent image):

```bash
factory add --image worker-copilot 2
```

Monitor workers with:

```bash
factory status              # list running workers
factory logs <worker-id>    # stream a worker's output
factory stop --all          # stop all workers
```

---

## Planning

If your workflow requires a planning step before implementation, run planner workers alongside your regular workers. Planners claim issues, generate a written plan, commit it to `plans/<ISSUE-KEY>.md` in the repo, and move on. A human reviews the plan; once approved, a regular implementation worker picks the issue up.

### Build the planner image

```bash
docker build -f planner/Dockerfile -t planner-claude .
```

### Start planner workers

```bash
factory planners       # start 1 planning worker
factory planners 2     # start 2 planning workers
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

