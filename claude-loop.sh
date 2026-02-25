#!/usr/bin/env bash

set -euo pipefail

PROMPT="${1:-"Implement the next change from TODO.md. Make sure to run all necessary tests. Once the change is implemented, update the TODO.md file and commit the change it with a brief description of the change. After committing, push the changes to the remote repository."}"
TOTAL=10

for i in $(seq 1 "$TOTAL"); do
  echo $(date) "=== Invocation $i / $TOTAL ==="  
  INVOCATION_NUMBER=$i claude --dangerously-skip-permissions -p "$PROMPT"
  echo $(date) "Finished invocation $i / $TOTAL"
  sleep $((10*60))
done
