#!/usr/bin/env bash
set -euo pipefail

# setup — guided setup for AI Coding Factory
#
# Creates bin/ symlinks, configures PATH, and collects credentials.
# Re-runnable: asks before overwriting existing configuration.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$REPO_DIR/bin"

# Global state set across steps
CHOSEN_AGENT=""
RC_FILE=""

# ─── helpers ───────────────────────────────────────────────────────────────

info()    { echo "  $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ! $*"; }
header()  { echo ""; echo "$*"; }

ask() {
    local prompt="$1" default="${2:-}"
    local answer
    if [[ -n "$default" ]]; then
        IFS= read -r -p "  $prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        IFS= read -r -p "  $prompt: " answer
        echo "$answer"
    fi
}

ask_secret() {
    local prompt="$1"
    local answer
    IFS= read -r -s -p "  $prompt: " answer
    echo "" >&2
    echo "$answer"
}

ask_yn() {
    local prompt="$1" default="${2:-n}"
    local choices answer
    if [[ "$default" == "y" ]]; then choices="Y/n"; else choices="y/N"; fi
    IFS= read -r -p "  $prompt [$choices]: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

make_symlink() {
    local src="$1" dst="$2" label="$3"
    if [[ -L "$dst" ]] || [[ -e "$dst" ]]; then
        if ask_yn "$label already exists. Overwrite?" "n"; then
            ln -sf "$src" "$dst"
            success "$label updated"
        else
            info "$label kept unchanged"
        fi
    else
        ln -sf "$src" "$dst"
        success "$label created"
    fi
}

# ─── step 1: prerequisites ─────────────────────────────────────────────────

check_prerequisites() {
    header "[1/5] Prerequisites"
    local all_ok=true
    for cmd in docker git; do
        if command -v "$cmd" &>/dev/null; then
            success "$cmd found"
        else
            warn "$cmd not found — please install it before continuing"
            all_ok=false
        fi
    done
    if [[ "$all_ok" == "false" ]]; then
        echo ""
        echo "Error: missing required tools. Please install them and re-run setup." >&2
        exit 1
    fi
}

# ─── step 2: agent selection ───────────────────────────────────────────────

select_agent() {
    header "[2/5] Agent selection"

    local agents=()
    for agent_script in "$REPO_DIR"/workers/*/agent; do
        [[ -f "$agent_script" ]] || continue
        agents+=("$(basename "$(dirname "$agent_script")")")
    done

    if [[ ${#agents[@]} -eq 0 ]]; then
        echo "Error: no agent scripts found under workers/*/agent" >&2
        exit 1
    fi

    info "Available agents: ${agents[*]}"

    if [[ -L "$BIN_DIR/agent" ]]; then
        local target current
        target="$(readlink "$BIN_DIR/agent")"
        current="$(basename "$(dirname "$target")")"
        info "Currently configured: $current"
        if ! ask_yn "Change agent?" "n"; then
            CHOSEN_AGENT="$current"
            return
        fi
    fi

    CHOSEN_AGENT="$(ask "Which agent? (${agents[*]})" "${agents[0]}")"

    local valid=false
    for a in "${agents[@]}"; do
        [[ "$a" == "$CHOSEN_AGENT" ]] && valid=true && break
    done
    if [[ "$valid" == "false" ]]; then
        echo "Error: unknown agent '$CHOSEN_AGENT'. Choose one of: ${agents[*]}" >&2
        exit 1
    fi
}

# ─── step 3: bin/ symlinks ─────────────────────────────────────────────────

setup_bin() {
    header "[3/5] Setting up bin/"
    mkdir -p "$BIN_DIR"

    for tool in claim loop factory worker-builder; do
        local src="$REPO_DIR/$tool/$tool"
        local dst="$BIN_DIR/$tool"
        if [[ ! -f "$src" ]]; then
            warn "script not found: $tool/$tool — skipping"
            continue
        fi
        make_symlink "$src" "$dst" "bin/$tool"
    done

    # agent symlink always reflects the choice made in select_agent (no prompt needed)
    local agent_src="$REPO_DIR/workers/$CHOSEN_AGENT/agent"
    local agent_dst="$BIN_DIR/agent"
    ln -sf "$agent_src" "$agent_dst"
    success "bin/agent → workers/$CHOSEN_AGENT/agent"
}

# ─── step 4: PATH setup ────────────────────────────────────────────────────

setup_path() {
    header "[4/5] PATH setup"

    local export_line="export PATH=\"\$PATH:$BIN_DIR\""
    RC_FILE="$HOME/.bashrc"
    case "${SHELL:-}" in
        */zsh)  RC_FILE="$HOME/.zshrc" ;;
        */fish)
            RC_FILE="$HOME/.config/fish/config.fish"
            export_line="fish_add_path $BIN_DIR"
            ;;
    esac

    info "Shell config line:  $export_line"

    if grep -qF "$BIN_DIR" "$RC_FILE" 2>/dev/null; then
        success "PATH already configured in $(basename "$RC_FILE")"
        return
    fi

    if ask_yn "Add automatically to $RC_FILE?" "y"; then
        echo "" >> "$RC_FILE"
        echo "# AI Coding Factory" >> "$RC_FILE"
        echo "$export_line" >> "$RC_FILE"
        success "Added to $RC_FILE"
    else
        info "Add the line above manually to your shell config."
    fi
}

# ─── step 5: project configuration ────────────────────────────────────────

collect_jira_config() {
    echo ""
    info "--- Jira ---"
    info "Create an API token at: https://id.atlassian.com/manage-profile/security/api-tokens"
    JIRA_SITE="$(ask "Jira hostname (e.g. mycompany.atlassian.net)")"
    JIRA_EMAIL="$(ask "Jira account email")"
    JIRA_TOKEN="$(ask_secret "Jira API token")"
    JIRA_PROJECT="$(ask "Jira project key (e.g. MYPROJ)")"
    info "Find your account ID at: https://$JIRA_SITE/rest/api/3/myself (sign in first)"
    JIRA_ASSIGNEE_ACCOUNT_ID="$(ask "Your Jira account ID")"
}

collect_git_config() {
    echo ""
    info "--- Git ---"
    info "Create a personal access token: https://github.com/settings/tokens (needs 'repo' scope)"
    GIT_REPO_URL="$(ask "Repository URL (e.g. https://github.com/org/repo.git)")"
    GIT_USERNAME="$(ask "Git username")"
    GIT_TOKEN="$(ask_secret "Personal access token")"
}

collect_agent_credentials() {
    case "$CHOSEN_AGENT" in
        claude)
            echo ""
            info "--- Claude ---"
            info "  1) Anthropic API key (pay-per-use)"
            info "  2) Claude subscription (requires 'claude login')"
            local method
            method="$(ask "Authentication method" "1")"
            if [[ "$method" == "2" ]]; then
                info "Run 'claude login' first, then copy values from ~/.claude/.credentials.json"
                CLAUDE_ACCESS_TOKEN="$(ask_secret "CLAUDE_ACCESS_TOKEN")"
                CLAUDE_REFRESH_TOKEN="$(ask_secret "CLAUDE_REFRESH_TOKEN")"
                CLAUDE_TOKEN_EXPIRES_AT="$(ask "CLAUDE_TOKEN_EXPIRES_AT (timestamp)")"
                CLAUDE_SUBSCRIPTION_TYPE="$(ask "CLAUDE_SUBSCRIPTION_TYPE" "pro")"
                ANTHROPIC_API_KEY=""
            else
                info "Create an API key at: https://console.anthropic.com/settings/keys"
                ANTHROPIC_API_KEY="$(ask_secret "ANTHROPIC_API_KEY")"
                CLAUDE_ACCESS_TOKEN=""
                CLAUDE_REFRESH_TOKEN=""
                CLAUDE_TOKEN_EXPIRES_AT=""
                CLAUDE_SUBSCRIPTION_TYPE=""
            fi
            ;;
        copilot)
            echo ""
            info "--- GitHub Copilot ---"
            info "Create a token with 'copilot' scope: https://github.com/settings/tokens"
            GH_TOKEN="$(ask_secret "GH_TOKEN")"
            GH_USERNAME="$(ask "GitHub username")"
            ;;
    esac
}

collect_optional_settings() {
    echo ""
    info "--- Optional settings ---"
    USE_FEATURE_BRANCHES="false"
    PLAN_BY_DEFAULT="false"
    if ask_yn "Create feature branches and PRs for each issue?" "n"; then
        USE_FEATURE_BRANCHES="true"
    fi
    if ask_yn "Require a planning step for all issues by default?" "n"; then
        PLAN_BY_DEFAULT="true"
    fi
}

write_env_file() {
    local env_file="$1"
    {
        echo "# AI Coding Factory — project config"
        echo "# Generated by setup on $(date)"
        echo ""
        echo "# Jira"
        echo "JIRA_SITE=${JIRA_SITE:-}"
        echo "JIRA_EMAIL=${JIRA_EMAIL:-}"
        echo "JIRA_TOKEN=${JIRA_TOKEN:-}"
        echo "JIRA_PROJECT=${JIRA_PROJECT:-}"
        echo "JIRA_ASSIGNEE_ACCOUNT_ID=${JIRA_ASSIGNEE_ACCOUNT_ID:-}"
        echo ""
        echo "# Git"
        echo "GIT_REPO_URL=${GIT_REPO_URL:-}"
        echo "GIT_USERNAME=${GIT_USERNAME:-}"
        echo "GIT_TOKEN=${GIT_TOKEN:-}"
        echo ""
        echo "# Factory"
        echo "FACTORY_WORKER_IMAGE=worker-$CHOSEN_AGENT"
        echo "FACTORY_PLANNER_IMAGE=planner-$CHOSEN_AGENT"
        echo ""
        echo "# Agent credentials"
        case "$CHOSEN_AGENT" in
            claude)
                if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
                    echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
                else
                    echo "CLAUDE_ACCESS_TOKEN=${CLAUDE_ACCESS_TOKEN:-}"
                    echo "CLAUDE_REFRESH_TOKEN=${CLAUDE_REFRESH_TOKEN:-}"
                    echo "CLAUDE_TOKEN_EXPIRES_AT=${CLAUDE_TOKEN_EXPIRES_AT:-}"
                    echo "CLAUDE_SUBSCRIPTION_TYPE=${CLAUDE_SUBSCRIPTION_TYPE:-}"
                fi
                ;;
            copilot)
                echo "GH_TOKEN=${GH_TOKEN:-}"
                echo "GH_USERNAME=${GH_USERNAME:-}"
                ;;
        esac
        echo ""
        echo "# Options"
        echo "USE_FEATURE_BRANCHES=${USE_FEATURE_BRANCHES:-false}"
        echo "PLAN_BY_DEFAULT=${PLAN_BY_DEFAULT:-false}"
    } > "$env_file"
}

setup_project() {
    header "[5/5] Project configuration"

    local project_name env_file
    project_name="$(ask "Project name (creates .env.<name>)")"
    env_file="$REPO_DIR/.env.$project_name"

    if [[ -f "$env_file" ]]; then
        warn "Config for '$project_name' already exists (.env.$project_name)"
        info "To use it:       factory workers --env-file .env.$project_name"
        info "To reconfigure:  delete .env.$project_name and re-run setup"
        return
    fi

    collect_jira_config
    collect_git_config
    collect_agent_credentials
    collect_optional_settings
    write_env_file "$env_file"
    success "Config written to .env.$project_name"
}

# ─── step 6: summary ───────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo "═══════════════════════════════════════"
    echo " Setup complete!"
    echo "═══════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo ""
    if [[ -n "$RC_FILE" ]]; then
        echo "  1. Reload your shell:"
        echo "       source $RC_FILE"
        echo ""
    fi
    echo "  2. Build the worker image:"
    echo "       docker build -f workers/$CHOSEN_AGENT/Dockerfile -t worker-$CHOSEN_AGENT ."
    echo ""
    echo "  3. Start workers:"
    echo "       factory workers --env-file .env.<project>"
    echo ""
}

# ─── main ──────────────────────────────────────────────────────────────────

echo "=== AI Coding Factory Setup ==="

check_prerequisites
select_agent
setup_bin
setup_path
setup_project
print_summary
