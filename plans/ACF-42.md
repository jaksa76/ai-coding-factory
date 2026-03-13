# Plan: ACF-42 — Introduce a configuration file for the factory

## Goal

Give `factory` a two-level config system so users can persist defaults
(credentials, images, project settings) instead of supplying everything on the
command line or via ambient environment variables. Both config files are merged
to produce the env-file passed into each worker container.

## Motivation

Currently `factory add --image <img> <count>` launches containers with no
environment variables. Workers need a dozen variables to do anything useful.
These must be threaded in manually via `--env-file` today. A config system
centralises all of this and makes `factory` usable without flags for common
workflows.

## Two-level config (global → local → CLI flags)

Inspired by `~/.gitconfig` + `.git/config`. Later levels override earlier ones.

### Level 1 — Global credentials (`~/.factory/config`)

Shared across all projects. Never committed to a repository. Contains secrets.

```
# Jira authentication
JIRA_SITE=mycompany.atlassian.net
JIRA_EMAIL=worker@example.com
JIRA_TOKEN=...
JIRA_ASSIGNEE_ACCOUNT_ID=...

# Git push credentials
GIT_USERNAME=...
GIT_TOKEN=...

# Agent keys (include whichever apply)
ANTHROPIC_API_KEY=...
# GH_TOKEN=...
# OPENAI_API_KEY=...

# Claude OAuth (written by `factory import-claude-credentials`)
# CLAUDE_ACCESS_TOKEN=...
# CLAUDE_REFRESH_TOKEN=...
# CLAUDE_TOKEN_EXPIRES_AT=...
# CLAUDE_SUBSCRIPTION_TYPE=...
```

### Level 2 — Project config (`.factory` in the current working directory)

Project-specific settings. Safe to commit (contains no secrets).

```
# Task management backend
TASK_MANAGER=jira          # jira | github | todo
JIRA_PROJECT=MYPROJ        # jira backend
# GH_ASSIGNEE=myuser   # github backend

# Repository
GIT_REPO_URL=https://github.com/myorg/myrepo

# Worker images (factory-internal, not passed into containers)
FACTORY_WORKER_IMAGE=worker-claude
FACTORY_PLANNER_IMAGE=planner-claude

# Default worker counts (factory-internal)
FACTORY_WORKER_COUNT=2
FACTORY_PLANNER_COUNT=1

# Loop behaviour (passed into containers)
PLAN_BY_DEFAULT=false
FEATURE_BRANCHES=true
# NO_ISSUES_WAIT=60
# INTER_ISSUE_WAIT=1200
# IMPLEMENTATION_PROMPT=...
# PLANNING_PROMPT=...
```

### Settings classification

| Variable | Global | Project | Passed to container |
|---|:---:|:---:|:---:|
| `JIRA_SITE` | ✓ | | ✓ |
| `JIRA_EMAIL` | ✓ | | ✓ |
| `JIRA_TOKEN` | ✓ | | ✓ |
| `JIRA_ASSIGNEE_ACCOUNT_ID` | ✓ | | ✓ |
| `GIT_USERNAME` | ✓ | | ✓ |
| `GIT_TOKEN` | ✓ | | ✓ |
| `ANTHROPIC_API_KEY` | ✓ | | ✓ |
| `GH_TOKEN` | ✓ | | ✓ |
| `CLAUDE_*` (OAuth) | ✓ | | ✓ |
| `TASK_MANAGER` | | ✓ | ✓ |
| `JIRA_PROJECT` | | ✓ | ✓ |
| `GH_ASSIGNEE` | | ✓ | ✓ |
| `GIT_REPO_URL` | | ✓ | ✓ |
| `PLAN_BY_DEFAULT` | | ✓ | ✓ |
| `FEATURE_BRANCHES` | | ✓ | ✓ |
| `NO_ISSUES_WAIT` | | ✓ | ✓ |
| `INTER_ISSUE_WAIT` | | ✓ | ✓ |
| `IMPLEMENTATION_PROMPT` | | ✓ | ✓ |
| `PLANNING_PROMPT` | | ✓ | ✓ |
| `FACTORY_WORKER_IMAGE` | | ✓ | stripped |
| `FACTORY_PLANNER_IMAGE` | | ✓ | stripped |
| `FACTORY_WORKER_COUNT` | | ✓ | stripped |
| `FACTORY_PLANNER_COUNT` | | ✓ | stripped |

## Config file format

Plain `KEY=VALUE` text file — one assignment per line, `#` starts a comment,
blank lines ignored. No shell syntax (`export`, `$(...)`, etc.). This format is:

- Sourceable by bash (populates variables in the current shell)
- Accepted by `docker run --env-file` verbatim (after stripping `FACTORY_*`)

## Config file discovery

```
--config <path>          CLI flag on any subcommand (overrides everything)
FACTORY_CONFIG           Environment variable
.factory                 Current working directory (project config)
~/.factory/config        Global credentials
```

`--config` and `FACTORY_CONFIG` replace the project-level file only; the global
file (`~/.factory/config`) is always loaded first when it exists.

If neither config file is found, `factory` continues with no config (current
behaviour).

## Changes to `factory add`, `factory workers`, `factory planners`

- Load global config, then project config; later values override earlier ones.
- Merge both into a temp env-file, stripping `FACTORY_*` keys, passed as
  `--env-file` to `docker run`.
- `factory workers` defaults image to `FACTORY_WORKER_IMAGE`, count to
  `FACTORY_WORKER_COUNT` (default `1`).
- `factory planners` defaults image to `FACTORY_PLANNER_IMAGE`, count to
  `FACTORY_PLANNER_COUNT` (default `1`).
- `factory add` still requires `--image` and count explicitly (low-level
  command; no defaults).
- `FACTORY_ENV_FILE` env var is superseded by the config system; kept for
  backwards compatibility (merged in after both config files if set).

## New command: `factory init`

Writes a commented template `.factory` project config file in the current
directory. The global credentials template is written to `~/.factory/config`
if that file does not exist.

```bash
factory init
```

- Errors if `.factory` already exists (no silent overwrite).
- Creates `~/.factory/` and writes `~/.factory/config` template if absent.
- Prints instructions telling the user to fill in their credentials.

## New command: `factory config`

Reads and displays the merged config (useful for debugging). Masks secret
values (anything containing `TOKEN`, `KEY`, `PASSWORD`, `SECRET`).

```bash
factory config
```

## Changes to `factory import-claude-credentials`

Currently writes to `--env-file <file>`. Update to write into
`~/.factory/config` by default (still accepts `--env-file` for backwards
compatibility).

## Files to create / modify

### `factory/factory.bats` additions

- `factory init` creates `.factory` with expected placeholder keys.
- `factory init` errors if `.factory` already exists.
- `factory init` creates `~/.factory/config` template when absent.
- `factory workers` uses `FACTORY_WORKER_IMAGE` from project config.
- `factory workers` uses `FACTORY_WORKER_COUNT` from project config.
- `factory planners` uses `FACTORY_PLANNER_IMAGE` and `FACTORY_PLANNER_COUNT`.
- `docker run` receives a merged env-file containing vars from both configs.
- `FACTORY_*` vars are stripped from the env-file passed to docker.
- Global config is loaded even when no project config exists.
- Project config overrides global config for the same key.
- `--config <path>` replaces the project config file.
- `FACTORY_CONFIG` env var is respected.
- Missing config files are silently ignored.
- `factory config` prints merged config with secrets masked.

### `factory/factory`

1. Add `load_config()`:
   - Load `~/.factory/config` if it exists.
   - Load project config (from `--config` flag, `FACTORY_CONFIG` env var, or
     `.factory` in cwd) if it exists; values override global.
   - Merge into a temp file (excluding `FACTORY_*` lines); export as
     `WORKER_ENV_FILE`. Register cleanup via `trap`.
   - Source the merged config so `FACTORY_*` variables are available in the
     current shell.

2. Call `load_config()` before the main `case` dispatch (parses `--config`
   from the global args before the subcommand is dispatched).

3. Update `cmd_workers`:
   - Default image to `${FACTORY_WORKER_IMAGE:-worker-claude}`.
   - Default count to `${FACTORY_WORKER_COUNT:-1}`.
   - Pass `WORKER_ENV_FILE` when set.

4. Update `cmd_planners`:
   - Default image to `${FACTORY_PLANNER_IMAGE:-planner-claude}`.
   - Default count to `${FACTORY_PLANNER_COUNT:-1}`.
   - Pass `WORKER_ENV_FILE` when set.

5. Add `cmd_init`:
   - Create `~/.factory/` and write global credentials template if absent.
   - Error if `.factory` already exists.
   - Write project config template.
   - Print next-step instructions.

6. Add `cmd_config`:
   - Print merged config, masking values for keys matching
     `TOKEN|KEY|PASSWORD|SECRET`.

7. Update `cmd_import_claude_credentials`:
   - Default target file to `~/.factory/config` (keep `--env-file` override).

8. Update `usage()` and main `case` dispatch.

## Implementation steps

1. Add `load_config()`, `cmd_init()`, `cmd_config()` to `factory/factory`;
   update `cmd_workers`, `cmd_planners`, `cmd_add`, `cmd_import_claude_credentials`,
   `usage`, and the main dispatch.
2. Add new bats tests to `factory/factory.bats` covering all cases above.
3. Verify all existing tests still pass (`bats factory/factory.bats`).
