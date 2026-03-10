# Plan: ACF-69 — Make loop easier to run in the current container

## Problem

Running `loop` inside a devcontainer today requires setting `GIT_REPO_URL`, `GIT_USERNAME`, and `GIT_TOKEN` — even if the container already has the repo checked out with git credentials configured. This creates unnecessary friction for the common "run loop inside the project devcontainer" use case.

Currently, `loop` already detects when it's running inside the target repo (lines 423–431 of `loop/loop`) and sets `WORK_DIR` to the git root. However, it still fails early at the env var validation block (lines 82–84) if those variables are unset.

## Goal

Allow `loop` to run without `GIT_REPO_URL`, `GIT_USERNAME`, and `GIT_TOKEN` when it's already inside the target git repository and git can push without extra credentials.

## Approach

### 1. Auto-detect `GIT_REPO_URL` from the current git remote

If `GIT_REPO_URL` is not set, attempt to read it from `git remote get-url origin`. If the current directory is not inside a git repo, fail with a clear error message.

```bash
if [[ -z "${GIT_REPO_URL:-}" ]]; then
    GIT_REPO_URL="$(git remote get-url origin 2>/dev/null)" \
        || error_exit "GIT_REPO_URL is not set and no git remote 'origin' found"
fi
```

Move this detection to before the validation block so the auto-detected value is available.

### 2. Make `GIT_USERNAME` and `GIT_TOKEN` optional

These are only needed by `setup_git_credentials` to configure HTTPS auth. If they are absent, skip that step entirely — the container may already have credentials via SSH keys, an existing credential helper, or a token baked in.

Change the validation from hard errors to optional:
```bash
# Only required when using HTTPS with no pre-configured credentials
# (GIT_USERNAME and GIT_TOKEN are optional if git can already push)
```

`setup_git_credentials` already gates on `GIT_REPO_URL` starting with `https://`, so it only modifies git config when needed. Make it also gate on `GIT_USERNAME` being set:

```bash
setup_git_credentials() {
    if [[ "$GIT_REPO_URL" == https://* ]] && [[ -n "${GIT_USERNAME:-}" ]] && [[ -n "${GIT_TOKEN:-}" ]]; then
        # ... existing credential store setup ...
    fi
}
```

### 3. Skip clone/pull when already in the target repo

The `clone_or_pull` function always runs. When `WORK_DIR` is the current git root (in-container case), a `git pull` is acceptable but might be surprising. Keep the pull — it's safe and keeps the repo up to date — but no structural change needed here.

### 4. Update `configure_git_identity` to handle missing vars

`configure_git_identity` references `$GIT_USERNAME` and `$JIRA_EMAIL`. When those are absent, fall back to existing git config if already set:

```bash
configure_git_identity() {
    if [[ -n "${GIT_USERNAME:-}" ]]; then
        git config --global user.name "$GIT_USERNAME"
    fi
    # ... similar for email ...
}
```

### 5. Update the usage/help text

Add a note that `GIT_REPO_URL`, `GIT_USERNAME`, and `GIT_TOKEN` are optional when running inside a git repository with credentials already configured.

## Files to change

- `loop/loop` — main script: env detection, validation, `setup_git_credentials`, `configure_git_identity`, usage text
- `loop/loop.bats` — add unit tests for the auto-detect path (mock `git remote get-url`)
- `loop/loop-integration.bats` — no changes needed (integration tests always set all vars)

## Test cases to add (loop.bats)

1. `GIT_REPO_URL` not set but inside a git repo → auto-detected from remote, loop proceeds
2. `GIT_REPO_URL` not set and not in a git repo → fails with clear error
3. `GIT_USERNAME`/`GIT_TOKEN` not set → `setup_git_credentials` skipped, loop proceeds
4. All three absent in an in-container scenario → succeeds (covers the happy path)

## Out of scope

- SSH-specific credential handling (not needed; existing credential store logic is HTTPS-only)
- Changing how workers (Dockerfile entrypoints) are invoked — they always set all vars explicitly
