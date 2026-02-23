FROM node:24-alpine

# Install bash, git, and expect
RUN apk add --no-cache bash git expect

# Install GitHub Copilot CLI globally
RUN npm install -g @github/copilot && \
    printf '#!/bin/sh\nexec node /usr/local/lib/node_modules/@github/copilot/index.js "$@"\n' > /usr/local/bin/copilot && \
    chmod +x /usr/local/bin/copilot

# Set default environment variables (can be overridden at runtime)
ENV TASK_ID=""
ENV TASK_DESCRIPTION=""
ENV GIT_REPO_URL=""
ENV GIT_USERNAME=""
ENV GIT_TOKEN=""
ENV GH_TOKEN=""
ENV GH_USERNAME=""

# Pre-configure model selection (gpt-4o as default)
RUN mkdir -p /root/.copilot
COPY copilot-config.json /root/.copilot/config.json

# Set working directory
WORKDIR /app

# Copy the pipeline script
COPY pipeline.sh /app/

# Make the script executable
RUN chmod +x /app/pipeline.sh

# Run the pipeline script
CMD ["/app/pipeline.sh"]
