# AI Coding Factory Hub (Express + zx)

This hub now runs a Node.js Express server with zx for shell integration. It serves the static UI and exposes API endpoints compatible with the previous CGI paths.

## Features

- Express server with CORS and logging
- CRUD operations for tasks stored as JSON files in `$DATA_DIR/tasks/`
- Backwards-compatible routes: `/api/tasks.cgi`, `/api/status.cgi`
- Uses zx for shell-friendly scripting where needed

## API Endpoints

### Tasks API (`/api/tasks.cgi`)

#### List All Tasks
```bash
GET /api/tasks.cgi
```

#### Get Specific Task
```bash
GET /api/tasks.cgi/{task_id}
```

#### Create New Task
```bash
POST /api/tasks.cgi
Content-Type: application/json

{
    "description": "Task description"
}
```

#### Update Task
```bash
PUT /api/tasks.cgi/{task_id}
Content-Type: application/json

{
    "description": "Updated description (optional)",
    "status": "pending|in_progress|completed|failed (optional)"
}
```

#### Delete Task
```bash
DELETE /api/tasks.cgi/{task_id}
```

### Other Endpoints

- `GET /api/status.cgi` - Service status and health check

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
    -v /path/to/data:/data \
    --name hub \
    ai-coding-factory-hub

# Test the API
curl http://localhost:8080/api/tasks.cgi
```

## Dependencies

- Node.js 18+ (Dockerfile uses Node 20)
- Express, zx, fs-extra, morgan

## Security Notes

- The API currently has no authentication
- CORS is enabled for all origins (`*`)
- Data validation is basic - enhance for production use
- Consider implementing rate limiting for production

## File Structure

```
hub/
├── src/
│   ├── app.mjs             # Express app factory
│   ├── server.mjs          # Server entrypoint
│   ├── routes/
│   │   ├── status.mjs
│   │   └── tasks.mjs
│   └── utils/
│       └── storage.mjs
├── ui/                     # Static UI served by Express
├── agents.sh               # Existing shell agent (invoked as needed)
├── package.json
├── Dockerfile
└── README.md
```
