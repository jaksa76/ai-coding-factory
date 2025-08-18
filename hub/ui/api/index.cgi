#!/bin/bash

# API Index endpoint for AI Coding Factory Hub
# Lists available API endpoints and their documentation

# Set content type for JSON response
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# Handle preflight OPTIONS request
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

if [ "$REQUEST_METHOD" != "GET" ]; then
    echo "Status: 405 Method Not Allowed"
    echo ""
    echo '{"error": "Method not allowed", "message": "This endpoint only supports GET requests"}'
    exit 1
fi

# API documentation response
cat << 'EOF'
{
  "name": "AI Coding Factory Hub API",
  "version": "1.0.0",
  "description": "REST API for managing AI coding tasks and hub operations",
  "endpoints": {
    "status": {
      "path": "/api/status.cgi",
      "methods": ["GET"],
      "description": "Get service status and health information"
    },
    "tasks": {
      "path": "/api/tasks.cgi",
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "description": "CRUD operations for task management",
      "usage": {
        "list_all": {
          "method": "GET",
          "path": "/api/tasks.cgi",
          "description": "List all tasks"
        },
        "get_task": {
          "method": "GET",
          "path": "/api/tasks.cgi/{task_id}",
          "description": "Get a specific task by ID"
        },
        "create_task": {
          "method": "POST",
          "path": "/api/tasks.cgi",
          "description": "Create a new task",
          "body": {
            "description": "string (required) - Task description"
          }
        },
        "update_task": {
          "method": "PUT",
          "path": "/api/tasks.cgi/{task_id}",
          "description": "Update an existing task",
          "body": {
            "description": "string (optional) - Updated task description",
            "status": "string (optional) - Updated task status (pending, in_progress, completed, failed)"
          }
        },
        "delete_task": {
          "method": "DELETE",
          "path": "/api/tasks.cgi/{task_id}",
          "description": "Delete a task"
        }
      }
    }
  },
  "data_storage": {
    "location": "$DATA_DIR/tasks/",
    "format": "JSON files (one per task)",
    "structure": {
      "id": "string - Unique task identifier",
      "description": "string - Task description",
      "status": "string - Task status (pending, in_progress, completed, failed)",
      "created_at": "string - ISO 8601 timestamp",
      "updated_at": "string - ISO 8601 timestamp"
    }
  },
  "examples": {
    "create_task": {
      "request": {
        "method": "POST",
        "url": "/api/tasks.cgi",
        "headers": {
          "Content-Type": "application/json"
        },
        "body": {
          "description": "Implement user authentication system"
        }
      }
    },
    "update_task": {
      "request": {
        "method": "PUT",
        "url": "/api/tasks.cgi/task_1692345678_123",
        "headers": {
          "Content-Type": "application/json"
        },
        "body": {
          "status": "completed"
        }
      }
    }
  }
}
EOF
