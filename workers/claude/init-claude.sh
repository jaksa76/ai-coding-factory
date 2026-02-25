#!/bin/bash
# Initializes Claude Code authentication by writing OAuth credentials
# into ~/.claude/.credentials.json from environment variables.
#
# Required env vars:
#   CLAUDE_ACCESS_TOKEN       — Claude OAuth access token
#   CLAUDE_REFRESH_TOKEN      — Claude OAuth refresh token
#   CLAUDE_TOKEN_EXPIRES_AT   — Token expiry timestamp (epoch ms, numeric)
#   CLAUDE_SUBSCRIPTION_TYPE  — Subscription type (e.g. "pro")

set -euo pipefail

if [ -z "${CLAUDE_ACCESS_TOKEN:-}" ]; then
  echo "ERROR: CLAUDE_ACCESS_TOKEN is required for Claude Code authentication" >&2
  exit 1
fi
if [ -z "${CLAUDE_REFRESH_TOKEN:-}" ]; then
  echo "ERROR: CLAUDE_REFRESH_TOKEN is required for Claude Code authentication" >&2
  exit 1
fi
if [ -z "${CLAUDE_TOKEN_EXPIRES_AT:-}" ]; then
  echo "ERROR: CLAUDE_TOKEN_EXPIRES_AT is required for Claude Code authentication" >&2
  exit 1
fi
if [ -z "${CLAUDE_SUBSCRIPTION_TYPE:-}" ]; then
  echo "ERROR: CLAUDE_SUBSCRIPTION_TYPE is required for Claude Code authentication" >&2
  exit 1
fi

jq -n \
  --arg accessToken "$CLAUDE_ACCESS_TOKEN" \
  --arg refreshToken "$CLAUDE_REFRESH_TOKEN" \
  --argjson expiresAt "$CLAUDE_TOKEN_EXPIRES_AT" \
  --arg subscriptionType "$CLAUDE_SUBSCRIPTION_TYPE" \
  '{claudeAiOauth: {
      accessToken: $accessToken,
      refreshToken: $refreshToken,
      expiresAt: $expiresAt,
      scopes: ["user:inference","user:mcp_servers","user:profile","user:sessions:claude_code"],
      subscriptionType: $subscriptionType,
      rateLimitTier: "default_claude_ai"
    }}' > "${HOME:-/home/worker}/.claude/.credentials.json"

echo "Claude Code authentication initialized"
