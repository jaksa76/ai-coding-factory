#!/bin/bash
# Wrapper for the Claude CLI that refreshes the OAuth access token before each
# invocation when CLAUDE_ACCESS_TOKEN mode is active. This ensures the worker
# never fails with an expired token mid-loop. When CLAUDE_ACCESS_TOKEN is not
# in use (e.g. ANTHROPIC_API_KEY mode), the refresh is a no-op.
#
# Any arguments are forwarded verbatim to `claude`.
# --verbose is always passed so that tool calls and agent progress are visible
# in docker logs.

set -euo pipefail

init-claude --refresh

exec claude --verbose "$@"
