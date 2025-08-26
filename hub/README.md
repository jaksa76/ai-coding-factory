# AI Coding Factory Hub (Express + zx)

This hub now runs a Node.js Express server with zx for shell integration. It serves the static UI and exposes clean API endpoints. It also includes scripts for managing AI agent containers and coding pipelines on AWS.

## File Structure

```
hub/
├── src/
│   ├── app.mjs             # Express app factory (used by tests)
│   ├── server.mjs          # Server entrypoint
│   └── routes/
│       ├── status.mjs
│       └── tasks.mjs       # Includes storage logic
├── ui/                     # Static UI served by Express
├── agents.sh               # Existing shell agent (invoked as needed)
├── pipelines.sh             # New coding pipeline script
├── package.json
├── Dockerfile
└── README.md
```

## Environment Variables

- `DATA_DIR` - Base directory for data storage (default: `/tmp/ai-coding-factory`)
- Tasks are stored in `$DATA_DIR/tasks/`

## Testing

Run unit tests with vitest:

```bash
npm test
```

## Docker Support

Build and run the hub with Docker:

```bash
# Build the image
docker build -t ai-coding-factory-hub .

# Run the container
docker run -d \
    -p 8080:8080 \
    -e DATA_DIR=/data \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e AWS_REGION=$AWS_REGION \
    -v /var/run/docker.sock:/var/run/docker.sock \
    ai-coding-factory-hub
```

## Prerequisites

### AWS Authentication

The scripts in this hub use the AWS CLI to interact with your AWS account. You need to configure your AWS credentials. The simplest way is to set the following environment variables:

```bash
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY"
export AWS_REGION="eu-central-1"
```

Alternatively, you can use `aws configure` to set up your credentials.



## Features

- Express server with CORS and logging
- CRUD operations for tasks stored as JSON files in `$DATA_DIR/tasks/`
- Clean RESTful routes under `/api/*`
- Scripts to manage agent containers (`agents.sh`) and pipelines (`pipelines.sh`) on AWS ECS.
- Uses zx for shell-friendly scripting where needed

## API Endpoints

### Tasks API (`/api/tasks`)

#### List All Tasks
```bash
GET /api/tasks
```

#### Get Specific Task
```bash
GET /api/tasks/{task_id}
```

#### Create New Task
```bash
POST /api/tasks
Content-Type: application/json

{
    "description": "Task description"
}
```

#### Update Task
```bash
PUT /api/tasks/{task_id}
Content-Type: application/json

{
    "description": "Updated description (optional)",
    "status": "pending|in_progress|completed|failed (optional)"
}
```

#### Delete Task
```bash
DELETE /api/tasks/{task_id}
```

### Other Endpoints

- `GET /api/status` - Service status and health check

## Task Data Structure

Each task is stored as a JSON file with the following structure:

```json
{
    "id": "task_1692345678_123",
    "description": "Task description",
    "status": "pending",
    "created_at": "2023-08-18T10:30:00+00:00",
    "updated_at": "2023-08-18T10:30:00+00:00"
}
```

### Task Status Values
- `pending` - Task created but not started
- `in_progress` - Task is being worked on
- `completed` - Task finished successfully
- `failed` - Task encountered an error


## Security Notes

- The API currently has no authentication
- CORS is enabled for all origins (`*`)
- Data validation is basic - enhance for production use
- Consider implementing rate limiting for production

## Agents (`agents.sh`)

This script manages the lifecycle of agent containers on AWS ECS.

### Commands
-   `create-volume`: Creates an EFS file system to be used as a volume.
-   `delete-volume`: Deletes an EFS file system.
-   `start-container`: Starts an agent container on ECS Fargate.
-   `stop-container`: Stops a running agent container.
-   `status-container`: Shows the status of a container.
-   `list-containers`: Lists all running containers and task definitions.

### Usage
```bash
./agents.sh start-container --container-name my-agent --volume my-volume --image my-image:latest
```

## Pipelines (`pipelines.sh`)

This script orchestrates coding pipelines by leveraging `agents.sh`. Each pipeline runs in its own container and is associated with a specific task.

### Commands
-   `start`: Starts a new pipeline for a task.
-   `status`: Shows the status of a pipeline.
-   `stop`: Stops a running pipeline.

### Usage
```bash
./pipelines.sh start --task-id "task123" --task-description "Implement a new feature"
```
