#!/bin/bash

# Test script for Tasks API
# Usage: ./test_tasks_api.sh [base_url]

BASE_URL=${1:-"http://localhost:8080"}
API_URL="$BASE_URL/api/tasks.cgi"

echo "Testing AI Coding Factory Tasks API"
echo "API URL: $API_URL"
echo "=================================="
echo

# Test 1: Create a task
echo "1. Creating a new task..."
TASK1_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"description": "Implement user authentication system"}' \
    "$API_URL")

echo "Response: $TASK1_RESPONSE"
TASK1_ID=$(echo "$TASK1_RESPONSE" | jq -r '.id' 2>/dev/null)
echo "Task ID: $TASK1_ID"
echo

# Test 2: Create another task
echo "2. Creating another task..."
TASK2_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"description": "Set up CI/CD pipeline"}' \
    "$API_URL")

echo "Response: $TASK2_RESPONSE"
TASK2_ID=$(echo "$TASK2_RESPONSE" | jq -r '.id' 2>/dev/null)
echo "Task ID: $TASK2_ID"
echo

# Test 3: List all tasks
echo "3. Listing all tasks..."
curl -s -X GET "$API_URL" | jq .
echo

# Test 4: Get specific task
if [ -n "$TASK1_ID" ]; then
    echo "4. Getting task $TASK1_ID..."
    curl -s -X GET "$API_URL/$TASK1_ID" | jq .
    echo
fi

# Test 5: Update task status
if [ -n "$TASK1_ID" ]; then
    echo "5. Updating task $TASK1_ID status to 'in_progress'..."
    curl -s -X PUT \
        -H "Content-Type: application/json" \
        -d '{"status": "in_progress"}' \
        "$API_URL/$TASK1_ID" | jq .
    echo
fi

# Test 6: Update task description and status
if [ -n "$TASK2_ID" ]; then
    echo "6. Updating task $TASK2_ID description and status..."
    curl -s -X PUT \
        -H "Content-Type: application/json" \
        -d '{"description": "Set up CI/CD pipeline with GitHub Actions", "status": "completed"}' \
        "$API_URL/$TASK2_ID" | jq .
    echo
fi

# Test 7: List all tasks again to see updates
echo "7. Listing all tasks after updates..."
curl -s -X GET "$API_URL" | jq .
echo

# Test 8: Delete a task
if [ -n "$TASK2_ID" ]; then
    echo "8. Deleting task $TASK2_ID..."
    curl -s -X DELETE "$API_URL/$TASK2_ID" | jq .
    echo
fi

# Test 9: List tasks after deletion
echo "9. Listing all tasks after deletion..."
curl -s -X GET "$API_URL" | jq .
echo

# Test 10: Try to get deleted task (should return 404)
if [ -n "$TASK2_ID" ]; then
    echo "10. Trying to get deleted task $TASK2_ID (should return 404)..."
    curl -s -X GET "$API_URL/$TASK2_ID"
    echo
fi

echo "=================================="
echo "API testing completed!"
