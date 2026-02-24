# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All commands run from the `hub/` directory unless noted.

```bash
# Run unit/integration tests (vitest + supertest)
npm --prefix hub test

# Run tests in watch mode
npm --prefix hub run test:watch

# Run a single test file
npm --prefix hub exec vitest run -- test/tasks.test.mjs

# Start dev server (uses demo-data/ as DATA_DIR, hot-reloads)
npm --prefix hub run dev

# Start production server (reads hub/.env)
npm --prefix hub start

# Run Playwright e2e tests (requires server running + hub/.env)
npm --prefix hub run test:e2e

# Build coding-pipeline Docker image
docker build -t coding-pipeline coding-pipeline/
```

## Architecture

This is a monorepo with two main components:

```
hub/              Node.js ESM Express server (control plane + UI)
coding-pipeline/  Dockerized AI agent that runs inside containers
mock-coding-pipeline/  Lightweight mock agent for local testing
```

### Hub (`hub/src/`)

- **`app.mjs`** — Express app factory; mounts middleware and routes. Imported directly by tests.
- **`server.mjs`** — Process entry point; starts the HTTP listener.
- **`routes/tasks.mjs`** — Task CRUD over the file store.
- **`routes/pipelines.mjs`** — Pipeline lifecycle (create, stop, status, logs); calls `pipelines.sh` via `zx`.
- **`routes/status.mjs`** — Pipeline/stage write-back endpoints called by `pipeline-client.sh`.
- **`pipeline-sync.mjs`** — Background sync that reconciles pipeline state from the container runtime every 10 s.

### File Store

No database. Entities are separate JSON files under `$DATA_DIR` (default `/tmp/ai-coding-factory`; dev uses `hub/demo-data/`):

```
$DATA_DIR/
  projects/   <project_id>.json
  tasks/      <task_id>.json
  pipelines/  <pipeline_id>.json   ← stages embedded as an array
```

### Shell Script Layer

The Hub shells out via `zx` to manage container lifecycle:

- **`pipelines.sh`** — Facade: `start | stop | status | logs | list`. Calls `agents.sh`.
- **`agents.sh` / `agents-docker.sh` / `agents-aws.sh`** — Low-level container primitives. Not called directly by the Hub.
- **`pipeline-client.sh`** (inside the container) — The **only** write path from the agent back to the Hub, via `curl` to the REST API. Works identically in local-Docker and AWS ECS.

### UI (`hub/ui/`)

Static HTML + vanilla JS served by Express. Two pages: `index.html` (task board) and `pipeline.html` (pipeline detail). Calls Hub REST API directly; no build step.

## Key Conventions

- All source files in `hub/src/` use ESM `.mjs` modules.
- `zx` runs shell scripts; `$.verbose` is toggled by `process.env.DEBUG`.
- Tests set `process.env.DATA_DIR` to an isolated temp dir before importing `app.mjs` — never share state between tests.
- Shell scripts are **not** invoked in tests; only the file-store layer is exercised.

## API Contracts (be strict)

Changing these breaks the UI and the pipeline agent:

- `POST /api/tasks` → 201 `{ id, title, status, … }`. `POST /api/tasks/:id` → 405.
- `PUT /api/tasks/:id` without id → 400. Missing task → 404.
- `GET /api/pipelines?task=<taskId>` → array of pipeline objects (read from disk, no container query).
- `POST /api/pipelines` requires `{ taskId, description }` → 201 `{ id }`.
- `POST /api/pipelines/:id/stop` — pipeline id must match `^(.+)_pipeline_\d+$`.
- `PUT /api/pipelines/:id/stages/:position` — upserts a stage by zero-based position.
- ID formats: `task_<ts>_<pid>`, `project_<ts>_<pid>`, `<taskId>_pipeline_<ts>`, `<pipelineId>_stage_<position>`.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DATA_DIR` | `/tmp/ai-coding-factory` | Root of file store |
| `PORT` | `8080` | HTTP listener port |
| `DEBUG` | _(unset)_ | Enables verbose `zx` shell output |
| `GIT_REPO_URL` / `GIT_USERNAME` / `GIT_TOKEN` | _(unset)_ | Passed to pipeline containers |
| `GH_TOKEN` / `GH_USERNAME` | _(unset)_ | GitHub Copilot credentials for pipeline containers |

The Hub Docker container requires `/var/run/docker.sock` mounted to manage pipeline containers locally.
