#!/bin/bash

# Simple API endpoint for AI Coding Factory Hub
# This is a basic example of a CGI script

# Set content type for JSON response
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# Parse query string if present
if [ "$REQUEST_METHOD" = "GET" ]; then
    # Basic status endpoint
    cat << 'EOF'
{
  "status": "ok",
  "service": "AI Coding Factory Hub",
  "version": "1.0.0",
  "timestamp": "$(date -Iseconds)",
  "endpoints": [
    "/api/status.cgi - Service status",
    "/api/health.cgi - Health check"
  ]
}
EOF
else
    # Method not allowed
    echo "Status: 405 Method Not Allowed"
    echo ""
    cat << 'EOF'
{
  "error": "Method not allowed",
  "message": "This endpoint only supports GET requests"
}
EOF
fi
