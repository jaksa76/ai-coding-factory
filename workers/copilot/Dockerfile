FROM node:24-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash curl git jq wget gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install @github/copilot CLI and create a wrapper that bypasses auth
RUN npm install -g @github/copilot && \
    printf '#!/bin/sh\nexec node /usr/local/lib/node_modules/@github/copilot/index.js "$@"\n' > /usr/local/bin/copilot && \
    chmod +x /usr/local/bin/copilot

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

# Install loop and claim tools
# Build context must be the repository root: docker build -f workers/copilot/Dockerfile .
COPY claim/claim /usr/local/bin/claim
COPY loop/loop /usr/local/bin/loop
COPY workers/copilot/init-copilot.sh /usr/local/bin/init-copilot
RUN chmod +x /usr/local/bin/claim /usr/local/bin/loop /usr/local/bin/init-copilot

# Bake in the copilot config template (credentials injected at runtime by init-copilot)
RUN mkdir -p /root/.copilot
COPY workers/copilot/copilot-config.json /root/.copilot/config.json

# Runtime env vars (must be supplied via docker run -e / --env-file):
#   GH_TOKEN / GH_USERNAME    — GitHub credentials for Copilot authentication
#   JIRA_SITE / JIRA_EMAIL / JIRA_TOKEN / JIRA_ASSIGNEE_ACCOUNT_ID
#   JIRA_PROJECT              — Jira project key to pull issues from (e.g. MYPROJ)
#   GIT_REPO_URL / GIT_USERNAME / GIT_TOKEN

ENTRYPOINT ["bash", "-c", "init-copilot && exec loop --project \"$JIRA_PROJECT\" --agent copilot"]
