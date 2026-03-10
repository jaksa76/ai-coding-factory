# Plan: ACF-41 — Running workers on AWS

## Goal

Extend `factory` with an AWS backend so workers can be launched as ECS Fargate
tasks instead of local Docker containers. The same `factory` commands work
regardless of backend; the active backend is selected via a `runtime` symlink
(similar to how `bin/agent` selects between `workers/claude/agent` and
`workers/copilot/agent`).

## Motivation

The legacy implementation had two backends (`agents-docker.sh` and
`agents-aws.sh`). The current `factory` supports Docker only. AWS is needed
for scalable, cloud-hosted deployments where local Docker is not available or
not practical.

## High-level design

`factory` delegates all container-lifecycle operations to a `runtime` script
located alongside it. Two runtime implementations exist:

- `factory/runtime-docker` — wraps the Docker CLI (current behaviour)
- `factory/runtime-aws` — wraps AWS ECS Fargate

During deployment (or `factory init`), a `factory/runtime` symlink is created
pointing to the chosen implementation — exactly as `bin/agent` points to either
`workers/claude/agent` or `workers/copilot/agent`.

`factory` itself becomes a thin dispatcher: it parses user-facing commands,
derives a worker name, and delegates to `runtime <subcommand> <args>`. It
contains no Docker- or AWS-specific code.

Each runtime script is a standalone executable with its own `.bats` test suite.

## Runtime interface

Both `runtime-docker` and `runtime-aws` implement the same subcommands:

| Subcommand | Arguments | Description |
|---|---|---|
| `add` | `<name> <image> [--env-file <file>]` | Start one worker, print its ID |
| `status` | — | Print table of running workers (`ID Image Status Name`) |
| `logs` | `<worker-id>` | Stream logs for a worker |
| `stop` | `<worker-id>` | Stop one worker |
| `stop-all` | — | Stop all factory-managed workers |

`factory` generates unique worker names (e.g. `factory-worker-<ts>-<n>`) and
calls `runtime add <name> <image> …` once per worker when `count > 1`.

## New environment / config variables

| Key | Purpose |
|-----|---------|
| `FACTORY_AWS_REGION` | AWS region (defaults to `AWS_DEFAULT_REGION` or `us-east-1`) |
| `FACTORY_AWS_CLUSTER` | ECS cluster name (default: `ai-coding-factory`) |
| `FACTORY_AWS_SUBNET_ID` | Subnet for ECS tasks (default: first subnet in default VPC) |
| `FACTORY_AWS_SECURITY_GROUP_ID` | Security group for ECS tasks (default: default SG) |
| `FACTORY_AWS_LOG_GROUP` | CloudWatch log group (default: `/ecs/ai-coding-factory`) |

The standard AWS credential vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_DEFAULT_REGION`) are passed through as-is.

No `FACTORY_BACKEND` variable is needed — the symlink encodes the selection.

## AWS infrastructure used

| AWS service | Purpose |
|-------------|---------|
| ECS Fargate | Run worker containers (no EC2 instances to manage) |
| CloudWatch Logs | Container stdout/stderr (replacing `docker logs`) |
| IAM | `ecsTaskExecutionRole` for ECS to pull images and write logs |

Workers are long-lived containers; workspace state lives inside the container.
No EFS volumes are needed.

## Command mapping

### `runtime-aws add <name> <image> [--env-file <file>]`

1. Ensure the ECS cluster exists (create if absent).
2. Ensure `ecsTaskExecutionRole` exists (create if absent).
3. Register an ECS task definition (Fargate, `awsvpc` networking, env vars from
   `--env-file` passed as container environment).
4. Run the task on the cluster, tagged `ai-coding-factory.worker=true`.
5. Print the ECS task ARN as the worker ID.

Resource sizing defaults: CPU `256`, memory `512`.

### `runtime-aws status`

List running ECS tasks in the cluster tagged `ai-coding-factory.worker=true`,
formatted as a table (`ID`, `Image`, `Status`, `Name`).

### `runtime-aws logs <task-arn>`

Fetch log events from CloudWatch using the log stream
`ecs/<container-name>/<task-id>`. Poll every 2 s for new events (CloudWatch
has no native `--follow`).

### `runtime-aws stop <task-arn>`

Call `aws ecs stop-task` with the correct cluster and task ARN.

### `runtime-aws stop-all`

List all running tasks tagged `ai-coding-factory.worker=true` and stop each.

## Files to create

### `factory/runtime-docker`

Executable bash script. Implements the runtime interface using the Docker CLI.
Extracts all Docker-specific logic currently inline in `factory/factory`.

```
runtime-docker add <name> <image> [--env-file <file>]
runtime-docker status
runtime-docker logs <worker-id>
runtime-docker stop <worker-id>
runtime-docker stop-all
```

Internal details:
- `add`: `docker run -d --restart=on-failure --label ai-coding-factory.worker=true --name <name> …`
- `status`: `docker ps --filter "label=ai-coding-factory.worker=true" --format "table …"`
- `logs`: `docker logs -f <worker-id>`
- `stop`: `docker stop <worker-id>`
- `stop-all`: `docker ps --filter … --quiet | xargs docker stop`

### `factory/runtime-docker.bats`

Unit tests for `runtime-docker` with `docker` stubbed. Key cases:

- `add` runs `docker run` with the correct label, name and image.
- `add` passes `--env-file` to `docker run` when provided.
- `status` calls `docker ps` with the worker label filter.
- `logs` calls `docker logs -f` with the given ID.
- `stop` calls `docker stop` with the given ID.
- `stop-all` stops every container with the factory label.

### `factory/runtime-aws`

Executable bash script. Implements the runtime interface using the AWS CLI.

```
runtime-aws add <name> <image> [--env-file <file>]
runtime-aws status
runtime-aws logs <task-arn>
runtime-aws stop <task-arn>
runtime-aws stop-all
```

Internal helpers:
- `ensure_cluster` — create ECS cluster if absent
- `ensure_execution_role` — create `ecsTaskExecutionRole` if absent
- `resolve_network` — resolve subnet/SG from env or default VPC
- `register_task_def <name> <image> <env_file>` — write and register task
  definition JSON, return task definition ARN
- `task_id_from_arn <arn>` — extract the short task ID for log stream names

Key conventions:
- Task definition family = `ai-coding-factory-<name>`.
- Tasks tagged `ai-coding-factory.worker=true` for listing/stop-all.
- Log group `${FACTORY_AWS_LOG_GROUP:-/ecs/ai-coding-factory}` created if absent.
- Log stream pattern: `ecs/<container-name>/<task-id>`.

### `factory/runtime-aws.bats`

Unit tests for `runtime-aws` with `aws` stubbed. Key cases:

- `add` registers a task definition and runs an ECS task.
- `add` creates the ECS cluster if it doesn't exist.
- `add` passes env vars from `--env-file` into the task definition.
- `status` returns a formatted table of running tasks.
- `logs` polls CloudWatch and prints events.
- `stop` calls `ecs stop-task` with the correct cluster and task ARN.
- `stop-all` stops every task with the factory tag.
- Missing `FACTORY_AWS_REGION` defaults gracefully.

## Files to modify

### `factory/factory`

1. **Remove Docker-specific code** from `cmd_add`, `cmd_status`, `cmd_logs`,
   and `cmd_stop`. Replace with calls to the `runtime` script:

   ```bash
   RUNTIME="$(dirname "$0")/runtime"

   cmd_add()    { … runtime add <name> <image> … }
   cmd_status() { "$RUNTIME" status }
   cmd_logs()   { "$RUNTIME" logs "$worker_id" }
   cmd_stop()   { "$RUNTIME" stop "$target"
                  # or: "$RUNTIME" stop-all }
   ```

2. **`usage`**: document the `runtime` symlink and how to select a backend.

3. The `workers` and `planners` convenience commands remain in `factory` (they
   are image-selection sugar, not runtime-specific).

### `factory/factory.bats`

Replace Docker-specific assertions in `cmd_add`, `cmd_status`, `cmd_logs`, and
`cmd_stop` tests with assertions that verify `factory` calls the `runtime`
script with the correct subcommand and arguments. Stub `runtime` as a test
double rather than stubbing `docker` or `aws` directly.

### `factory/factory` — `cmd_init` template (ACF-42)

Add runtime symlink creation to the generated setup, and document the AWS
variables as commented placeholders:

```
# AWS runtime settings (only needed when runtime → runtime-aws)
# FACTORY_AWS_REGION=us-east-1
# FACTORY_AWS_CLUSTER=ai-coding-factory
# FACTORY_AWS_SUBNET_ID=
# FACTORY_AWS_SECURITY_GROUP_ID=
# FACTORY_AWS_LOG_GROUP=/ecs/ai-coding-factory
```

## Implementation steps

1. Create `factory/runtime-docker`: extract all Docker logic from `factory`.
2. Create `factory/runtime-docker.bats`: unit-test the Docker runtime.
3. Create `factory/runtime-aws`: implement the AWS ECS runtime.
4. Create `factory/runtime-aws.bats`: unit-test the AWS runtime.
5. Create symlink `factory/runtime → runtime-docker` (default).
6. Modify `factory/factory`: remove inline Docker code, delegate to `runtime`.
7. Update `factory/factory.bats`: stub `runtime` instead of `docker`.
8. Run all bats test suites to confirm no regressions.

## Dependencies

- ACF-42 (config file) may provide AWS variable defaults; this plan can proceed
  without it by reading variables directly from the environment.
- The `aws` CLI must be installed and configured in the environment running
  `factory`. Worker images themselves do not need AWS credentials.
