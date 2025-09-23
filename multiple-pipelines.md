## Requirements for supporting multiple pipelines per task

We need to conceptually separate pipeline management from task management.
Each task should have multiple pipelines.
The UI should still display the last pipeline as the default pipeline for a task, but it should be possible to stop a pipeline and start another one.
The task details page should allow us to view previous pipelines and their logs.
The UI should not enable starting multiple pipelines for the same task, but the backend should support it.
Pipelines should be able to run concurrently on the same task, and the system should handle any conflicts that arise. This includes each pipeline for the same task should having a different name.
We should not keep the status of the pipelines in the hub, but should rely on agents.sh to query it on demand.

## Implementation Plan: Multiple Pipelines Management

### 1. Existing Management of Tasks, Pipelines, and Agents

#### Tasks
- Tasks are managed via the `tasks.mjs` file in the `hub/src/routes/` directory.
- Task data is stored as JSON files in the `demo-data/tasks/` directory (or `/data/tasks` in Docker).
- The current API supports CRUD operations for tasks, but pipelines are not explicitly managed.
- Tasks have a `status` field, which is updated to `in-progress` to trigger the pipeline.

#### Pipelines
- Pipelines are triggered via the `pipelines.sh` script when a task's status is updated to `in-progress`.
- There is no explicit API for managing pipelines; they are indirectly controlled through task updates.
- Pipeline state (e.g., running, stopped, completed) is not persisted, and the system relies on the `pipelines.sh` script for runtime information.

#### Agents
- Agents are managed via shell scripts (`agents.sh`, `agents-docker.sh`, `agents-aws.sh`).
- These scripts handle Docker container operations (e.g., start, stop, status) and are invoked by the pipeline scripts.
- There is no direct integration between agents and the task/pipeline management API.

### 2. New API

#### Goals
- Separate pipeline management from task management.
- Allow multiple pipelines per task, with only one active pipeline at a time.
- Provide endpoints for creating, starting, stopping, and querying pipelines.
- Persist pipeline metadata for UI and history.
- Use `pipelines.sh` and `agents.sh` for runtime operations.

#### Proposed Endpoints

##### Pipeline-Specific Endpoints
- **GET /pipelines?task=<task_id>**: List all pipelines for a task.
- **POST /pipelines**: Create and start a new pipeline for a task. Request body includes `taskId` and optional parameters.
- **GET /pipelines/:pipelineId**: Get details of a specific pipeline.
- **POST /pipelines/:pipelineId/stop**: Stop a running pipeline.
- **GET /pipelines/:pipelineId/status**: Get the live status of a pipeline.
- **GET /pipelines/:pipelineId/logs**: Fetch logs for a pipeline.

#### Behavioral Rules
- **Single Active Pipeline**: Only one pipeline can be active per task. Starting a new pipeline stops the current one unless explicitly allowed.
- **State Management**: Persist pipeline metadata (e.g., status, timestamps, container/volume names) and rely on `pipelines.sh` for runtime state.
- **Conflict Avoidance**: Use unique workspace volumes and container names per pipeline. Each pipeline should have a distinct identifier that includes the task_id, but also another unique number. Try to make this number sequential for easier tracking.

### 3. Decide Which Files Should Be Modified

#### Backend
- **`hub/src/routes/tasks.mjs`**
  - Update task endpoints to integrate with the new pipeline API.
- **`hub/src/routes/pipelines.mjs`** (new file)
  - Implement the new pipeline-specific endpoints.
  - Manage pipeline metadata and delegate runtime operations to `pipelines.sh` and `agents.sh`.

#### Scripts
- **`hub/pipelines.sh`**
  - Update to support multiple pipelines per task.
  - Add commands for querying pipeline status and logs.
- **`hub/agents.sh` and `hub/agents-docker.sh`**
  - Ensure compatibility with the new pipeline management logic.

#### Data Storage
- **`demo-data/pipelines/`** (new directory)
  - Store pipeline metadata as JSON files.
  - Use a structure like `{ pipelineId }.json`.

#### UI
- **`hub/ui/`**
  - Update the UI to display the last pipeline for a task in the main page.
  - Update the UI to display multiple pipelines per task in the details page.
  - If a pipeline is active, show its status and provide controls for stopping it.
  - If no pipeline is active, provide an option to start a new pipeline.
  - If there is an active pipeline or there has been one, show a button to view the pipeline details.
  - on the pipeline.html page, show the last pipeline details and a dropdown of previous pipelines to select from and navigate to the details of those pipelines.

### 4. Next Steps
- Implement the new `pipelines.mjs` file.
- Update `tasks.mjs` to integrate with the pipeline API.
- Modify `pipelines.sh` and `agents.sh` to support the new functionality.
- Update the UI to reflect the changes.

