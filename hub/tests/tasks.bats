curl_t() {
    # Curl with sensible timeouts
    command curl -s --connect-timeout 2 --max-time 5 "$@"
}

wait_for_server() {
    # Poll until server responds with 200 or timeout
    local retries=30
    local url=${1:-http://localhost:8080}
    for i in $(seq 1 $retries); do
        code=$(curl_t -o /dev/null -w "%{http_code}" "$url" || true)
        if [ "$code" -eq 200 ]; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

setup_file() {
    PID_FILE="${BATS_FILE_TMPDIR:-/tmp}/hub_test.pid"
    # Kill any existing process on 8080 to avoid bind errors
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti:8080 | xargs -r kill -9 || true
    else
        fuser -k 8080/tcp 2>/dev/null || true
    fi

    # Start hub.sh in background and save PID
    ./hub.sh &
    HUB_PID=$!
    echo $HUB_PID > "$PID_FILE"

    # Wait for server to be ready
    wait_for_server || { echo "Server failed to start" >&2; exit 1; }
}

teardown_file() {
    PID_FILE="${BATS_FILE_TMPDIR:-/tmp}/hub_test.pid"
    # Kill the hub process if it's still running
    if [ -f "$PID_FILE" ]; then
        HUB_PID=$(cat "$PID_FILE")
        if kill -0 $HUB_PID 2>/dev/null; then
            kill $HUB_PID || true
            # Wait for process to terminate
            wait $HUB_PID 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

@test "hub is running" {
    run curl_t -o /dev/null -w "%{http_code}" http://localhost:8080
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]
}

@test "create a task" {
    # Create a task
    timestamp=$(date +%s%N | cut -b1-13)
    task_desc="Test task description ${timestamp}"
    task_data=$(printf '{"description": "%s"}' "$task_desc")
    run curl_t -X POST -H "Content-Type: application/json" -d "$task_data" http://localhost:8080/api/tasks.cgi

    run curl_t http://localhost:8080/api/tasks.cgi
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r 'length')" -gt 0 ]

    # Verify the created task is present
    created_task=$(echo "$output" | jq -r ".[] | select(.description == \"${task_desc}\")")
    echo "$created_task"

    # now retrieve only the created task
    task_id=$(echo "$created_task" | jq -r '.id')
    run curl_t http://localhost:8080/api/tasks.cgi/$task_id
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "CRUD: create, get, update, delete a task" {
    # Create
    desc="CRUD test $(date +%s)"
    run curl_t -X POST -H "Content-Type: application/json" -d "{\"description\": \"$desc\"}" http://localhost:8080/api/tasks.cgi
    [ "$status" -eq 0 ]
    id=$(echo "$output" | jq -r '.id')
    [ -n "$id" ]
    [ "$(echo "$output" | jq -r '.status')" = "pending" ]

    # Get
    run curl_t -o /dev/null -w "%{http_code}" http://localhost:8080/api/tasks.cgi/$id
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]

    # Update status
    run curl_t -X PUT -H "Content-Type: application/json" -d '{"status": "done"}' http://localhost:8080/api/tasks.cgi/$id
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.status')" = "done" ]

    # Delete
    run curl_t -X DELETE http://localhost:8080/api/tasks.cgi/$id
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.message')" = "Task deleted successfully" ]

    # Ensure 404 after delete
    run curl_t -o /dev/null -w "%{http_code}" http://localhost:8080/api/tasks.cgi/$id
    [ "$status" -eq 0 ]
    [ "$output" -eq 404 ]
}

@test "invalid JSON returns 400" {
    run curl_t -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{invalid' http://localhost:8080/api/tasks.cgi
    [ "$status" -eq 0 ]
    [ "$output" -eq 400 ]
}

@test "PUT without ID returns 400" {
    run curl_t -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d '{"status":"done"}' http://localhost:8080/api/tasks.cgi
    [ "$status" -eq 0 ]
    [ "$output" -eq 400 ]
}

@test "POST with ID not allowed returns 405" {
    run curl_t -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"description":"x"}' http://localhost:8080/api/tasks.cgi/someid
    [ "$status" -eq 0 ]
    [ "$output" -eq 405 ]
}

@test "update non-existing returns 404" {
    fake="task_000000_nonexistent"
    run curl_t -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d '{"status":"done"}' http://localhost:8080/api/tasks.cgi/$fake
    [ "$status" -eq 0 ]
    [ "$output" -eq 404 ]
}

@test "delete non-existing returns 404" {
    fake="task_000000_nonexistent"
    run curl_t -o /dev/null -w "%{http_code}" -X DELETE http://localhost:8080/api/tasks.cgi/$fake
    [ "$status" -eq 0 ]
    [ "$output" -eq 404 ]
}