#!/bin/bash

echo "Starting file watcher for coding-pipeline directory..."
echo "Will rebuild Docker image 'coding-pipeline:latest' when files change."
echo "Press Ctrl+C to stop watching."
echo ""

# Initial build
echo "[$(date)] Building initial Docker image..."
docker build -t coding-pipeline:latest . && echo "[$(date)] ✅ Initial build completed successfully!" || echo "[$(date)] ❌ Initial build failed!"
echo ""

# Watch for changes and rebuild
inotifywait -m -r -e modify,create,delete,move --format '[%T] File %w%f was %e' --timefmt '%Y-%m-%d %H:%M:%S' . | while read change; do
    echo "$change"
    
    # Ignore temporary files and build artifacts
    if [[ "$change" == *"~"* ]] || [[ "$change" == *".swp"* ]] || [[ "$change" == *".tmp"* ]]; then
        continue
    fi
    
    echo "[$(date)] Rebuilding Docker image due to file changes..."
    
    # Build with a short delay to catch multiple rapid changes
    sleep 1
    
    if docker build -t coding-pipeline:latest . >/dev/null 2>&1; then
        echo "[$(date)] ✅ Docker image rebuilt successfully!"
    else
        echo "[$(date)] ❌ Docker build failed!"
        # Show the error
        docker build -t coding-pipeline:latest .
    fi
    echo ""
done
