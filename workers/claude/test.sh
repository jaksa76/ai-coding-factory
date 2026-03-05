#!/bin/bash

set -e

echo "initializing claude..."

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


echo "calling claude..."
claude -p "tell me a joke" || echo "claude failed with exit $?"
echo "did you like the joke?"

echo "starting planner loop..."
loop --project "$JIRA_PROJECT" --agent "run-claude --dangerously-skip-permissions -p" || echo "loop failed with exit $?"