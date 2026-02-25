#!/bin/bash
# Initializes GitHub Copilot CLI authentication by injecting GH_TOKEN and
# GH_USERNAME into the config file baked into the image.
#
# Required env vars:
#   GH_TOKEN    — GitHub personal access token
#   GH_USERNAME — GitHub username

set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN is required for GitHub Copilot CLI authentication" >&2
  exit 1
fi
if [ -z "${GH_USERNAME:-}" ]; then
  echo "ERROR: GH_USERNAME is required for GitHub Copilot CLI authentication" >&2
  exit 1
fi

sed -i "s|\${GH_USERNAME}|${GH_USERNAME}|g; s|\${GH_TOKEN}|${GH_TOKEN}|g" \
  /root/.copilot/config.json

echo "Copilot authentication initialized for ${GH_USERNAME}"
