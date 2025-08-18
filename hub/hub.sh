#!/bin/bash

# AI Coding Factory Hub - Main Entry Point
# This script starts a web server using mini_httpd to serve the UI and handle API requests

set -e

# Configuration
HUB_PORT=${HUB_PORT:-8080}
HUB_HOST=${HUB_HOST:-0.0.0.0}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$SCRIPT_DIR/ui"
API_DIR="$SCRIPT_DIR/api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Signal handlers for graceful shutdown
cleanup() {
    log "Received shutdown signal, stopping server..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
log "Starting AI Coding Factory Hub..."

# Start mini_httpd
log "Starting web server on http://$HUB_HOST:$HUB_PORT"
log "Document root: $UI_DIR"
log "CGI directory: $API_DIR (via symbolic link)"

# mini_httpd command with proper configuration for Docker
exec mini_httpd \
    -D \
    -p "$HUB_PORT" \
    -d "$UI_DIR" \
    -c "*.cgi" \
    -T UTF-8
