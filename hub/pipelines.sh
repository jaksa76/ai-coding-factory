#!/bin/bash

# Function to display usage information
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
    echo ""
    echo "$0 start --task-id <task-id> --task-description \"<description>\""
    echo ""
    echo "$0 status --task-id <task-id>"
    echo ""
    echo "$0 stop --task-id <task-id>"
    echo ""
    echo "$0 logs --task-id <task-id>"
    echo ""
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
        start|status|stop|logs)
            COMMAND=$1
            shift
            ;;
        --task-id)
            TASK_ID=$2
            shift 2
            ;;
        --task-description)
            TASK_DESCRIPTION=$2
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
        if [ -z "$TASK_ID" ]; then
            echo "Error: --task-id is required for start command"
            exit 1
        fi
        if [ -z "$TASK_DESCRIPTION" ]; then
            echo "Error: --task-description is required for start command"
            exit 1
        fi
        
        echo "Starting pipeline for task '$TASK_ID'..."
        
        # Define volume name and container name based on task ID
        VOLUME_NAME="vol-$TASK_ID"
        CONTAINER_NAME="pipe-$TASK_ID"
        IMAGE_NAME="coding-pipeline:latest" # Assuming the image is tagged as 'coding-pipeline:latest'

        # 1. Create a volume
        echo "Creating volume '$VOLUME_NAME'..."
        ./agents.sh create-volume --volume-name "$VOLUME_NAME"
        
        # 2. Start the container
        echo "Starting container '$CONTAINER_NAME'..."
        ./agents.sh start-container \
            --container-name "$CONTAINER_NAME" \
            --volume "$VOLUME_NAME" \
            --image "$IMAGE_NAME" \
            --command "/app/pipeline.sh" \
            --env "TASK_ID=$TASK_ID" \
            --env "TASK_DESCRIPTION=$TASK_DESCRIPTION"
        
        echo "Pipeline for task '$TASK_ID' started successfully."
        ;;
        
    status)
        if [ -z "$TASK_ID" ]; then
            echo "Error: --task-id is required for status command"
            exit 1
        fi
        
        CONTAINER_NAME="pipe-$TASK_ID"
        echo "Checking status for pipeline '$CONTAINER_NAME'..."
        ./agents.sh status-container --container-name "$CONTAINER_NAME"
        ;;
        
    stop)
        if [ -z "$TASK_ID" ]; then
            echo "Error: --task-id is required for stop command"
            exit 1
        fi
        
        CONTAINER_NAME="pipe-$TASK_ID"
        echo "Stopping pipeline '$CONTAINER_NAME'..."
        ./agents.sh stop-container --container-name "$CONTAINER_NAME"
        ;;
        
    logs)
        if [ -z "$TASK_ID" ]; then
            echo "Error: --task-id is required for logs command"
            exit 1
        fi
        
        CONTAINER_NAME="pipe-$TASK_ID"
        echo "Getting logs for pipeline '$CONTAINER_NAME'..."
        ./agents.sh logs-container --container-name "$CONTAINER_NAME"
        ;;
        
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac
