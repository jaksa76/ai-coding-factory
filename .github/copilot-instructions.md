# AI Coding Factory - Copilot Instructions

This document provides guidance for AI coding agents working in the `ai-coding-factory` repository.

## Architecture Overview

The `ai-coding-factory` is a monorepo containing two main components:

1.  **`hub/`**: A Node.js Express server that acts as the central control plane.
    *   **API**: Exposes a REST API for managing `tasks`. The API is defined in `hub/src/routes/`.
        *   `hub/src/routes/tasks.mjs` is the core of the API, handling CRUD operations for tasks.
        *   Task data is stored as JSON files in the `demo-data/tasks/` directory (for development) or `/data/tasks` in the Docker container.
    *   **UI**: Serves a static UI from the `hub/ui/` directory.
    *   **Scripts**: Contains shell scripts (`agents.sh`, `pipelines.sh`) for interacting with AI agents and coding pipelines.
2.  **`coding-pipeline/`**: A Dockerized coding pipeline.
    *   `coding-pipeline/pipeline.sh` defines the stages of the pipeline (refining, planning, implementing, deploying, verifying).
    *   This pipeline is triggered by the `hub` when a task's status is updated to `in-progress`.

### Data Flow

1.  A user creates a task via the UI, which calls the `POST /api/tasks` endpoint in the `hub`.
2.  The `hub` creates a new JSON file for the task in the `tasks` directory.
3.  When a task is ready to be worked on, the UI updates the task's status to `in-progress` via `PUT /api/tasks/:id`.
4.  The `hub` then executes the `pipelines.sh` script, passing the task ID and description.
5.  The `pipelines.sh` script (currently a placeholder) would then invoke the `coding-pipeline` to perform the actual coding work.

## Developer Workflow

### Prerequisites

*   Node.js (v18+)
*   Docker

### Running the Hub

To run the `hub` server in development mode:

```bash
npm run dev
```

This will start the server with `nodemon` and use the `demo-data` directory for task storage.

### Running Tests

The `hub` uses `vitest` for testing. To run the tests:

```bash
npm test
```

The tests are located in `hub/test/` and use `supertest` to make requests to the API. The test data directory is `hub/test/.data-test`.

### Building and Running with Docker

To build the `hub` Docker image:

```bash
docker build -t ai-coding-factory-hub .
```

To run the `hub` container:

```bash
docker run -p 8080:8080 -v /var/run/docker.sock:/var/run/docker.sock -v $(pwd)/demo-data:/data ai-coding-factory-hub
```

## Conventions

*   The `hub` uses ES Modules (`.mjs`).
*   The `zx` library is used for running shell commands within the Node.js application.
*   API routes are defined in separate files in `hub/src/routes/`.
*   The `fs-extra` library is used for file system operations.

## Key Files

*   `hub/src/app.mjs`: Express app factory, used by both the server and tests.
*   `hub/src/server.mjs`: The main entry point for the `hub` server.
*   `hub/src/routes/tasks.mjs`: The core logic for the `tasks` API.
*   `hub/test/tasks.test.mjs`: Tests for the `tasks` API.
*   `coding-pipeline/pipeline.sh`: The main script for the coding pipeline.
*   `hub/Dockerfile`: Dockerfile for the `hub` server.
*   `coding-pipeline/Dockerfile`: Dockerfile for the coding pipeline.
