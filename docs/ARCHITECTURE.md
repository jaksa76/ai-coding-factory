# Architecture

This document describes the system architecture of the AI Coding Factory. It is the authoritative reference for how components fit together, how data flows through the system, and why key design decisions were made.

---

## System Overview

The AI Coding Factory automates software development through AI agents that work on tasks organised into projects. A browser-based UI lets operators observe progress, review stage outputs, and approve or reject agent-produced artefacts.

The system is built from a small number of composable parts:

```
┌─────────────────────────────────────────────────────────┐
│                     Browser (UI)                        │
│          static HTML/JS served by the Hub               │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP/REST
┌────────────────────────▼────────────────────────────────┐
│                   Hub (Express)                         │
│  REST API · static file serving · shell orchestration   │
│  src/app.mjs · src/routes/ · src/pipelines-store.mjs    │
└──────┬──────────────────────────────────────┬───────────┘
       │ reads/writes JSON files              │ spawns via zx
       │                                     │
┌──────▼──────────────┐            ┌──────────▼───────────┐
│   File Store        │            │    pipelines.sh       │
│  $DATA_DIR/         │            │  runtime facade for   │
│    projects/        │            │  container lifecycle  │
│    tasks/           │            └──────────┬────────────┘
│    pipelines/       │                       │ calls
└─────────────────────┘            ┌──────────▼────────────┐
                                   │      agents.sh         │
                                   │  Docker / AWS ECS      │
                                   │  container management  │
                                   └──────────┬─────────────┘
                                              │ runs
                                   ┌──────────▼─────────────┐
                                   │  coding-pipeline        │
                                   │  (Docker container)     │
                                   │  pipeline.sh            │
                                   │  pipeline-client.sh ───►│──► Hub REST API
                                   └────────────────────────┘
```

---

## Components

### Browser UI

- Static HTML + vanilla JavaScript files in `hub/ui/`.
- Served directly by the Express hub; no separate web server.
- Communicates exclusively with the Hub REST API. No direct access to the file store or shell scripts.
- Auto-refreshes the board while any pipeline is active.

### Hub (Express)

- Node.js ESM application in `hub/src/`.
- **`app.mjs`** — Express app factory; mounts middleware and routes. Used directly by tests.
- **`server.mjs`** — process entry point; starts the HTTP listener.
- **`routes/tasks.mjs`** — task CRUD over the file store.
- **`routes/pipelines.mjs`** — pipeline lifecycle endpoints; orchestrates the file store and `pipelines.sh`.
- **`src/pipelines-store.mjs`** — all pipeline file I/O in one place (create, read, list, update pipeline and stage records).
- Shell scripts are invoked via `zx` for container start/stop/status/logs.
- `process.env.DATA_DIR` controls the root of the file store (default `/tmp/ai-coding-factory`).

### File Store

File-backed persistence; no database. Each entity is a separate JSON file:

```
$DATA_DIR/
  projects/   <project_id>.json
  tasks/      <task_id>.json
  pipelines/  <pipeline_id>.json   ← stages embedded as array
```

See [DATA_MODEL.md](DATA_MODEL.md) for the full entity schema.

Advantages: trivially testable (set `DATA_DIR` to a temp dir), human-readable, no external dependency.

### `pipelines.sh`

A thin bash facade over the container runtime. Knows nothing about the file store. Supported commands:

| Command | Effect |
|---|---|
| `start` | Creates a Docker volume and starts the pipeline container |
| `stop` | Stops the running container |
| `status` | Reports live container status |
| `logs` | Streams container logs |
| `list` | Lists containers matching a task ID |

Called by the Hub via `zx` when a pipeline is started, stopped, or queried for live status/logs.

### `agents.sh` / `agents-docker.sh` / `agents-aws.sh`

Low-level container management primitives (`create-volume`, `start-container`, `stop-container`, `logs-container`, `list-containers`). Called by `pipelines.sh`, not directly by the Hub.

### `coding-pipeline` (Docker container)

The AI agent that actually implements tasks. Runs `pipeline.sh` inside the container. Uses `pipeline-client.sh` to report progress back to the Hub.

### `pipeline-client.sh`

A bash HTTP client (using `curl`) that the pipeline agent calls to update pipeline and stage state in the Hub. It is the **only** way the agent writes back to the system — the agent does not touch the file store directly. This also means the same update mechanism works identically in local-Docker and remote-container (AWS ECS) deployments.

---

## Key Design Decisions

### Hub is the single source of truth for pipeline state

The problem with querying the container runtime (e.g., `docker ps`) to list pipelines is that it is slow, depends on Docker being reachable, and loses all stage-level information the moment a container exits.

Instead, the Hub writes a pipeline JSON record to disk the moment a pipeline is created and updates it in place as the pipeline progresses. The container runtime is queried only for live status and log streaming — exactly where it adds value.

### No extra bash orchestration layer

An earlier option considered having a second bash script sit between `pipelines.sh` and the Hub to manage file state. This was rejected because:
- The Hub already is the REST service.
- The Hub already manages file state for tasks.
- Adding a bash middleman would duplicate logic and create two sources of truth.

The clean split is: **Hub owns file state; `pipelines.sh` owns runtime state.**

### `pipeline-client.sh` as the agent's write path

The agent (running inside Docker) cannot safely write to the shared file store directly — it may run on a remote host. Routing all writes through the Hub REST API gives us:
- A single authorised write path with validation.
- Identical behaviour in all deployment environments (local Docker, AWS ECS).
- Logging/auditing of all state changes in one place.

---

## Data Flow: Starting a Pipeline

```
User clicks "Start Pipeline" in UI
  → POST /api/pipelines  {taskId, description}
      Hub creates pipeline JSON on disk (status: pending)
      Hub calls pipelines.sh start --task-id … --pipeline-id …
        pipelines.sh calls agents.sh start-container …
          Docker container starts running pipeline.sh
      Hub updates pipeline JSON (status: running)
      Hub returns 201 {id: pipelineId}
  ← UI receives id, begins polling /api/pipelines/:id/status
```

## Data Flow: Agent Reporting Progress

```
  pipeline.sh (inside container)
    → pipeline-client.sh update-stage \
        --pipeline-id $PIPELINE_ID \
        --position 0 --name "planning" --status "in_progress"
      curl PUT /api/pipelines/:id/stages/0
        Hub upserts stage in pipeline JSON on disk
        Hub returns updated pipeline record
    → ... agent does work ...
    → pipeline-client.sh update-stage … --status "needs_review" --content "…plan text…"
    → pipeline-client.sh update-pipeline … --status "completed"
```

## Data Flow: Listing Pipelines

```
User loads task detail in UI
  → GET /api/pipelines?task=<taskId>
      Hub reads $DATA_DIR/pipelines/<taskId>_pipeline_*.json
      Returns array of pipeline objects (no container runtime query)
  ← UI renders pipeline list with stage chips
```

---

## API Surface (Hub REST)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/projects` | List all projects |
| `POST` | `/api/projects` | Create project |
| `GET` | `/api/projects/:id` | Get project |
| `PUT` | `/api/projects/:id` | Update project |
| `DELETE` | `/api/projects/:id` | Delete project |
| `GET` | `/api/tasks` | List all tasks |
| `POST` | `/api/tasks` | Create task |
| `GET` | `/api/tasks/:id` | Get task |
| `PUT` | `/api/tasks/:id` | Update task |
| `DELETE` | `/api/tasks/:id` | Delete task |
| `POST` | `/api/tasks/import/jira` | Import tasks from Jira |
| `GET` | `/api/pipelines?task=<id>` | List pipelines for a task (from disk) |
| `POST` | `/api/pipelines` | Create and start a pipeline |
| `PUT` | `/api/pipelines/:id` | Update pipeline top-level fields (status, etc.) |
| `PUT` | `/api/pipelines/:id/stages/:position` | Upsert a stage by position |
| `POST` | `/api/pipelines/:id/stop` | Stop a running pipeline |
| `GET` | `/api/pipelines/:id/status` | Live status from container runtime |
| `GET` | `/api/pipelines/:id/logs` | Live logs from container runtime |

---

## Deployment

The Hub is packaged as a Docker image (`hub/Dockerfile`). Configuration is entirely via environment variables:

| Variable | Default | Description |
|---|---|---|
| `DATA_DIR` | `/tmp/ai-coding-factory` | Root of the file store |
| `PORT` | `8080` | HTTP listener port |
| `DEBUG` | _(unset)_ | Set to any value to enable verbose `zx` shell output |
| `GIT_REPO_URL` | _(unset)_ | Git repo URL passed through to pipeline containers |
| `GIT_USERNAME` | _(unset)_ | Git username passed through to pipeline containers |
| `GIT_TOKEN` | _(unset)_ | Git token passed through to pipeline containers |
| `GH_TOKEN` | _(unset)_ | GitHub Copilot token passed through to pipeline containers |
| `GH_USERNAME` | _(unset)_ | GitHub username for Copilot access |

The Hub container requires the Docker socket (`/var/run/docker.sock`) mounted to manage pipeline containers locally. For AWS deployments, `agents-aws.sh` takes the place of `agents-docker.sh`.

---

## Testing

- Unit/integration tests live in `hub/test/` and use **vitest** + **supertest**.
- Tests set `process.env.DATA_DIR` to an isolated temp directory before importing `app.mjs`, so no real data is touched.
- Shell script calls (`pipelines.sh`, `agents.sh`) are not invoked in tests; the file store layer is exercised directly.
- Run tests: `npm test` from the `hub/` directory.
