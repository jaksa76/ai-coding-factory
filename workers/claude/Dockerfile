FROM node:24-slim

# Runtime env vars (must be supplied via docker run -e / --env-file):
#
# Authentication — choose one:
#   ANTHROPIC_API_KEY         — API key (simplest; takes precedence over OAuth)
#   -- OR --
#   CLAUDE_ACCESS_TOKEN       — Claude OAuth access token
#   CLAUDE_REFRESH_TOKEN      — Claude OAuth refresh token
#   CLAUDE_TOKEN_EXPIRES_AT   — Token expiry timestamp (epoch ms, numeric)
#   CLAUDE_SUBSCRIPTION_TYPE  — Subscription type (e.g. "pro")
#
#   PROJECT                   — Project to pull issues from:
#                               Jira:   project key (e.g. MYPROJ)
#                               GitHub: owner/repo (e.g. org/myrepo)
#   TASK_MANAGER              — Backend: jira (default), github, or todo
#   JIRA_SITE / JIRA_EMAIL / JIRA_TOKEN / JIRA_ASSIGNEE_ACCOUNT_ID (jira backend)
#   GH_TOKEN / GITHUB_ASSIGNEE (github backend)
#   GIT_REPO_URL / GIT_USERNAME / GIT_TOKEN

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash curl git jq wget gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Install acli (Atlassian CLI) for Jira operations
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O- https://acli.atlassian.com/gpg/public-key.asc \
        | gpg --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/acli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/acli-archive-keyring.gpg] https://acli.atlassian.com/linux/deb stable main" \
        | tee /etc/apt/sources.list.d/acli.list > /dev/null \
    && apt-get update \
    && apt-get install -y acli \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user — Claude Code refuses --dangerously-skip-permissions as root
RUN useradd -m -s /bin/bash worker

# Install Claude Code CLI as the worker user so it lands in /home/worker/.local/bin
USER worker
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root

# Install loop, task-manager, and agent tools
# Build context must be the repository root: docker build -f workers/claude/Dockerfile .
COPY loop/loop /usr/local/bin/loop
COPY loop/implement /usr/local/bin/implement
COPY loop/plan /usr/local/bin/plan
COPY loop/git-utils.sh /usr/local/bin/git-utils.sh
COPY task-manager/task-manager /usr/local/bin/task-manager
COPY task-manager/backends /usr/local/bin/backends
COPY workers/claude/agent /usr/local/bin/agent
RUN chmod +x /usr/local/bin/loop /usr/local/bin/implement /usr/local/bin/plan \
        /usr/local/bin/task-manager /usr/local/bin/backends/jira \
        /usr/local/bin/backends/github /usr/local/bin/backends/todo \
        /usr/local/bin/agent

# Ensure ~/.claude directory exists so agent init can write credentials at runtime
RUN mkdir -p /home/worker/.claude && chown worker:worker /home/worker/.claude

USER worker
WORKDIR /home/worker
ENV HOME=/home/worker
ENV PATH="/home/worker/.local/bin:$PATH"

ENTRYPOINT ["bash", "-c", "agent init && exec loop --project \"$PROJECT\""]
