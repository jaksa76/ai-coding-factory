# AI Coding Factory - Copilot Instructions

Short, focused instructions to help an AI coding agent be immediately productive in this repository.

## Big picture
- This is a small monorepo with two main pieces:
  - `hub/`: an Express (Node.js ESM) control-plane that exposes a REST API and serves static UI from `hub/ui/`.
  - `coding-pipeline/`: Dockerized pipeline scripts and helpers orchestrated from the `hub` via shell scripts.
- The `hub` stores tasks as JSON files in `$DATA_DIR/tasks` (default `/tmp/ai-coding-factory`), or `hub/demo-data/tasks` in dev. Shell scripts (`pipelines.sh`, `agents.sh`) are invoked via `zx` from the server.

## Why the structure
- File-backed storage keeps the project simple and testable without a DB. The server shells out to pipeline scripts so the orchestration is explicit and easy to stub in tests.

## Key files to read first
- `hub/src/app.mjs` — app factory, middleware, route mounting.
- `hub/src/routes/tasks.mjs` — task CRUD, import/jira endpoint, task id generation and status update logic.
- `hub/src/routes/pipelines.mjs` — pipeline list/start/stop/status/log endpoints, pipeline id format.
- `hub/ui/index.html` and `hub/ui/pipeline.html` — frontend expectations for API shapes.
- `pipelines.sh`, `agents.sh`, `agents-docker.sh` — shell scripts invoked by the server (see `zx` usage in routes).
- `hub/test/*.mjs` — concise examples of required API behavior and edge cases.

## API contracts & important shapes (be strict)
- Tasks API (`hub/src/routes/tasks.mjs`):
  - `GET /api/tasks` → array of task objects stored as JSON files.
  - `POST /api/tasks` → create task; returns `{ id, description, status }`. POST to `/api/tasks/:id` returns 405 (not allowed).
  - `GET /api/tasks/:id`, `PUT /api/tasks/:id` (PUT without id → 400), `DELETE /api/tasks/:id`.
  - `POST /api/tasks/import/jira` → accepts `{ site, email, token, project }` and calls `jira.sh`.
  - Task id format: `task_${Date.now()}_${process.pid}` (see `generateId`).

- Pipelines API (`hub/src/routes/pipelines.mjs`):
  - `GET /api/pipelines?task=<taskId>` → returns an array of objects `{ id }`. The list contains pipeline ids, not statuses.
  - `POST /api/pipelines` → create/start pipeline. Body must include `{ taskId, description }`; returns `201` with `{ id }`.
  - `POST /api/pipelines/:pipelineId/stop` → stops a pipeline. Pipeline id must match `^(.+)_pipeline_\d+$` (extracts taskId).
  - `GET /api/pipelines/:pipelineId/status` and `/logs` → return text/plain output from the underlying script.
  - Pipeline id format: `${taskId}_pipeline_${Date.now()}` (see `generatePipelineId`).

## Code patterns & conventions
- Source files in `hub/src` use ESM `.mjs` modules — keep imports/exports as ESM.
- `zx` is used to run shell scripts; `$.verbose` is toggled by `process.env.DEBUG`.
- Tests use `vitest` + `supertest`. Tests may set `process.env.DATA_DIR` before importing `app` to isolate state.
- The UI is static HTML with inline JavaScript in `hub/ui/` and calls API endpoints directly; keep API contracts stable when changing routes.


## Developer workflow

### Scripts (pipelines, agents, jira)

Testing is performed manually by running the scripts directly. There is no automated test mechanism for now.

### Hub Backend

Run the tests with `npm test` in `hub/`.

### Hub UI

Run the server with `npm run dev` in `hub/` and open `http://localhost:8080` in a browser.

### Coding Pipeline

Build the docker image using `docker build -t coding-pipeline coding-pipeline/`.


## Editing guidance — safe, minimal changes
- If you change pipeline start/stop semantics, update both `hub/src/routes/pipelines.mjs` and `pipelines.sh` to keep the API contract consistent.
- When changing task state handling in `tasks.mjs`, keep the same HTTP semantics (status codes) used in tests: 400 for missing ID/invalid JSON, 405 for POST with ID, 404 when resources missing.
- Prefer updating the small JSON files under `demo-data/tasks/` for local manual testing.

## Integration points / external dependencies
- Shell scripts: `pipelines.sh`, `agents.sh`, and `jira.sh`.
- Docker: pipeline runner expects Docker available when starting actual containers.
- No external DB; persistence is file-backed under `$DATA_DIR/tasks`.

