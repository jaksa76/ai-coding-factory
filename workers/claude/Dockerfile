FROM node:24-slim

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

# Install loop and claim tools
# Build context must be the repository root: docker build -f workers/claude/Dockerfile .
COPY claim/claim /usr/local/bin/claim
COPY loop/loop /usr/local/bin/loop
COPY workers/claude/init-claude.sh /usr/local/bin/init-claude
RUN chmod +x /usr/local/bin/claim /usr/local/bin/loop /usr/local/bin/init-claude

# Ensure ~/.claude directory exists so init-claude can write credentials at runtime
RUN mkdir -p /home/worker/.claude && chown worker:worker /home/worker/.claude

# Runtime env vars (must be supplied via docker run -e / --env-file):
#   CLAUDE_ACCESS_TOKEN       — Claude OAuth access token
#   CLAUDE_REFRESH_TOKEN      — Claude OAuth refresh token
#   CLAUDE_TOKEN_EXPIRES_AT   — Token expiry timestamp (epoch ms, numeric)
#   CLAUDE_SUBSCRIPTION_TYPE  — Subscription type (e.g. "pro")
#   JIRA_SITE / JIRA_EMAIL / JIRA_TOKEN / JIRA_ASSIGNEE_ACCOUNT_ID
#   JIRA_PROJECT              — Jira project key to pull issues from (e.g. MYPROJ)
#   GIT_REPO_URL / GIT_USERNAME / GIT_TOKEN

USER worker
ENV HOME=/home/worker
ENV PATH="/home/worker/.local/bin:$PATH"

ENTRYPOINT ["bash", "-c", "init-claude && exec loop --project \"$JIRA_PROJECT\" --agent 'claude --dangerously-skip-permissions -p'"]
