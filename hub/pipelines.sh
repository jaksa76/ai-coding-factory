#!/bin/bash

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "AI Coding Factory Pipeline Hub"
    echo ""
    echo "Commands:"
    echo "  start      Start a new pipeline for a task"
    echo "  status     Show pipeline status"
    echo "  stop       Stop a running pipeline"
    echo "  logs       Get logs from a running pipeline"
    echo "  list       List pipelines for a task or all pipelines"
    echo ""
    echo "$0 start --task-id <task-id> --pipeline-id <pipeline-id> --task-description \"<description>\" [--git-url <git-url>] [--git-username <username>] [--git-token <token>]"
    echo ""
    echo "$0 status --task-id <task-id> --pipeline-id <pipeline-id>"
    echo ""
    echo "$0 stop --task-id <task-id> --pipeline-id <pipeline-id>"
    echo ""
    echo "$0 logs --task-id <task-id> --pipeline-id <pipeline-id>"
    echo ""
    echo "$0 list --task-id <task-id>"
    echo ""
    echo "Git options:"
    echo "  --git-url         Git repository URL"
    echo "  --git-username    Git username for authentication"
    echo "  --git-token       Git access token for authentication"
    echo ""
    echo "Note: Git credentials can also be provided via environment variables:"
    echo "      GIT_REPO_URL, GIT_USERNAME, GIT_TOKEN"
    echo "      If --pipeline-id is not provided, operations will use the task-id for backward compatibility"
    echo ""
}

require_param() {
    local param_name="$1"
    local param_value="$2"
    local cmd="$3"
    if [ -z "$param_value" ]; then
    echo "Error: --$param_name is required for $cmd command"
    exit 1
    fi
}


# Check if no arguments provided
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        start|status|stop|logs|list)
            COMMAND=$1
            shift
            ;;
        --task-id)
            TASK_ID=$2
            shift 2
            ;;
        --pipeline-id)
            PIPELINE_ID=$2
            shift 2
            ;;
        --task-description)
            TASK_DESCRIPTION=$2
            shift 2
            ;;
        --git-url)
            GIT_REPO_URL=$2
            shift 2
            ;;
        --git-username)
            GIT_USERNAME=$2
            shift 2
            ;;
        --git-token)
            GIT_TOKEN=$2
            shift 2
            ;;
        *)
            echo "Error: Unknown option or command '$1'"
            echo ""
            show_usage
            exit 1
            ;;
    esac
done

# Execute the command
case $COMMAND in
    start)
        require_param "task-id" "$TASK_ID" "start"
        require_param "pipeline-id" "$PIPELINE_ID" "start"
        require_param "task-description" "$TASK_DESCRIPTION" "start"
        
        echo "Starting pipeline '$PIPELINE_ID' for task '$TASK_ID'..."
        
        # Define volume name and container name based on pipeline ID
        VOLUME_NAME="vol-$TASK_ID-$PIPELINE_ID"
        CONTAINER_NAME="pipe-$TASK_ID-$PIPELINE_ID"
        IMAGE_NAME="coding-pipeline:latest" # Assuming the image is tagged as 'coding-pipeline:latest'

        # 1. Create a volume
        echo "Creating volume '$VOLUME_NAME'..."
        ./agents.sh create-volume --volume-name "$VOLUME_NAME"
        
        # 2. Start the container with environment variables
        echo "Starting container '$CONTAINER_NAME'..."
        
        # Build the agent command with basic environment variables
        AGENT_COMMAND="./agents.sh start-container --container-name \"$CONTAINER_NAME\" --volume \"$VOLUME_NAME\" --image \"$IMAGE_NAME\" --command \"/app/pipeline.sh\" --env \"TASK_ID=$TASK_ID\" --env \"PIPELINE_ID=$PIPELINE_ID\" --env \"TASK_DESCRIPTION=$TASK_DESCRIPTION\""
        
        # Add git environment variables if provided via command line or environment
        if [ -n "$GIT_REPO_URL" ]; then
            AGENT_COMMAND="$AGENT_COMMAND --env \"GIT_REPO_URL=$GIT_REPO_URL\""
            echo "Git repository URL: $GIT_REPO_URL"
        fi
        
        if [ -n "$GIT_USERNAME" ]; then
            AGENT_COMMAND="$AGENT_COMMAND --env \"GIT_USERNAME=$GIT_USERNAME\""
            echo "Git username: $GIT_USERNAME"
        fi
        
        if [ -n "$GIT_TOKEN" ]; then
            AGENT_COMMAND="$AGENT_COMMAND --env \"GIT_TOKEN=$GIT_TOKEN\""
            echo "Git token: [REDACTED - length: ${#GIT_TOKEN} characters]"
        fi
        
        # Execute the command
        eval $AGENT_COMMAND
        
        echo "Pipeline '$PIPELINE_ID' for task '$TASK_ID' started successfully."
        ;;
        
    status)
        require_param "task-id" "$TASK_ID" "status"
        require_param "pipeline-id" "$PIPELINE_ID" "status"
        
        CONTAINER_NAME="pipe-$TASK_ID-$PIPELINE_ID"
        ./agents.sh status-container --container-name "$CONTAINER_NAME"
        ;;
        
    stop)
        require_param "task-id" "$TASK_ID" "stop"
        require_param "pipeline-id" "$PIPELINE_ID" "stop"

        CONTAINER_NAME="pipe-$TASK_ID-$PIPELINE_ID"
        ./agents.sh stop-container --container-name "$CONTAINER_NAME"
        ;;
        
    logs)
        require_param "task-id" "$TASK_ID" "logs"
        require_param "pipeline-id" "$PIPELINE_ID" "logs"

        CONTAINER_NAME="pipe-$TASK_ID-$PIPELINE_ID"
        echo "Getting logs for pipeline '$PIPELINE_ID' (container '$CONTAINER_NAME')..."
        ./agents.sh logs-container --container-name "$CONTAINER_NAME"
        ;;

    list)
        require_param "task-id" "$TASK_ID" "list"
        
        ./agents.sh list-containers | grep "$TASK_ID"
        ;;
        
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac