#!/bin/bash
# Wrapper for the Claude CLI that refreshes the OAuth access token before each
# invocation. This ensures the worker never fails with an expired token mid-loop.
#
# Any arguments are forwarded verbatim to `claude`.

set -euo pipefail

init-claude --refresh

exec claude "$@"
