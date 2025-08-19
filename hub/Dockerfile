# AI Coding Factory Hub Docker Image
FROM node:20-bullseye-slim

# Set environment variables with defaults
ENV HUB_PORT=8080
ENV HUB_HOST=0.0.0.0
ENV DATA_DIR=/data

# Install additional OS packages if needed
RUN apt-get update && apt-get install -y \
    bash curl procps \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /app

# Create data directory for persistent storage
RUN mkdir -p /data

# Copy hub files
COPY . /app/

# Install dependencies
RUN npm ci --omit=dev || npm install --omit=dev

# Make scripts executable
RUN chmod +x /app/agents.sh || true

# Create a non-root user for security
RUN useradd -r -s /bin/bash -d /app hub

# Change ownership of app directory to hub user
RUN chown -R hub:hub /app /data

# Switch to non-root user
# Keep running as non-root user
USER hub

# Expose the default port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${HUB_PORT}/ || exit 1

# Set the default command: run server directly
CMD ["node", "/app/src/server.mjs"]