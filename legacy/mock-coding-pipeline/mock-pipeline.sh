#!/usr/bin/env bash
set -euo pipefail

MOCK_MODE="${MOCK_MODE:-success}"
HUB_URL="${HUB_URL:-http://host.docker.internal:3000}"
PIPELINE_ID="${PIPELINE_ID:-}"
TASK_ID="${TASK_ID:-}"
MOCK_SCRIPT_B64="${MOCK_SCRIPT_B64:-}"

# Brief pause to let the container's network stack settle before making curl calls
sleep 1

# If a base64-encoded bash script is provided, decode and source it.
# Stage functions defined in the script (e.g. cloning(), refining(), ...) will
# override the default MOCK_MODE behaviour for that stage.
if [ -n "$MOCK_SCRIPT_B64" ]; then
    SCRIPT_FILE=$(mktemp /tmp/mock-script-XXXXXX)
    echo "$MOCK_SCRIPT_B64" | base64 -d > "$SCRIPT_FILE"
    # shellcheck source=/dev/null
    source "$SCRIPT_FILE"
    rm -f "$SCRIPT_FILE"
fi

STAGES=("cloning" "refining" "planning" "implementing" "deploying" "verifying")

for POSITION in "${!STAGES[@]}"; do
    STAGE="${STAGES[$POSITION]}"

    # Mark in_progress
    curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$STAGE\",\"status\":\"in_progress\"}"

    if declare -f "$STAGE" > /dev/null 2>&1; then
        # A stage function was provided by MOCK_SCRIPT — call it and capture output/exit code
        set +e
        OUTPUT=$("$STAGE" 2>&1)
        STAGE_EXIT=$?
        set -e

        # Escape output for embedding in JSON
        ESCAPED=$(printf '%s' "$OUTPUT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')

        if [ "$STAGE_EXIT" -ne 0 ]; then
            curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
                -H 'Content-Type: application/json' \
                -d "{\"name\":\"$STAGE\",\"status\":\"failed\",\"content\":\"$ESCAPED\"}"
            curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID" \
                -H 'Content-Type: application/json' \
                -d '{"status":"failed"}'
            exit 0
        fi

        curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID/stages/$POSITION" \
            -H 'Content-Type: application/json' \
            -d "{\"name\":\"$STAGE\",\"status\":\"completed\",\"content\":\"$ESCAPED\"}"
    else
        # Fall back to MOCK_MODE behaviour

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
    fi
done

# Mark pipeline completed
curl -s -X PUT "$HUB_URL/api/pipelines/$PIPELINE_ID" \
    -H 'Content-Type: application/json' \
    -d '{"status":"completed"}'
