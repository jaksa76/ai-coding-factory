# ACF-63: Make image-builder use the devcontainer CLI tool

## Problem

`worker-builder` currently builds worker images by:
1. Reading `devcontainer.json` manually (stripping `//` comments, parsing with `jq`)
2. Extracting only the `image` field — it **ignores** `build.dockerfile`, `dockerComposeFile`, and all other devcontainer config forms
3. Using that image as `FROM` in a hand-generated Dockerfile
4. Running `docker build` directly

This means it silently falls back to a generic default image for any project whose devcontainer uses a Dockerfile. Using the official `devcontainer` CLI fixes all of that.

## Solution

Replace the manual parse-and-build pipeline with two steps:
1. **`devcontainer build`** — build the project's devcontainer image (handles `image`, `build.dockerfile`, `dockerComposeFile`, features, etc.)
2. **`docker build`** — layer the agent CLI + `loop` + `task-manager` on top of the resulting image

## Changes

### `worker-builder/worker-builder`

- Change `--devcontainer <path-to-devcontainer.json>` → `--devcontainer <workspace-folder>` (folder, not file — matches how the devcontainer CLI works)
- Replace the manual JSON-parsing block with:
  ```bash
  BASE_TAG="worker-base-${AGENT}:latest"
  devcontainer build \
      --workspace-folder "$DEVCONTAINER_ARG" \
      --image-name "$BASE_TAG"
  BASE_IMAGE="$BASE_TAG"
  ```
- Remove the `sed`/`jq` comment-stripping logic entirely
- Remove the `DEFAULT_BASE` fallback (the devcontainer CLI handles missing/minimal configs natively)
- Update the `FROM` line in the generated Dockerfile to use `$BASE_IMAGE` as before (no change needed there)
- Update usage/help text to say `--devcontainer <workspace-folder>`

### `worker-builder/worker-builder.bats`

- Update tests that mock `docker build` to also mock `devcontainer build`
- Update argument description tests to reflect the new `<workspace-folder>` language
- Remove tests for the JSON-parsing / comment-stripping logic
- Add a test that verifies `devcontainer build --workspace-folder ... --image-name ...` is called with the right args
- Keep tests for Dockerfile generation (FROM, agent installs, ENTRYPOINT) — they don't change

## Dependency

The `devcontainer` CLI is installed automatically if not present. Add this near the top of the script (after the helper functions):
```bash
if ! command -v devcontainer >/dev/null 2>&1; then
    echo "devcontainer CLI not found — installing via npm..."
    npm install -g @devcontainers/cli
fi
```

This keeps the script self-contained so workers and CI environments don't need to pre-install it.

### `worker-builder/worker-builder-integration.bats`

Add a new integration test file (skipped when Docker or network is unavailable) that:

1. Creates a minimal temporary workspace with a `.devcontainer/devcontainer.json` that uses a small base image (e.g. `ubuntu:22.04`).
2. Runs `worker-builder build --devcontainer <tmpdir> --type claude --tag test-worker-integration:latest` against the real `devcontainer` CLI and real `docker build`.
3. Runs the built image with `docker run --rm test-worker-integration:latest <tool> --version` for each expected tool:
   - `loop` (the work loop script)
   - `task-manager` (the task manager wrapper)
   - `claude` (the agent CLI)
4. Asserts each command exits 0 and produces recognisable output.
5. Cleans up: removes the image and the temp workspace on exit.

Skip conditions (use `skip` at the top of the test file):
```bash
if ! command -v docker >/dev/null 2>&1; then skip "docker not available"; fi
```

## Non-goals

- No changes to the generated Dockerfile structure or agent install logic
- No changes to `--type`, `--tag`, `--push` flags
- No support for docker-compose devcontainers (out of scope; `devcontainer build` handles single-container configs)

## Acceptance criteria

- `worker-builder build --devcontainer ./my-project --type claude` calls `devcontainer build --workspace-folder ./my-project --image-name worker-base-claude:latest` then `docker build` using that image as the base
- If `devcontainer` is not installed, the script installs it via `npm install -g @devcontainers/cli` and continues without user intervention
- All existing `.bats` unit tests pass with updated mocks
- A project whose devcontainer uses `build.dockerfile` (not `image`) now builds correctly instead of silently falling back to the default base image
- The integration test builds a real image, runs it, and confirms `loop`, `task-manager`, and the agent CLI are all present and executable inside the container
