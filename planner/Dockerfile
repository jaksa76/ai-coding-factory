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

# Install planner-loop, claim, and Claude helper tools
# Build context must be the repository root: docker build -f planner/Dockerfile .
COPY claim/claim /usr/local/bin/claim
COPY planner/planner-loop /usr/local/bin/planner-loop
COPY workers/claude/init-claude.sh /usr/local/bin/init-claude
COPY workers/claude/run-claude.sh /usr/local/bin/run-claude
RUN chmod +x /usr/local/bin/claim /usr/local/bin/planner-loop /usr/local/bin/init-claude /usr/local/bin/run-claude

# Ensure ~/.claude directory exists so init-claude can write credentials at runtime
RUN mkdir -p /home/worker/.claude && chown worker:worker /home/worker/.claude

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
#   JIRA_SITE / JIRA_EMAIL / JIRA_TOKEN / JIRA_ASSIGNEE_ACCOUNT_ID
#   JIRA_PROJECT              — Jira project key to pull issues from (e.g. MYPROJ)
#   GIT_REPO_URL / GIT_USERNAME / GIT_TOKEN
#   PLAN_BY_DEFAULT           — Optional: "true" to require planning for all issues

USER worker
WORKDIR /home/worker
ENV HOME=/home/worker
ENV PATH="/home/worker/.local/bin:$PATH"

ENTRYPOINT ["bash", "-c", "init-claude && exec planner-loop --project \"$JIRA_PROJECT\" --agent 'run-claude --dangerously-skip-permissions -p'"]
