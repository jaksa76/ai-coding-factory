#!/bin/bash

# Tasks API endpoint for AI Coding Factory Hub
# Supports CRUD operations on tasks
# Tasks are stored as JSON files in $DATA_DIR/tasks/

# Set content type and CORS headers (do not end headers yet)
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"

# Handle preflight OPTIONS request
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    # End headers and return (preflight OK)
    echo ""
    exit 0
fi

# Set default DATA_DIR if not set
DATA_DIR=${DATA_DIR:-"/tmp/ai-coding-factory"}
TASKS_DIR="$DATA_DIR/tasks"

# Ensure tasks directory exists
mkdir -p "$TASKS_DIR"

# Function to generate unique task ID
generate_id() {
    echo "task_$(date +%s)_$$"
}

# Function to validate JSON
validate_json() {
    echo "$1" | jq empty > /dev/null 2>&1
}

# Function to get task by ID
get_task() {
    local task_id="$1"
    local task_file="$TASKS_DIR/$task_id.json"
    
    if [ -f "$task_file" ]; then
        cat "$task_file"
        return 0
    else
        return 1
    fi
}

# Function to list all tasks
list_tasks() {
    echo "["
    local first=true
    for task_file in "$TASKS_DIR"/*.json; do
        if [ -f "$task_file" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            cat "$task_file"
        fi
    done
    echo "]"
}

# Function to create task
create_task() {
    local task_data="$1"
    local task_id=$(generate_id)
    local task_file="$TASKS_DIR/$task_id.json"
    
    # Extract description from input data
    local description=$(echo "$task_data" | jq -r '.description // ""')
    
    # Create task JSON
    local task_json=$(cat << EOF
{
    "id": "$task_id",
    "description": "$description",
    "status": "pending",
    "created_at": "$(date -Iseconds)",
    "updated_at": "$(date -Iseconds)"
}
EOF
)
    
    echo "$task_json" > "$task_file"
    echo "$task_json"
}

# Function to update task
update_task() {
    local task_id="$1"
    local task_data="$2"
    local task_file="$TASKS_DIR/$task_id.json"
    
    if [ ! -f "$task_file" ]; then
        return 1
    fi
    
    # Get current task data
    local current_task=$(cat "$task_file")
    
    # Extract fields from input data
    local new_description=$(echo "$task_data" | jq -r '.description // ""')
    local new_status=$(echo "$task_data" | jq -r '.status // ""')
    
    # Get current values
    local current_description=$(echo "$current_task" | jq -r '.description // ""')
    local current_status=$(echo "$current_task" | jq -r '.status // ""')
    local created_at=$(echo "$current_task" | jq -r '.created_at // ""')
    
    # Use new values if provided, otherwise keep current
    local final_description="${new_description:-$current_description}"
    local final_status="${new_status:-$current_status}"
    
    # Create updated task JSON
    local updated_task_json=$(cat << EOF
{
    "id": "$task_id",
    "description": "$final_description",
    "status": "$final_status",
    "created_at": "$created_at",
    "updated_at": "$(date -Iseconds)"
}
EOF
)
    
    echo "$updated_task_json" > "$task_file"
    echo "$updated_task_json"
}

# Function to delete task
delete_task() {
    local task_id="$1"
    local task_file="$TASKS_DIR/$task_id.json"
    
    if [ -f "$task_file" ]; then
        rm "$task_file"
        return 0
    else
        return 1
    fi
}

# Parse path info to extract task ID
TASK_ID=""
if [ -n "$PATH_INFO" ]; then
    TASK_ID=$(echo "$PATH_INFO" | sed 's|^/||')
fi

# Prepare response placeholders
STATUS_HEADER=""
RESPONSE_BODY=""

# Handle different HTTP methods and build response
case "$REQUEST_METHOD" in
    "GET")
        if [ -z "$TASK_ID" ]; then
            # List all tasks
            RESPONSE_BODY="$(list_tasks)"
        else
            # Get specific task
            if [ -f "$TASKS_DIR/$TASK_ID.json" ]; then
                RESPONSE_BODY="$(get_task "$TASK_ID")"
            else
                STATUS_HEADER="Status: 404 Not Found"
                RESPONSE_BODY='{"error": "Task not found", "message": "Task with specified ID does not exist"}'
            fi
        fi
        ;;
    
    "POST")
        # Create new task
        if [ -z "$TASK_ID" ]; then
            # Read POST data
            POST_DATA=$(cat)
            
            # Validate JSON
            if validate_json "$POST_DATA"; then
                RESPONSE_BODY="$(create_task "$POST_DATA")"
            else
                STATUS_HEADER="Status: 400 Bad Request"
                RESPONSE_BODY='{"error": "Invalid JSON", "message": "Request body must be valid JSON"}'
            fi
        else
            STATUS_HEADER="Status: 405 Method Not Allowed"
            RESPONSE_BODY='{"error": "Method not allowed", "message": "POST with task ID is not allowed. Use PUT to update."}'
        fi
        ;;
    
    "PUT")
        # Update existing task
        if [ -n "$TASK_ID" ]; then
            # Read PUT data
            PUT_DATA=$(cat)
            
            # Validate JSON
            if validate_json "$PUT_DATA"; then
                if [ -f "$TASKS_DIR/$TASK_ID.json" ]; then
                    RESPONSE_BODY="$(update_task "$TASK_ID" "$PUT_DATA")"
                else
                    STATUS_HEADER="Status: 404 Not Found"
                    RESPONSE_BODY='{"error": "Task not found", "message": "Task with specified ID does not exist"}'
                fi
            else
                STATUS_HEADER="Status: 400 Bad Request"
                RESPONSE_BODY='{"error": "Invalid JSON", "message": "Request body must be valid JSON"}'
            fi
        else
            STATUS_HEADER="Status: 400 Bad Request"
            RESPONSE_BODY='{"error": "Missing task ID", "message": "Task ID is required for PUT requests"}'
        fi
        ;;
    
    "DELETE")
        # Delete task
        if [ -n "$TASK_ID" ]; then
            if delete_task "$TASK_ID"; then
                RESPONSE_BODY='{"message": "Task deleted successfully"}'
            else
                STATUS_HEADER="Status: 404 Not Found"
                RESPONSE_BODY='{"error": "Task not found", "message": "Task with specified ID does not exist"}'
            fi
        else
            STATUS_HEADER="Status: 400 Bad Request"
            RESPONSE_BODY='{"error": "Missing task ID", "message": "Task ID is required for DELETE requests"}'
        fi
        ;;
    
    *)
        STATUS_HEADER="Status: 405 Method Not Allowed"
        RESPONSE_BODY='{"error": "Method not allowed", "message": "Supported methods: GET, POST, PUT, DELETE"}'
        ;;
esac

# Emit status (if any), end headers, then body
if [ -n "$STATUS_HEADER" ]; then
    echo "$STATUS_HEADER"
fi
echo ""
echo "$RESPONSE_BODY"
