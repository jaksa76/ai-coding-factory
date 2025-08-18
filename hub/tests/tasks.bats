setup() {
    # Start hub.sh in background and save PID
    ./hub.sh &
    HUB_PID=$!
    
    # Wait a moment for the server to start
    sleep 2
    
    # Store PID in a file for teardown
    echo $HUB_PID > /tmp/hub_test.pid
}

teardown() {
    # Kill the hub process if it's still running
    if [ -f /tmp/hub_test.pid ]; then
        HUB_PID=$(cat /tmp/hub_test.pid)
        if kill -0 $HUB_PID 2>/dev/null; then
            kill $HUB_PID
            # Wait for process to terminate
            wait $HUB_PID 2>/dev/null || true
        fi
        rm -f /tmp/hub_test.pid
    fi
}

@test "hub is running" {
    run curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]
}

@test "create a task" {
    # Create a task
    timestamp=$(date +%s%N | cut -b1-13)
    task_data=$(printf '{"description": "Test task description %s"}' "$timestamp")
    run curl -s -X POST -H "Content-Type: application/json" -d "$task_data" http://localhost:8080/api/tasks.cgi

    run curl -s http://localhost:8080/api/tasks.cgi
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r 'length')" -gt 0 ]

    # Verify the created task is present
    created_task=$(echo "$output" | jq -r ".[] | select(.description == \"Test task description $time\")")
    echo "$created_task"

    # now retrieve only the created task
    task_id=$(echo "$created_task" | jq -r '.id')
    run curl -s http://localhost:8080/api/tasks.cgi/$task_id
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}