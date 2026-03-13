# Architecture

## Overview

Worker-based pull model where agents poll a task-manager backend for work. By default, the backend is Jira, and Jira acts as the single source of truth (no local task store).

```
[Task manager backend: jira | github | todo]
   <- single source of truth for issue state
   v  workers poll for unassigned/open work
[Worker pool: implementers + planners]
   v  run agent, push code/plan, comment, transition state
[Task manager + Git]

[factory CLI] <- start/stop/monitor worker containers
```

## Repository layout

```
task-manager/   CLI tool - pluggable task management wrapper
loop/           CLI tool - claim/work loop (implementation and planning modes)
worker-builder/ CLI tool - build worker Docker images from a project devcontainer
factory/        CLI tool - start/stop/monitor worker containers

workers/
  claude/       Dockerfile: loop + Claude CLI
  copilot/      Dockerfile: loop + Copilot CLI

planner/        Dockerfile: loop --for-planning + Claude CLI
plans/          Plan files generated in planning mode

legacy/         Previous hub-based implementation (reference only)
```

## task-manager

task-manager is a thin CLI wrapper over backends:

- jira (default, via acli)
- github (via gh)
- todo (local TODO.md for development/testing)

It exposes a common interface: auth, claim, list, view, assign, comment, transition, transitions.

### Claim semantics

Claiming uses optimistic locking:

1. Search for eligible unassigned work
2. Assign to self
3. Wait and verify assignment
4. If assignment changed, retry from step 1
5. Transition status (for example In Progress or Planning)
6. Return normalized issue JSON for downstream tools

Planning eligibility is controlled by PLAN_BY_DEFAULT plus labels:

- needs-plan forces planning
- skip-plan skips planning and takes precedence

## loop

loop is an agent-agnostic orchestrator. It shells out to task-manager for issue operations, agent for model execution, and git for repository operations.

```bash
loop --project MYPROJ
loop --project MYPROJ --for-planning
```

The implementation and planning logic is extracted into separate scripts (`implement`, `plan`) that can also be called directly with an issue key:

```bash
implement <issue-key>
plan <issue-key>
```

### Implementation loop

1. Claim an implementation-eligible issue with task-manager
2. Clone or pull GIT_REPO_URL
3. Run agent with issue summary/description (and approved plan file when present)
4. Push code changes
5. Post issue comment and transition status
6. Sleep and repeat

Features currently supported:

- Rate-limit retry when the agent returns 429/overload signals
- Configurable polling/spacing intervals (NO_ISSUES_WAIT, INTER_ISSUE_WAIT)
- Customizable agent prompt via IMPLEMENTATION_PROMPT
- Optional feature-branch flow:
  - Enabled by FEATURE_BRANCHES=true or needs-branch label
  - Disabled by skip-branch label (takes precedence)
  - Creates branch feature/<ISSUE-KEY>, opens PR, comments with PR URL, and attempts transition to In Review

### Planning loop (--for-planning)

1. Claim a planning-eligible issue with task-manager claim --for-planning
2. Clone or pull GIT_REPO_URL
3. Run agent to create plans/<ISSUE-KEY>.md (customizable via PLANNING_PROMPT)
4. Commit and push plan file
5. Comment with GitHub plan URL
6. Transition to Awaiting Plan Review when available
7. Sleep and repeat

Planner and implementer loops are intentionally separate so workers do not block on human review.

## worker-builder

worker-builder generates project-specific worker images by extending a target repository's devcontainer setup.

```bash
worker-builder build --devcontainer <path> --type <agent> --tag <tag>
```

Flow:

1. Read .devcontainer/devcontainer.json
2. Resolve base image and setup metadata
3. Generate a derived Dockerfile with selected agent tooling and factory scripts
4. Build the image (and optionally push)

## factory

factory operates the worker pool through a pluggable runtime backend (no long-running server).

```bash
factory status
factory workers [count] [--env-file <file>]
factory planners [count] [--env-file <file>]
factory add --image <img> <count> [--env-file <file>]
factory logs <worker-id>
factory stop <worker-id>
factory stop --all
factory import-claude-credentials --env-file <file>
```

Key behavior:

- Worker containers are started with --restart=on-failure (Docker) or equivalent
- Environment is injected via --env-file or FACTORY_ENV_FILE
- workers and planners commands are convenience wrappers around add
- Worker images are automatically built or rebuilt when missing or outdated
- The runtime backend is selected via a `runtime` symlink in the factory directory:
  - `runtime-docker` (default) — local Docker
  - `runtime-aws` — AWS ECS Fargate

AWS ECS runtime environment variables:

| Variable | Purpose |
|---|---|
| FACTORY_AWS_REGION | AWS region (default: us-east-1) |
| FACTORY_AWS_CLUSTER | ECS cluster name (default: ai-coding-factory) |
| FACTORY_AWS_SUBNET_ID | Subnet for ECS tasks |
| FACTORY_AWS_SECURITY_GROUP_ID | Security group for ECS tasks |
| FACTORY_AWS_LOG_GROUP | CloudWatch log group (default: /ecs/ai-coding-factory) |

## Worker images

Predefined worker images are thin wrappers over loop plus an agent-specific adapter script.

| Image | Agent | Mode |
|---|---|---|
| workers/claude | Claude CLI | implementation |
| workers/copilot | GitHub Copilot CLI | implementation |
| planner/Dockerfile | Claude CLI | planning |

Project-specific images should prefer worker-builder to mirror target devcontainer environments.

## Configuration

The system is configured through environment variables (typically in an env file passed to factory):

| Variable | Purpose |
|---|---|
| TASK_MANAGER | Backend: jira (default), github, or todo |
| JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN | Jira authentication |
| JIRA_ASSIGNEE_ACCOUNT_ID | Jira self-assignment identity |
| JIRA_PROJECT | Jira project key |
| GH_TOKEN, GH_ASSIGNEE | GitHub backend authentication/identity |
| GIT_REPO_URL, GIT_USERNAME, GIT_TOKEN | Target repo and push credentials |
| PLAN_BY_DEFAULT | Planning policy default |
| FEATURE_BRANCHES | Enable feature-branch workflow by default |
| NO_ISSUES_WAIT, INTER_ISSUE_WAIT | Polling and pacing controls |
| IMPLEMENTATION_PROMPT | Override the default implementation prompt |
| PLANNING_PROMPT | Override the default planning prompt |

Agent-specific variables are added per worker type (for example ANTHROPIC_API_KEY for Claude workers).

## What this drops vs. the legacy hub

- No local task store in this repository
- No background sync service reconciling Docker and file state
- No web server or browser UI
- No separate hub process coordinating workers

## Notes

- All tools are bash scripts.
- loop is the core orchestrator; workers are thin image/agent wrappers.
- Task-manager keeps backend-specific logic isolated from loop and factory.

