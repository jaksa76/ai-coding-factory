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
    echo ""
    echo "$0 stop-container --container-name <container-name>"
    echo ""
    echo "$0 status-container --container-name <container-name>"
    echo ""
    echo "$0 list-containers"
    echo ""
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
        create-volume|delete-volume|list-volumes|start-container|stop-container|status-container|list-containers)
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
        if [ -z "$VOLUME_NAME" ]; then
            echo "Error: --volume-name is required for create-volume command"
            exit 1
        fi
        echo "Creating Docker volume '$VOLUME_NAME'..."
        docker volume create "$VOLUME_NAME"
        ;;
    delete-volume)
        if [ -z "$VOLUME_NAME" ]; then
            echo "Error: --volume-name is required for delete-volume command"
            exit 1
        fi
        echo "Deleting Docker volume '$VOLUME_NAME'..."
        docker volume rm "$VOLUME_NAME"
        ;;
    list-volumes)
        echo "Listing all Docker volumes..."
        docker volume ls
        ;;
    start-container)
        if [ -z "$CONTAINER_NAME" ]; then
            echo "Error: --container-name is required for start-container command"
            exit 1
        fi
        if [ -z "$VOLUME" ]; then
            echo "Error: --volume is required for start-container command"
            exit 1
        fi
        if [ -z "$IMAGE_NAME" ]; then
            echo "Error: --image is required for start-container command"
            exit 1
        fi
        
        echo "Starting Docker container '$CONTAINER_NAME'..."
        
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
        docker run -d --name "$CONTAINER_NAME" \
            -v "$VOLUME:/workspace" \
            "${ENV_VARS[@]}" \
            "$IMAGE_NAME" \
            $CONTAINER_OPTION

        echo "Docker container '$CONTAINER_NAME' started successfully!"
        echo "Volume '$VOLUME' is mounted at /workspace"
        ;;
    stop-container)
        if [ -z "$CONTAINER_NAME" ]; then
            echo "Error: --container-name is required for stop-container command"
            exit 1
        fi
        
        echo "Stopping Docker container '$CONTAINER_NAME'..."
        docker stop "$CONTAINER_NAME"
        
        echo "Would you like to remove the container? (y/n)"
        read -r REMOVE_CONTAINER
        if [ "$REMOVE_CONTAINER" = "y" ] || [ "$REMOVE_CONTAINER" = "Y" ]; then
            docker rm "$CONTAINER_NAME"
            echo "Container '$CONTAINER_NAME' removed."
        fi
        ;;
    status-container)
        if [ -z "$CONTAINER_NAME" ]; then
            echo "Error: --container-name is required for status-container command"
            exit 1
        fi
        
        echo "Checking status for Docker container '$CONTAINER_NAME'..."
        docker ps -a --filter "name=$CONTAINER_NAME"
        
        echo ""
        echo "--- DETAILS ---"
        docker inspect "$CONTAINER_NAME"
        ;;
    list-containers)
        echo "Listing AI Coding Factory Docker containers..."
        docker ps -a --filter "name=ai-coding-factory-task-*"
        ;;
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac
