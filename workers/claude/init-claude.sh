#!/bin/bash
# Initializes Claude Code authentication by writing OAuth credentials
# into ~/.claude/.credentials.json from environment variables.
#
# Usage:
#   init-claude           — Write credentials from environment variables (initial setup)
#   init-claude --refresh — Refresh the OAuth access token if expired or near expiry
#
# Authentication modes (mutually exclusive, checked in order):
#   1. ANTHROPIC_API_KEY — API key authentication; no credentials file needed.
#      Set this env var and init-claude becomes a no-op (both modes).
#   2. OAuth tokens — set all four vars below:
#      CLAUDE_ACCESS_TOKEN       — Claude OAuth access token
#      CLAUDE_REFRESH_TOKEN      — Claude OAuth refresh token
#      CLAUDE_TOKEN_EXPIRES_AT   — Token expiry timestamp (epoch ms, numeric)
#      CLAUDE_SUBSCRIPTION_TYPE  — Subscription type (e.g. "pro")
#
# --refresh reads the current credentials file and uses the stored refresh token
# to obtain a fresh access token. It is a no-op if the token is still valid
# (more than 5 minutes before expiry). On failure it warns but exits 0 so that
# the caller can still attempt to run claude and surface the real auth error.

set -euo pipefail

OAUTH_TOKEN_ENDPOINT="https://console.anthropic.com/api/oauth/token"
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
# Refresh if within 5 minutes (300 seconds = 300000 ms) of expiry
REFRESH_BUFFER_MS=300000

CREDS_FILE="${HOME:-/home/worker}/.claude/.credentials.json"

# ── API key mode (both initial setup and --refresh are no-ops) ────────────────

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Using ANTHROPIC_API_KEY for authentication — skipping OAuth credential setup"
  exit 0
fi

# ── --refresh mode ────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--refresh" ]]; then
  if [[ ! -f "$CREDS_FILE" ]]; then
    echo "ERROR: credentials file not found at $CREDS_FILE — run init-claude first" >&2
    exit 1
  fi

  EXPIRES_AT="$(jq -r '.claudeAiOauth.expiresAt' "$CREDS_FILE")"
  REFRESH_TOKEN="$(jq -r '.claudeAiOauth.refreshToken' "$CREDS_FILE")"

  # Epoch milliseconds: seconds * 1000 (GNU date %s%3N preferred; fall back to %s000)
  NOW_MS="$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")"

  if [[ "$((EXPIRES_AT - REFRESH_BUFFER_MS))" -gt "$NOW_MS" ]]; then
    echo "Claude OAuth token is still valid"
    exit 0
  fi

  echo "Claude OAuth token is expired or near expiry — refreshing..."

  set +e
  RESPONSE="$(curl -sS \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"${REFRESH_TOKEN}\",\"client_id\":\"${OAUTH_CLIENT_ID}\"}" \
    "${OAUTH_TOKEN_ENDPOINT}" 2>&1)"
  CURL_EXIT=$?
  set -e

  if [[ "$CURL_EXIT" -ne 0 ]]; then
    echo "Warning: token refresh request failed (curl exit $CURL_EXIT): $RESPONSE" >&2
    exit 0
  fi

  if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    ERROR_DESC="$(echo "$RESPONSE" | jq -r '.error_description // .error')"
    echo "Warning: token refresh failed: $ERROR_DESC" >&2
    exit 0
  fi

  NEW_ACCESS_TOKEN="$(echo "$RESPONSE" | jq -r '.access_token // empty')"
  if [[ -z "$NEW_ACCESS_TOKEN" ]]; then
    echo "Warning: token refresh returned no access_token" >&2
    exit 0
  fi

  # expires_in is in seconds; convert to epoch ms
  EXPIRES_IN="$(echo "$RESPONSE" | jq -r '.expires_in // 28800')"
  NEW_EXPIRES_AT="$((NOW_MS + EXPIRES_IN * 1000))"

  # Update credentials file in-place
  UPDATED="$(jq \
    --arg accessToken "$NEW_ACCESS_TOKEN" \
    --argjson expiresAt "$NEW_EXPIRES_AT" \
    '.claudeAiOauth.accessToken = $accessToken | .claudeAiOauth.expiresAt = $expiresAt' \
    "$CREDS_FILE")"

  # Update refresh token if the server returned a new one
  NEW_REFRESH_TOKEN="$(echo "$RESPONSE" | jq -r '.refresh_token // empty')"
  if [[ -n "$NEW_REFRESH_TOKEN" ]]; then
    UPDATED="$(echo "$UPDATED" | jq \
      --arg refreshToken "$NEW_REFRESH_TOKEN" \
      '.claudeAiOauth.refreshToken = $refreshToken')"
  fi

  echo "$UPDATED" > "$CREDS_FILE"
  echo "Claude OAuth token refreshed successfully"
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
    }}' > "$CREDS_FILE"

echo "Claude Code authentication initialized"
