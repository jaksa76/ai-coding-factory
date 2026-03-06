# Plan: ACF-42 — Introduce a configuration file for the factory

## Goal

Give `factory` a config file so users can persist defaults (worker image, Jira
credentials, git settings, agent keys) instead of supplying everything on the
command line or relying on ambient environment variables. The config file also
serves as the env-file passed into each worker container.

## Motivation

Currently `factory add --image <img> <count>` launches containers with no
environment variables. Workers need `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_TOKEN`,
`JIRA_ASSIGNEE_ACCOUNT_ID`, `JIRA_PROJECT`, `GIT_REPO_URL`, `GIT_USERNAME`,
`GIT_TOKEN`, and an agent key (`ANTHROPIC_API_KEY`, `GH_TOKEN`, etc.) to do
anything useful. These must be threaded in manually via `extra_args` today.
A config file centralises all of this and makes `factory` usable without any
flags for common workflows.

## Config file format

Plain `KEY=VALUE` text file — one assignment per line, `#` starts a comment,
blank lines ignored. No shell syntax (`export`, `$(...)`, etc.). This format
is simultaneously:

- Sourceable by bash (assigns variables without `export`)
- Accepted by `docker run --env-file` verbatim

### Worker variables (passed into containers)

```
JIRA_SITE=mycompany.atlassian.net
JIRA_EMAIL=worker@example.com
JIRA_TOKEN=...
JIRA_ASSIGNEE_ACCOUNT_ID=...
JIRA_PROJECT=MYPROJ

GIT_REPO_URL=https://github.com/myorg/myrepo
GIT_USERNAME=...
GIT_TOKEN=...

# Agent-specific (include whichever apply)
ANTHROPIC_API_KEY=...
# GH_TOKEN=...
# OPENAI_API_KEY=...
```

### Factory-specific defaults (not passed into containers)

```
FACTORY_IMAGE=my-worker-image
FACTORY_COUNT=1
```

`FACTORY_*` keys are stripped before the file is used as `--env-file`.

## Config file location

Search order (first found wins):

1. Path given by `--config <path>` flag on any subcommand
2. `FACTORY_CONFIG` environment variable
3. `.factory` in the current working directory

If none is found, `factory` continues with no config (current behaviour).

## Changes to `factory add`

- Load config at startup (source for `FACTORY_*` values, keep raw path for
  `--env-file`).
- `--image` defaults to `$FACTORY_IMAGE` if not provided on the CLI.
- Count argument defaults to `$FACTORY_COUNT` (default `1`) if omitted.
- `docker run` gains `--env-file <stripped-config>` so worker containers
  receive all non-`FACTORY_*` variables. A temp file is produced by stripping
  `FACTORY_*` lines and is cleaned up after the command.

## New command: `factory init`

Writes a commented template `.factory` file in the current directory.

```bash
factory init
```

Errors if `.factory` already exists (no silent overwrite). Prints a message
telling the user to fill in their credentials.

## Files to create

### `factory/factory.bats` additions

Tests for the new behaviour (added to the existing file):

- `factory init` creates `.factory` with expected placeholder keys.
- `factory init` errors if `.factory` already exists.
- `factory add` uses `FACTORY_IMAGE` from config when `--image` is absent.
- `factory add` uses `FACTORY_COUNT` from config when count is absent.
- `factory add` passes `--env-file` to `docker run` containing worker vars.
- `factory add` does NOT include `FACTORY_IMAGE` / `FACTORY_COUNT` in the
  env-file passed to docker.
- `--config <path>` causes that file to be used instead of `.factory`.
- `FACTORY_CONFIG` env var is respected.
- Missing config file is silently ignored (no error).

## Files to modify

### `factory/factory`

1. Add `load_config()` helper at the top:
   - Determine config path from `--config` flag, `FACTORY_CONFIG` env var, or
     `.factory` in cwd; export `CONFIG_FILE`.
   - Source the file to populate `FACTORY_IMAGE` and `FACTORY_COUNT` in the
     current shell.
   - Produce a temp file with `FACTORY_*` lines removed; export as
     `WORKER_ENV_FILE`.
2. Call `load_config()` before the main `case` dispatch; clean up
   `WORKER_ENV_FILE` on exit via a `trap`.
3. Update `cmd_add`:
   - Default `image` to `${FACTORY_IMAGE:-}` if `--image` is not supplied.
   - Default `count` to `${FACTORY_COUNT:-1}` if positional count is absent.
   - Add `--env-file "$WORKER_ENV_FILE"` to the `docker run` call when
     `WORKER_ENV_FILE` is non-empty.
4. Add `cmd_init`:
   - Error if `.factory` (or `$CONFIG_FILE`) already exists.
   - Write a template with commented sections and placeholder values.
   - Print instructions to the user.
5. Update `usage()` to document `init` and the `--config` flag.
6. Add `init` to the main `case` dispatch.

## Implementation steps

1. Add `load_config()` and `cmd_init()` to `factory/factory`; update
   `cmd_add`, `usage`, and the main dispatch.
2. Add new bats tests to `factory/factory.bats` covering the cases above.
3. Verify all existing tests still pass (`bats factory/factory.bats`).
