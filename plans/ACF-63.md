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

The `devcontainer` CLI must be available in the environment. It is installable via:
```
npm install -g @devcontainers/cli
```

Add a check at the top of the script:
```bash
command -v devcontainer >/dev/null 2>&1 || error_exit "devcontainer CLI not found (npm install -g @devcontainers/cli)"
```

## Non-goals

- No changes to the generated Dockerfile structure or agent install logic
- No changes to `--type`, `--tag`, `--push` flags
- No support for docker-compose devcontainers (out of scope; `devcontainer build` handles single-container configs)

## Acceptance criteria

- `worker-builder build --devcontainer ./my-project --type claude` calls `devcontainer build --workspace-folder ./my-project --image-name worker-base-claude:latest` then `docker build` using that image as the base
- All existing `.bats` tests pass with updated mocks
- A project whose devcontainer uses `build.dockerfile` (not `image`) now builds correctly instead of silently falling back to the default base image
