#!/usr/bin/env bash
set -euo pipefail

MOCK_MODE="${MOCK_MODE:-success}"
HUB_URL="${HUB_URL:-http://host.docker.internal:3000}"
PIPELINE_ID="${PIPELINE_ID:-}"
TASK_ID="${TASK_ID:-}"

# Brief pause to let the container's network stack settle before making curl calls
sleep 1

STAGES=("cloning" "refining" "planning" "implementing" "deploying" "verifying")

for POSITION in "${!STAGES[@]}"; do
    STAGE="${STAGES[$POSITION]}"

    # Mark in_progress
    curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$STAGE\",\"status\":\"in_progress\"}"

    # Sleep unless instant mode
    [ "$MOCK_MODE" != "instant" ] && sleep 1

    # If hang mode: block on first stage
    if [ "$MOCK_MODE" = "hang" ] && [ "$POSITION" -eq 0 ]; then
        sleep infinity
    fi

    # Check if this stage should fail
    if [ "$MOCK_MODE" = "fail_at_$STAGE" ]; then
        curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
            -H 'Content-Type: application/json' \
            -d "{\"name\":\"$STAGE\",\"status\":\"failed\",\"content\":\"Mock failure at $STAGE\"}"
        curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID" \
            -H 'Content-Type: application/json' \
            -d '{"status":"failed"}'
        exit 0
    fi

    # Mark completed
    curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$STAGE\",\"status\":\"completed\",\"content\":\"Mock output for $STAGE\"}"
done

# Mark pipeline completed
curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID" \
    -H 'Content-Type: application/json' \
    -d '{"status":"completed"}'
