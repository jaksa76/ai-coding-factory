#!/bin/bash
# Initializes Claude Code authentication by writing OAuth credentials
# into ~/.claude/.credentials.json from environment variables.
#
# Usage:
#   init-claude           — Write credentials from environment variables (initial setup)
#
# Authentication modes (mutually exclusive, checked in order):
#   1. ANTHROPIC_API_KEY — API key authentication; no credentials file needed.
#      Set this env var and init-claude becomes a no-op (both modes).
#   2. OAuth tokens — set all four vars below:
#      CLAUDE_ACCESS_TOKEN       — Claude OAuth access token
#      CLAUDE_REFRESH_TOKEN      — Claude OAuth refresh token
#      CLAUDE_TOKEN_EXPIRES_AT   — Token expiry timestamp (epoch ms, numeric)
#      CLAUDE_SUBSCRIPTION_TYPE  — Subscription type (e.g. "pro")

set -euo pipefail

# ── API key mode (both initial setup and --refresh are no-ops) ────────────────

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Using ANTHROPIC_API_KEY for authentication — skipping OAuth credential setup"
  exit 0
fi

# ── initial setup mode ────────────────────────────────────────────────────────

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
    }}' > ~/.claude/.credentials.json

echo "Claude Code authentication initialized"
