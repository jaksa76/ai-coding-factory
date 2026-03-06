# Plan: ACF-41 — Running workers on AWS

## Goal

Extend `factory` with an AWS backend so workers can be launched as ECS Fargate
tasks (with EFS volumes for workspace persistence) instead of local Docker
containers. The same `factory` commands work regardless of backend; the backend
is selected via a config key or CLI flag.

## Motivation

The legacy implementation had two backends (`agents-docker.sh` and
`agents-aws.sh`). The current `factory` supports Docker only. AWS is needed
for scalable, cloud-hosted deployments where local Docker is not available or
not practical.

## High-level design

A `--backend` flag (and `FACTORY_BACKEND` config key) selects the runtime:

- `docker` (default) — current behaviour, unchanged
- `aws` — uses ECS Fargate for containers and EFS for workspace volumes

Each `factory` subcommand (`add`, `stop`, `status`, `logs`) dispatches to the
appropriate backend implementation. No new top-level commands are needed.

## New environment / config variables

Added to the `.factory` config file (see ACF-42):

| Key | Purpose |
|-----|---------|
| `FACTORY_BACKEND` | `docker` (default) or `aws` |
| `FACTORY_AWS_REGION` | AWS region (defaults to `AWS_DEFAULT_REGION` or `us-east-1`) |
| `FACTORY_AWS_CLUSTER` | ECS cluster name (default: `ai-coding-factory`) |
| `FACTORY_AWS_SUBNET_ID` | Subnet for ECS tasks (default: first subnet in default VPC) |
| `FACTORY_AWS_SECURITY_GROUP_ID` | Security group for ECS tasks (default: default SG) |
| `FACTORY_AWS_LOG_GROUP` | CloudWatch log group (default: `/ecs/ai-coding-factory`) |

The standard AWS credential env vars (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`) are passed through as-is.

## AWS infrastructure used

| AWS service | Purpose |
|-------------|---------|
| ECS Fargate | Run worker containers (no EC2 instances to manage) |
| EFS | Persistent `/workspace` volume per worker |
| CloudWatch Logs | Container stdout/stderr (replacing `docker logs`) |
| IAM | `ecsTaskExecutionRole` for ECS to pull images and write logs |

This matches what the legacy `agents-aws.sh` used.

## Command mapping

### `factory add --image <img> [count]`

For each worker:

1. Create an EFS file system (creation token = worker name).
2. Register an ECS task definition (Fargate, `awsvpc` networking, EFS volume
   mounted at `/workspace`, env vars from `--env-file` passed as container
   environment).
3. Run the task on the ECS cluster.
4. Print the ECS task ARN as the worker ID.

Resource sizing defaults (configurable via config): CPU `256`, memory `512`.

### `factory status`

List running ECS tasks in the cluster that carry the
`ai-coding-factory.worker=true` tag, formatted like the Docker output
(`ID`, `Image`, `Status`, `Name`).

### `factory logs <worker-id>`

`worker-id` is the ECS task ARN. Fetch log events from CloudWatch using the
log stream `ecs/<container-name>/<task-id>`. Follow with polling (CloudWatch
has no native `--follow`; poll every 2 s and print new events).

### `factory stop <worker-id>` / `factory stop --all`

Call `aws ecs stop-task`. For `--all`, list all running tasks with the factory
tag and stop each one. EFS file systems are **not** automatically deleted on
stop (they persist like Docker volumes; cleanup is manual or via a future
`factory rm` command).

## Files to create

### `factory/backend-aws`

Bash script (not directly executable; sourced by `factory`). Exports functions:

```
aws_add_worker <name> <image> <env_file>
aws_status
aws_logs <task_arn>
aws_stop <task_arn>
aws_stop_all
```

Internal helpers (not exported):
- `aws_ensure_cluster` — create ECS cluster if absent
- `aws_ensure_execution_role` — create `ecsTaskExecutionRole` if absent
- `aws_resolve_network` — resolve VPC/subnet/SG from config or defaults
- `aws_create_efs <name>` — create EFS file system, return file system ID
- `aws_register_task_def <name> <image> <fs_id> <env_file>` — write and
  register task definition JSON, return task definition ARN

Key decisions carried over from the legacy implementation:
- EFS creation token = worker name (enables lookup by name).
- Task definition family = `ai-coding-factory-task-<name>`.
- Tasks are tagged `ai-coding-factory.worker=true` (ECS tags) for listing.
- Log group `/ecs/ai-coding-factory` created if absent.

### `factory/backend-aws.bats`

Tests stub `aws` CLI commands. Key cases:

- `aws_add_worker` registers a task definition and runs an ECS task.
- `aws_add_worker` creates the EFS file system before registering the task.
- `aws_add_worker` creates the ECS cluster if it doesn't exist.
- `aws_status` returns formatted table of running tasks.
- `aws_logs` prints events from CloudWatch.
- `aws_stop` calls `ecs stop-task` with the correct cluster and task ARN.
- `aws_stop_all` stops every task with the factory tag.
- Missing `FACTORY_AWS_REGION` defaults gracefully.

## Files to modify

### `factory/factory`

1. **Source backend**: after `load_config` (ACF-42), source the appropriate
   backend file:
   ```bash
   FACTORY_BACKEND="${FACTORY_BACKEND:-docker}"
   case "$FACTORY_BACKEND" in
       docker) : ;;  # built-in
       aws)    source "$(dirname "$0")/backend-aws" ;;
       *)      error_exit "Unknown backend: $FACTORY_BACKEND" ;;
   esac
   ```

2. **`cmd_add`**: call `aws_add_worker` instead of `docker run` when backend
   is `aws`. Pass the stripped env file (`WORKER_ENV_FILE`) and image.

3. **`cmd_status`**: call `aws_status` or existing `docker ps` depending on
   backend.

4. **`cmd_logs`**: call `aws_logs <worker-id>` or `docker logs -f` depending
   on backend.

5. **`cmd_stop`**: call `aws_stop` / `aws_stop_all` or `docker stop` depending
   on backend.

6. **`usage`**: document `FACTORY_BACKEND` and the `--backend` override flag.

7. **`--backend` flag**: allow `factory --backend aws add …` to override config
   for a single invocation (parsed before command dispatch).

### `factory/factory.bats`

Add integration test cases for the AWS backend (with `aws` stubbed):

- `factory add` with `FACTORY_BACKEND=aws` calls `aws ecs run-task`.
- `factory status` with `FACTORY_BACKEND=aws` calls `aws ecs list-tasks`.
- `factory stop <arn>` with `FACTORY_BACKEND=aws` calls `aws ecs stop-task`.
- `factory logs <arn>` with `FACTORY_BACKEND=aws` calls `aws logs get-log-events`.
- `factory --backend aws add …` overrides the configured backend.

### `factory/factory` — `cmd_init` template (ACF-42)

Add AWS-specific commented placeholders to the generated `.factory` template:

```
# Backend selection: docker (default) or aws
# FACTORY_BACKEND=docker

# AWS backend settings (only needed when FACTORY_BACKEND=aws)
# FACTORY_AWS_REGION=us-east-1
# FACTORY_AWS_CLUSTER=ai-coding-factory
# FACTORY_AWS_SUBNET_ID=
# FACTORY_AWS_SECURITY_GROUP_ID=
# FACTORY_AWS_LOG_GROUP=/ecs/ai-coding-factory
```

## Implementation steps

1. Create `factory/backend-aws` with all helper functions.
2. Create `factory/backend-aws.bats` with unit tests for the AWS functions.
3. Modify `factory/factory`: add `--backend` flag parsing, backend sourcing,
   and backend dispatch in `cmd_add`, `cmd_status`, `cmd_logs`, `cmd_stop`.
4. Update `factory/factory.bats`: add AWS backend integration tests.
5. Update the `cmd_init` template in `factory/factory` (or as part of ACF-42
   implementation) to include AWS placeholders.
6. Run all bats test suites to confirm no regressions.

## Dependencies

- ACF-42 (config file) provides `FACTORY_BACKEND` and `WORKER_ENV_FILE`;
  this plan assumes that work is done first or implemented in parallel.
  If ACF-42 is not yet landed, `FACTORY_BACKEND` can be read directly from
  the environment as a fallback with no config file support.
- The `aws` CLI must be installed and configured in the environment running
  `factory`. Worker images themselves do not need AWS credentials.
