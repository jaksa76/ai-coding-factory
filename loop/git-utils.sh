#!/usr/bin/env bash
# git-utils.sh — shared git helpers for loop/plan/implement
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/git-utils.sh"

setup_git_credentials() {
    # Set up git credential store for HTTPS authentication (avoids embedding
    # credentials in URLs where they could appear in process listings or logs)
    if [[ "$GIT_REPO_URL" == https://* ]]; then
        local cred_file host
        cred_file="$(mktemp)"
        chmod 600 "$cred_file"
        host="$(printf '%s\n' "$GIT_REPO_URL" | sed 's|https://||' | cut -d'/' -f1)"
        printf 'https://%s:%s@%s\n' "$GIT_USERNAME" "$GIT_TOKEN" "$host" > "$cred_file"
        git config --global credential.helper "store --file $cred_file"
        trap "rm -f '$cred_file'" EXIT
    fi
}

configure_git_identity() {
    # Configure git user identity for commits
    git config --global user.name "$GIT_USERNAME"
    if [[ "${TASK_MANAGER:-jira}" == "github" ]]; then
        git config --global user.email "$GITHUB_ASSIGNEE@users.noreply.github.com"
    elif [[ "${TASK_MANAGER:-jira}" == "todo" ]]; then
        git config --global user.email "${TODO_ASSIGNEE:-agent}@localhost"
    else
        git config --global user.email "$JIRA_EMAIL"
    fi
    git config --global pull.rebase true
}

clone_or_pull() {
    if [[ -d "$WORK_DIR/.git" ]]; then
        echo "Pulling latest changes for $REPO_NAME..."
        git -C "$WORK_DIR" remote set-url origin "$GIT_REPO_URL"
        git -C "$WORK_DIR" pull
    else
        echo "Cloning $GIT_REPO_URL..."
        git clone "$GIT_REPO_URL" "$WORK_DIR"
    fi
}

# Derive REPO_NAME and WORK_DIR from GIT_REPO_URL.
# LOOP_WORK_DIR can override the base directory (used in tests).
derive_work_dir() {
    REPO_NAME="$(basename "$GIT_REPO_URL" .git)"
    local base_dir="${LOOP_WORK_DIR:-$(pwd)}"
    WORK_DIR="$base_dir/$REPO_NAME"

    # If already running from inside the target repo, use the git root as WORK_DIR
    if [[ -z "${LOOP_WORK_DIR:-}" ]]; then
        local git_root git_remote
        git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -n "$git_root" ]]; then
            git_remote="$(git -C "$git_root" remote get-url origin 2>/dev/null || true)"
            if [[ "$git_remote" == "$GIT_REPO_URL" ]]; then
                WORK_DIR="$git_root"
            fi
        fi
    fi
}
