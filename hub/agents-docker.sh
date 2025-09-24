#!/bin/bash

# Function to display usage information
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "AI Coding Factory Agent Hub (Docker)"
    echo ""
    echo "Commands:"
    echo "  create-volume       Create a new Docker volume"
    echo "  delete-volume       Delete an existing Docker volume"
    echo "  list-volumes        List Docker volumes"
    echo "  start-container     Start an agent container using Docker"
    echo "  stop-container      Stop an agent container"
    echo "  status-container    Show agent container status"
    echo "  list-containers     List available agent containers"
    echo ""
    echo "$0 create-volume --volume-name <volume-name>"
    echo ""
    echo "$0 delete-volume --volume-name <volume-name>"
    echo ""
    echo "$0 list-volumes"
    echo ""
    echo "$0 start-container --container-name <container-name> --volume <volume_name> --image <image_name> [--command <command>] [--env <KEY=VALUE>]"
    echo "  Note: Container name will be prefixed with 'ai-coding-factory-container-'"
    echo ""
    echo "$0 stop-container --container-name <container-name>"
    echo ""
    echo "$0 status-container --container-name <container-name>"
    echo ""
    echo "$0 list-containers"
    echo ""
    echo "$0 logs-container --container-name <container-name>"
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
ENV_VARS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        create-volume|delete-volume|list-volumes|start-container|stop-container|status-container|list-containers|logs-container)
            COMMAND=$1
            shift
            ;;
        --volume-name)
            VOLUME_NAME=$2
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME=$2
            shift 2
            ;;
        --volume)
            VOLUME=$2
            shift 2
            ;;
        --image)
            IMAGE_NAME=$2
            shift 2
            ;;
        --command)
            CONTAINER_COMMAND=$2
            shift 2
            ;;
        --env)
            ENV_VARS+=("-e" "$2")
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
    create-volume)
        require_param "volume-name" "$VOLUME_NAME" "$COMMAND"
        echo "Creating Docker volume '$VOLUME_NAME'..."
        docker volume create "$VOLUME_NAME"
        ;;
    delete-volume)
        require_param "volume-name" "$VOLUME_NAME" "$COMMAND"
        echo "Deleting Docker volume '$VOLUME_NAME'..."
        docker volume rm "$VOLUME_NAME"
        ;;
    list-volumes)
        echo "Listing all Docker volumes..."
        docker volume ls
        ;;
    start-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        require_param "volume" "$VOLUME" "$COMMAND"
        require_param "image" "$IMAGE_NAME" "$COMMAND"
        
        # Add prefix to container name
        FULL_CONTAINER_NAME="ai-coding-factory-container-$CONTAINER_NAME"
        
        echo "Starting Docker container '$FULL_CONTAINER_NAME'..."
        
        # override image command if one is provided
        if [ "$CONTAINER_COMMAND" ]; then
            CONTAINER_OPTION="sh -c '$CONTAINER_COMMAND'"
        fi
        
        # Check if volume exists
        docker volume inspect "$VOLUME" >/dev/null 2>&1 || {
            echo "Volume '$VOLUME' does not exist. Please create it first:"
            echo "$0 create-volume --volume-name $VOLUME"
            exit 1
        }
        
        # Run the container
        docker run -d --name "$FULL_CONTAINER_NAME" \
            -v "$VOLUME:/workspace" \
            "${ENV_VARS[@]}" \
            "$IMAGE_NAME" \
            $CONTAINER_OPTION

        echo "Docker container '$FULL_CONTAINER_NAME' started successfully!"
        echo "Volume '$VOLUME' is mounted at /workspace"
        ;;
    stop-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        # Add prefix to container name
        FULL_CONTAINER_NAME="ai-coding-factory-container-$CONTAINER_NAME"
        
        echo "Stopping Docker container '$FULL_CONTAINER_NAME'..."
        docker stop "$FULL_CONTAINER_NAME"
        ;;
    status-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        # Add prefix to container name
        FULL_CONTAINER_NAME="ai-coding-factory-container-$CONTAINER_NAME"
        
        echo "Checking status for Docker container '$FULL_CONTAINER_NAME'..."
        docker ps -a --filter "name=$FULL_CONTAINER_NAME"
        
        echo ""
        echo "--- DETAILS ---"
        docker inspect "$FULL_CONTAINER_NAME"
        ;;
    list-containers)
        echo "Listing AI Coding Factory Docker containers..."
        docker ps -a --filter "name=ai-coding-factory-container-*" --format "{{.Names}}" | sed 's/^ai-coding-factory-container-//'
        ;;
    logs-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        # Add prefix to container name
        FULL_CONTAINER_NAME="ai-coding-factory-container-$CONTAINER_NAME"
        
        echo "Getting logs for Docker container '$FULL_CONTAINER_NAME'..."
        docker logs "$FULL_CONTAINER_NAME"
        ;;
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac
