#!/bin/bash

# Function to display usage information
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "AI Coding Factory Agent Hub"
    echo ""
    echo "Commands:"
    echo "  create-volume       Create a new volume that can be attached to a container"
    echo "  delete-volume       Delete an existing volume"
    echo "  start-container     Start an agent container"
    echo "  stop-container      Stop an agent container"
    echo "  status-container    Show agent container status"
    echo "  list-containers     List available agent containers"
    echo ""
    echo "$0 create-volume --volume-name <volume-name>"
    echo ""
    echo "$0 delete-volume --volume-name <volume-name>"
    echo ""
    echo "$0 start-container --container-name <container-name> --volume <volume_name> --image <image_name> [--command <command>]"
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
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        create-volume|delete-volume|start-container|stop-container|status-container|list-containers)
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
        echo "Creating volume '$VOLUME_NAME'..."

        # create volume on AWS EFS
        aws efs create-file-system --creation-token "$VOLUME_NAME"

        ;;
    delete-volume)
        if [ -z "$VOLUME_NAME" ]; then
            echo "Error: --volume-name is required for delete-volume command"
            exit 1
        fi
        echo "Deleting volume '$VOLUME_NAME'..."
        
        # Find the file system by creation token (volume name)
        echo "Looking up file system with creation token '$VOLUME_NAME'..."
        FILE_SYSTEM_ID=$(aws efs describe-file-systems --query "FileSystems[?CreationToken=='$VOLUME_NAME'].FileSystemId" --output text)
        
        if [ -z "$FILE_SYSTEM_ID" ] || [ "$FILE_SYSTEM_ID" = "None" ]; then
            echo "Error: No file system found with creation token '$VOLUME_NAME'"
            exit 1
        fi
        
        echo "Found file system ID: $FILE_SYSTEM_ID"
        
        # Check if there are any mount targets and delete them first
        echo "Checking for mount targets..."
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$FILE_SYSTEM_ID" --query "MountTargets[].MountTargetId" --output text)
        
        if [ -n "$MOUNT_TARGETS" ] && [ "$MOUNT_TARGETS" != "None" ]; then
            echo "Deleting mount targets..."
            for MOUNT_TARGET_ID in $MOUNT_TARGETS; do
                echo "Deleting mount target: $MOUNT_TARGET_ID"
                aws efs delete-mount-target --mount-target-id "$MOUNT_TARGET_ID"
            done
            
            # Wait for mount targets to be deleted
            echo "Waiting for mount targets to be deleted..."
            while [ "$(aws efs describe-mount-targets --file-system-id "$FILE_SYSTEM_ID" --query "length(MountTargets)" --output text)" != "0" ]; do
                echo "Still waiting for mount targets to be deleted..."
                sleep 5
            done
        fi
        
        # Delete the file system
        echo "Deleting file system '$FILE_SYSTEM_ID'..."
        aws efs delete-file-system --file-system-id "$FILE_SYSTEM_ID"
        
        echo "Volume '$VOLUME_NAME' has been successfully deleted."
        ;;
    start-container)
        echo "Starting container '$CONTAINER_NAME'..."
        # Add your start container logic here
        ;;
    stop-container)
        echo "Stopping container '$CONTAINER_NAME'..."
        # Add your stop container logic here
        ;;
    status-container)
        echo "Showing status for container '$CONTAINER_NAME'..."
        # Add your status container logic here
        ;;
    list-containers)
        echo "Listing available containers..."
        # Add your list containers logic here
        ;;
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac