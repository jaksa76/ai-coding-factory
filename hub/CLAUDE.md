# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Development
npm run dev          # Start server with --watch (auto-reload), uses demo-data as DATA_DIR
npm start            # Start server with .env file

# Testing
npm test             # Run unit/integration tests once (Vitest)
npm run test:watch   # Run unit tests in watch mode
npm run test:e2e     # Run Playwright e2e tests (requires hub running on port 8080)

# Run a single test file
npx vitest run test/pipelines.test.mjs

# Docker
docker build -t hub .
docker run -p 8080:8080 --env-file .env hub
```

## Architecture

This is a Node.js/Express server (ESM modules, `.mjs` files) that manages AI coding pipelines. The hub orchestrates task management, pipeline execution, and agent lifecycle.

**Key data flow:**
1. Tasks are stored as JSON files in `DATA_DIR/tasks/`
2. When a task status changes to `in-progress`, a pipeline is automatically created
3. Pipelines are stored in `DATA_DIR/pipelines/` and executed via `pipelines.sh`
4. A background sync loop (`pipeline-sync.mjs`) polls running pipelines every 10s via shell scripts
5. Agent containers write back progress via `PUT /api/pipelines/{id}/stages/{position}`

**Core modules:**
- `src/app.mjs` — Express app factory; mounts routes under `/api/{tasks,status,pipelines}`, serves UI from `/ui`
- `src/server.mjs` — Entrypoint; starts app and pipeline sync loop
- `src/routes/pipelines.mjs` — Pipeline lifecycle; calls `pipelines.sh` via `zx` for start/stop/status/logs
- `src/routes/tasks.mjs` — Task CRUD + Jira import; auto-creates pipeline on status→`in-progress`
- `src/pipelines-store.mjs` — JSON file persistence for pipeline records
- `src/pipeline-sync.mjs` — Background service that monitors Docker container state

**Shell scripts** (called from routes via `zx`):
- `pipelines.sh` — Orchestrates pipeline container execution (delegates to `agents.sh`)
- `agents.sh` — Manages agent container lifecycle (wraps `agents-docker.sh` or `agents-aws.sh`)
- `jira.sh` — Imports tasks from Jira

**Static UI**: `ui/index.html` (tasks list) and `ui/pipeline.html` (pipeline details) — vanilla HTML/JS, no build step.

## Environment Variables

Copy `.env.example` or configure `.env` with:
- `HUB_PORT`, `HUB_HOST` — Server binding
- `DATA_DIR` — Where tasks and pipeline JSON files are stored
- `AGENT_HOST` — `docker` or `aws`
- `PIPELINE_IMAGE` — Docker image for coding agents
- `HUB_URL` — Hub URL accessible by agents (for write-back calls)
- `GIT_REPO_URL`, `GIT_USERNAME`, `GIT_TOKEN` — Git credentials for agents
- `GH_USERNAME`, `GH_TOKEN` — GitHub credentials
- `DEBUG=1` — Verbose shell script output

## Testing Notes

- Unit/integration tests use `vitest` with `supertest`; they set `DATA_DIR` to a temp directory (`test/.data-test/`) and spin up the Express app directly
- Playwright e2e tests require the hub to be running; base URL defaults to `http://localhost:8080`
- `pipeline-run.spec.js` has a 10-minute timeout and exercises a real coding pipeline
- Mock pipeline modes (`instant`, `fail`, `hang`) are supported via the `script` field on pipeline creation for testing
