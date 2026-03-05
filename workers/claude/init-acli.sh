#!/bin/bash
# Authenticates acli with Jira using credentials from environment variables.
# Must run before any acli commands are called in a non-interactive context.
#
# Usage: init-acli
#
# Required environment variables:
#   JIRA_SITE   — Jira host (with or without https:// prefix)
#   JIRA_EMAIL  — Jira account email
#   JIRA_TOKEN  — Jira API token

set -euo pipefail

if acli jira auth status 2>/dev/null | grep -q "Authenticated"; then
    echo "acli: already authenticated"
    exit 0
fi

echo "Authenticating acli with Jira..."
echo "$JIRA_TOKEN" | acli jira auth login \
    --site "$JIRA_SITE" \
    --email "$JIRA_EMAIL" \
    --token
echo "acli: authenticated successfully"
