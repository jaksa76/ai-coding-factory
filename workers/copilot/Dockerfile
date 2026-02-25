FROM node:20-slim

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

# Install @github/copilot CLI extension (gh copilot) by downloading the binary
# directly from GitHub releases — no auth token required for public releases.
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
        amd64)  GH_COPILOT_ARCH="linux-amd64"  ;; \
        arm64)  GH_COPILOT_ARCH="linux-arm64"  ;; \
        386)    GH_COPILOT_ARCH="linux-386"     ;; \
        *)      echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac \
    && RELEASE_URL="https://api.github.com/repos/github/gh-copilot/releases/latest" \
    && DOWNLOAD_URL="$(curl -fsSL "$RELEASE_URL" \
        | jq -r --arg arch "$GH_COPILOT_ARCH" \
            '.assets[] | select(.name == $arch) | .browser_download_url')" \
    && mkdir -p /root/.local/share/gh/extensions/gh-copilot \
    && curl -fsSL "$DOWNLOAD_URL" \
        -o /root/.local/share/gh/extensions/gh-copilot/gh-copilot \
    && chmod +x /root/.local/share/gh/extensions/gh-copilot/gh-copilot

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
RUN chmod +x /usr/local/bin/claim /usr/local/bin/loop

# Runtime env vars (must be supplied via docker run -e / --env-file):
#   GH_TOKEN                  — GitHub token for Copilot authentication
#   JIRA_SITE / JIRA_EMAIL / JIRA_TOKEN / JIRA_ASSIGNEE_ACCOUNT_ID
#   GIT_REPO_URL / GIT_USERNAME / GIT_TOKEN

# Use gpt-4.1 as the Copilot model
ENV GH_COPILOT_MODEL="gpt-4.1"

ENTRYPOINT ["loop", "--agent", "gh copilot suggest --model gpt-4.1 -t shell"]
