#!/bin/bash

# AI Coding Factory Hub - Main Entry Point
# This script starts the Node.js Express server to serve the UI and handle API requests

set -e

# Configuration
HUB_PORT=${HUB_PORT:-8080}
HUB_HOST=${HUB_HOST:-0.0.0.0}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$SCRIPT_DIR/ui"
API_DIR="$SCRIPT_DIR/api"
APP_DIR="$SCRIPT_DIR"

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
log "Document root (served by Express): $UI_DIR"

# If running inside container or without node_modules, install dependencies
if [ ! -d "$APP_DIR/node_modules" ]; then
    log "Installing dependencies (npm ci)"
    if command -v npm >/dev/null 2>&1; then
        (cd "$APP_DIR" && npm ci --omit=dev || npm install --omit=dev)
    else
        error "npm not found, cannot start server"; exit 1
    fi
fi

# Start Node server
exec node "$APP_DIR/src/server.mjs"
