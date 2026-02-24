# Testing Strategy

This document describes the test levels for the AI Coding Factory, the rationale for each, the role of the mock coding agent, and the conventions tests must follow.

---

## Goals

- Each level tests a meaningfully larger slice of the real system than the level below it.
- Level 1 tests must be runnable in any environment that has Docker; they must not require AI credentials or external network access.
- Level 2 tests exercise real AI behaviour; they require credentials and are run deliberately, not on every commit.
- Each level catches a different class of defect. Adding more levels is only justified when those defects are not already caught at a cheaper level.

---

## Test Levels

### Level 1 — Integration Tests (REST API + persistence + real Docker + mock pipeline)

**What is tested end-to-end:**

- The full Hub REST API surface via real HTTP requests (supertest bound to a real port).
- File-store persistence: pipeline and task records written to a temp `DATA_DIR` are read back correctly.
- The real `pipelines.sh` → `agents.sh` → Docker container lifecycle: volume creation, container start, container stop, log retrieval, container listing.
- Pipeline state machine: create → running → stage-by-stage progress → completed / failed / stopped.
- Agent callback path: the mock container calls `PUT /api/pipelines/:id` and `PUT /api/pipelines/:id/stages/:position`; the Hub persists the results to disk.
- Error handling: missing fields, invalid IDs, stop of a completed pipeline.

**What is NOT tested:**

- Real AI model behaviour or output quality.
- Real git repository operations.
- Browser UI.

**The mock pipeline image (`mock-coding-pipeline:test`):**

A minimal Docker image built from `mock-coding-pipeline/`. Its `mock-pipeline.sh` accepts the same environment variables as `pipeline.sh` (`TASK_ID`, `PIPELINE_ID`, `HUB_URL`) and executes the same stage sequence — cloning, refining, planning, implementing, deploying, verifying — by calling the Hub REST API directly:

```
PUT /api/pipelines/:id/stages/:position  { name, status: "in_progress" }
<short sleep>
PUT /api/pipelines/:id/stages/:position  { name, status: "completed", content: "<canned output>" }
```

After all stages it calls `PUT /api/pipelines/:id  { status: "completed" }`.

Behaviour is controlled by the `MOCK_MODE` env var:

| Mode | Behaviour |
|---|---|
| `success` (default) | All stages complete; pipeline ends `completed`. |
| `fail_at_<stage>` | Marks the named stage `failed`; calls pipeline `failed`; exits. |
| `hang` | Marks the first stage `in_progress` then blocks indefinitely. Used to test the stop path. |
| `instant` | Same as `success` but with no sleeps. For tests that only need a pipeline to exist. |

**Hub URL inside Docker:**

The Hub must be reachable from inside the mock container. Integration tests bind the Hub to a real OS port (using `app.listen(0)` to get a random free port). The Hub address is passed to `pipelines.sh start` via the `--hub-url` flag (forwarded as `HUB_URL` env var into the container). On Linux the Docker bridge gateway (`172.17.0.1`) is the default; on Docker Desktop `host.docker.internal` is used instead.

**Directory layout:**

```
mock-coding-pipeline/
  Dockerfile              # lightweight image (curl + bash)
  mock-pipeline.sh        # HTTP callbacks → Hub REST API

hub/
  test/
    tasks.test.mjs                  # existing: task CRUD
    pipelines.test.mjs              # existing: basic validation (no Docker)
    pipeline-lifecycle.test.mjs     # NEW: full lifecycle with mock Docker container
```

**Key scenarios for `pipeline-lifecycle.test.mjs`:**

1. Start a pipeline → Hub writes pipeline record (`status: pending`) → container starts.
2. Mock agent progresses through all stages → each `PUT` is persisted to disk → `GET /api/pipelines/:id` returns updated record.
3. `GET /api/pipelines?task=<id>` returns the pipeline from disk (not Docker).
4. `GET /api/pipelines/:id/status` returns the Docker container status while running.
5. `GET /api/pipelines/:id/logs` streams real container stdout.
6. Pipeline completes → Hub record shows `status: completed` with all six stages.
7. Mock agent in `fail_at_planning` mode → Hub record shows `status: failed` at the planning stage.
8. Stop a `hang`-mode pipeline → container is killed → Hub record updated to `stopped`.
9. Two concurrent pipelines for the same task produce independent records and containers.

**Pre-requisite:**

```bash
docker build -t mock-coding-pipeline:test mock-coding-pipeline/
```

**Tools:** vitest, supertest, fs-extra (already in use). Docker must be available.

**Running:**

```bash
cd hub && npm test
```

---

### Level 2 — E2E Tests (Browser UI → Hub → real coding agent → real git repo)

**What is tested end-to-end:**

- The browser UI in a real browser (Playwright).
- All HTTP calls from the UI to the running Hub.
- The Hub spawning the real `coding-pipeline:latest` container running the real `pipeline.sh`.
- The real GitHub Copilot CLI (`gpt-4.1` model) performing actual coding work against a real git repository.
- Stage progress reported back to the Hub and reflected in the UI without a page reload.
- Final artefacts (code changes, PR, deployment summary) visible in the pipeline detail view.

**What is NOT tested:**

- Code quality of the AI output (these tests assert that the pipeline completes, not what it produces).
- AWS/ECS deployment path.

**Model selection:**

`gpt-4.1` is used in all E2E tests (already configured in `pipeline.sh` via the `--model gpt-4.1` flag). This avoids charges from more expensive models while still exercising the real agent path.

**Required credentials and environment:**

| Variable | Purpose |
|---|---|
| `GH_TOKEN` | GitHub Copilot CLI authentication |
| `GH_USERNAME` | GitHub username for Copilot |
| `GIT_REPO_URL` | A real git repository the agent can clone and push to |
| `GIT_USERNAME` | Git credentials |
| `GIT_TOKEN` | Git credentials |

These are provided via `.env.e2e` (gitignored) or CI secrets and loaded by the E2E test setup.

**Infrastructure setup per E2E run:**

1. Start the Hub as a real HTTP server (`DATA_DIR` set to a temp dir; all credentials forwarded).
2. Launch Playwright against the Hub's port.
3. Each test uses a freshly created task with its own pipeline; isolation is via `DATA_DIR` sub-directories.
4. After the suite, stop the Hub and prune containers and volumes created during the run.

**Directory layout:**

```
hub/
  e2e/
    tasks.spec.ts           # task list: create, edit, delete, filter, search
    pipeline.spec.ts        # full pipeline lifecycle in the UI
    fixtures/
      hub-server.ts         # start/stop Hub process; loads .env.e2e; manages DATA_DIR
```

**Key scenarios for `pipeline.spec.ts`:**

1. Create a task in the UI → click Start Pipeline → container starts → pipeline row appears.
2. Stage chips update progressively in the task list without page reload.
3. Navigate to pipeline detail page → logs panel streams real container stdout.
4. Agent completes all stages → final status `completed` visible in both list and detail views.
5. Click Stop on a running pipeline → container is gone → status updated.
6. Start a second pipeline for the same task → both appear in the pipeline selector on the detail page.

**Tools:** Playwright (to be added to `devDependencies`).

**Running:**

```bash
cd hub && npm run test:e2e
```

E2E tests are not run in standard CI. They are run manually or in a dedicated CI job gated on credential availability.

---

## When to Add More Levels

| Situation | Suggested addition |
|---|---|
| A function has complex branching logic independent of I/O | Unit test in `test/unit/` with vitest |
| Shell scripts need isolated testing | Bats (Bash Automated Testing System) in `test/shell/` |
| Performance or load characteristics matter | k6 or autocannon load tests, separate from CI |
| AWS/ECS deployment path changes | Integration test using `agents-aws.sh` against a real ECS dev cluster |

---

## Conventions

- Integration tests bind the Hub to a real port (not just in-memory supertest). This is required so the mock container can call back to the Hub.
- Each test file sets `process.env.DATA_DIR` to its own isolated temp directory before importing `app.mjs`.
- The Hub is configured to use the mock image in Level 1 via `process.env.PIPELINE_IMAGE=mock-coding-pipeline:test`.
- No test ever writes to `/tmp/ai-coding-factory`; that path is reserved for manual development use.
- Container and volume names created during tests use a `test-` prefix so `clean-local-containers.sh` can target them safely.
- Mock pipeline containers must exit with code 0 in `success` and `fail_at_*` modes. A non-zero exit not triggered by `MOCK_MODE` signals a test infrastructure problem.
