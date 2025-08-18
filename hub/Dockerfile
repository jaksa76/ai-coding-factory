# Dockerfile for AI Coding Factory Hub
FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    mini-httpd \
    python3 \
    python3-pip \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create application directories
RUN mkdir -p /app/hub/ui/api \
    && mkdir -p /data/tasks \
    && mkdir -p /var/log/hub

# Set environment variables
ENV DATA_DIR=/data
ENV PORT=8080

# Copy application files
COPY . /app/hub/

# Make CGI scripts executable
RUN chmod +x /app/hub/ui/api/*.cgi

# Create mini_httpd configuration
RUN echo "port=$PORT" > /app/mini_httpd.conf && \
    echo "dir=/app/hub/ui" >> /app/mini_httpd.conf && \
    echo "cgipat=**.cgi" >> /app/mini_httpd.conf && \
    echo "logfile=/var/log/hub/access.log" >> /app/mini_httpd.conf && \
    echo "pidfile=/var/run/mini_httpd.pid" >> /app/mini_httpd.conf

# Create startup script
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'set -e' >> /app/start.sh && \
    echo '' >> /app/start.sh && \
    echo '# Ensure data directory exists' >> /app/start.sh && \
    echo 'mkdir -p "$DATA_DIR/tasks"' >> /app/start.sh && \
    echo '' >> /app/start.sh && \
    echo '# Start mini_httpd' >> /app/start.sh && \
    echo 'echo "Starting AI Coding Factory Hub on port $PORT..."' >> /app/start.sh && \
    echo 'echo "Data directory: $DATA_DIR"' >> /app/start.sh && \
    echo 'echo "Web root: /app/hub/ui"' >> /app/start.sh && \
    echo '' >> /app/start.sh && \
    echo 'exec mini_httpd -D -C /app/mini_httpd.conf' >> /app/start.sh

RUN chmod +x /app/start.sh

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/api/status.cgi || exit 1

# Set working directory
WORKDIR /app

# Start the application
CMD ["/app/start.sh"]
