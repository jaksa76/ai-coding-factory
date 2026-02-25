#!/usr/bin/env bash
# Clean local ai-coding-factory containers and docker volumes
# Lists containers (prefix ai-coding-factory-container-*) and all docker volumes,
# prompts the user to confirm, then stops/removes containers and deletes volumes.

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SH="$HERE/agents-docker.sh"

if [ ! -x "$AGENTS_SH" ]; then
  echo "Error: agents script not found or not executable at $AGENTS_SH"
  exit 1
fi

echo "Scanning Docker for AI Coding Factory containers and volumes..."

# Use agents-docker.sh to get containers and volumes
CONTAINERS=()
VOLUMES=()

# Get short container names from agents script (it strips the project prefix)
if out="$($AGENTS_SH list-containers 2>/dev/null)"; then
  while IFS= read -r line; do
    line="${line##*( )}"
    line="${line%%*( )}"
    [ -z "$line" ] && continue
    # accept only valid docker container names (no whitespace)
    if [[ "$line" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
      CONTAINERS+=("ai-coding-factory-container-$line")
    else
      # skip header or human-readable lines
      continue
    fi
  done <<< "$out"
else
  echo "Warning: failed to list containers via agents script; no containers will be removed."
fi

# Get volumes via agents script and parse second column (docker volume ls output)
if out="$($AGENTS_SH list-volumes 2>/dev/null)"; then
  # Parse lines, skip header if present
  while IFS= read -r line; do
    # trim
    line="${line##*( )}"
    line="${line%%*( )}"
    [ -z "$line" ] && continue
    # accept only valid docker volume names (no whitespace)
    if [[ "$line" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
      VOLUMES+=("$line")
    else
      # skip headers like 'DRIVER ...' or human text
      continue
    fi
  done <<< "$out"
else
  echo "Warning: failed to list volumes via agents script; no volumes will be removed."
fi

echo
echo "Found ${#CONTAINERS[@]} container(s):"
if [ ${#CONTAINERS[@]} -eq 0 ]; then
  echo "  (none)"
else
  for c in "${CONTAINERS[@]}"; do
    echo "  - $c"
  done
fi

echo
echo "Found ${#VOLUMES[@]} docker volume(s):"
if [ ${#VOLUMES[@]} -eq 0 ]; then
  echo "  (none)"
else
  for v in "${VOLUMES[@]}"; do
    echo "  - $v"
  done
fi

echo
echo "This will STOP and REMOVE the listed containers and DELETE the listed volumes."
echo "This operation is destructive and cannot be undone."
read -rp $'Type YES to confirm: ' CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Aborted. No changes made."
  exit 0
fi

echo
echo "Proceeding..."

# Stop and remove containers
if [ ${#CONTAINERS[@]} -gt 0 ]; then
  for full in "${CONTAINERS[@]}"; do
    # agents-docker.sh expects the user-specified name without prefix
    short="${full#ai-coding-factory-container-}"
    echo "Stopping container $full (via agents-docker.sh stop-container --container-name $short)"
    if ! "$AGENTS_SH" stop-container --container-name "$short" >/dev/null 2>&1; then
      echo "  Warning: failed to stop $full (it may already be stopped)"
    fi

    echo "Removing container $full"
    if docker rm -v "$full" >/dev/null 2>&1; then
      echo "  Removed $full"
    else
      echo "  Warning: failed to remove $full"
    fi
  done
else
  echo "No containers to remove."
fi

# Delete volumes
if [ ${#VOLUMES[@]} -gt 0 ]; then
  for vol in "${VOLUMES[@]}"; do
    echo "Deleting volume $vol (via agents-docker.sh delete-volume --volume-name $vol)"
    if "$AGENTS_SH" delete-volume --volume-name "$vol" >/dev/null 2>&1; then
      echo "  Deleted $vol"
    else
      echo "  Warning: failed to delete $vol"
    fi
  done
else
  echo "No volumes to delete."
fi

echo
echo "Cleanup complete."
