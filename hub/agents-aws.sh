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

# Function to create ECS execution role if it doesn't exist
create_ecs_execution_role() {
    echo "Checking for ECS execution role..."
    
    # Check if role exists
    aws iam get-role --role-name ecsTaskExecutionRole >/dev/null 2>&1 || {
        echo "ECS task execution role not found. Attempting to create it..."
        
        # Create trust policy
        cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        # Try to create the role
        if aws iam create-role \
            --role-name ecsTaskExecutionRole \
            --assume-role-policy-document file:///tmp/trust-policy.json >/dev/null 2>&1; then
            
            # Attach the managed policy
            aws iam attach-role-policy \
                --role-name ecsTaskExecutionRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
            
            echo "ECS execution role created successfully"
        else
            echo "Warning: Could not create ECS execution role. You may need to:"
            echo "1. Create the role manually in the AWS Console"
            echo "2. Ask your administrator to create it"
            echo "3. Use an existing role by modifying the script"
            echo ""
            echo "Continuing anyway - the task may fail if the role doesn't exist..."
        fi
        
        # Clean up
        rm -f /tmp/trust-policy.json
    }
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
            ENV_VARS+=("$2")
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
        echo "Creating volume '$VOLUME_NAME'..."

        # create volume on AWS EFS
        aws efs create-file-system --creation-token "$VOLUME_NAME"

        ;;
    delete-volume)
        require_param "volume-name" "$VOLUME_NAME" "$COMMAND"
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
    list-volumes)
        echo "Listing all volumes..."
        aws efs describe-file-systems --query "FileSystems[].CreationToken" --output text | tr '\t' '\n'
        ;;
    start-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        require_param "volume" "$VOLUME" "$COMMAND"
        require_param "image" "$IMAGE_NAME" "$COMMAND"
        
        echo "Starting ECS container '$CONTAINER_NAME'..."
        
        # Ensure ECS execution role exists
        create_ecs_execution_role
        
        # Find the EFS file system by creation token (volume name)
        echo "Looking up EFS file system for volume '$VOLUME'..."
        FILE_SYSTEM_ID=$(aws efs describe-file-systems --query "FileSystems[?CreationToken=='$VOLUME'].FileSystemId" --output text)
        
        if [ -z "$FILE_SYSTEM_ID" ] || [ "$FILE_SYSTEM_ID" = "None" ]; then
            echo "Error: No EFS file system found with creation token '$VOLUME'"
            echo "Please create the volume first using: $0 create-volume --volume-name $VOLUME"
            exit 1
        fi
        
        echo "Found EFS file system ID: $FILE_SYSTEM_ID"
        
        # Get the default VPC and subnets
        echo "Getting VPC and subnet information..."
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
        if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
            echo "Error: No default VPC found"
            exit 1
        fi
        
        # Get first subnet ID
        SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)
        if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
            echo "Error: No subnets found in VPC $VPC_ID"
            exit 1
        fi
        
        echo "Using VPC: $VPC_ID, Subnet: $SUBNET_ID"
        
        # Ensure ECS cluster exists
        CLUSTER_NAME="ai-coding-factory"
        echo "Checking for ECS cluster '$CLUSTER_NAME'..."
        
        aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query "clusters[0].clusterName" --output text 2>/dev/null | grep -q "$CLUSTER_NAME" || {
            echo "Creating ECS cluster '$CLUSTER_NAME'..."
            aws ecs create-cluster --cluster-name "$CLUSTER_NAME"
        }
        
        # Set default command if not provided
        if [ -z "$CONTAINER_COMMAND" ]; then
            CONTAINER_COMMAND="sleep 3600"
        fi
        
        # Create task definition
        TASK_DEF_NAME="ai-coding-factory-task-$CONTAINER_NAME"
        echo "Creating ECS task definition '$TASK_DEF_NAME'..."
        
        # Build environment variables JSON
        ENV_JSON=""
        if [ ${#ENV_VARS[@]} -gt 0 ]; then
            ENV_JSON="\"environment\": ["
            for ENV_VAR in "${ENV_VARS[@]}"; do
                KEY=$(echo "$ENV_VAR" | cut -d'=' -f1)
                VALUE=$(echo "$ENV_VAR" | cut -d'=' -f2-)
                ENV_JSON="$ENV_JSON{\"name\": \"$KEY\", \"value\": \"$VALUE\"},"
            done
            # Remove trailing comma
            ENV_JSON=${ENV_JSON%,}
            ENV_JSON="$ENV_JSON],"
        fi
        
        cat > /tmp/task-definition.json << EOF
{
    "family": "$TASK_DEF_NAME",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "containerDefinitions": [
        {
            "name": "$CONTAINER_NAME",
            "image": "$IMAGE_NAME",
            "essential": true,
            $ENV_JSON
            "command": ["sh", "-c", "$CONTAINER_COMMAND"],
            "mountPoints": [
                {
                    "sourceVolume": "efs-volume",
                    "containerPath": "/workspace"
                }
            ]
        }
    ],
    "volumes": [
        {
            "name": "efs-volume",
            "efsVolumeConfiguration": {
                "fileSystemId": "$FILE_SYSTEM_ID",
                "rootDirectory": "/",
                "transitEncryption": "ENABLED"
            }
        }
    ]
}
EOF
        
        # Create CloudWatch log group if it doesn't exist
        aws logs create-log-group --log-group-name "/ecs/ai-coding-factory" 2>/dev/null || true
        
        # Register task definition
        aws ecs register-task-definition --cli-input-json file:///tmp/task-definition.json
        
        # Get security group for VPC
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)
        
        # Run the task
        echo "Starting ECS task..."
        TASK_ARN=$(aws ecs run-task \
            --cluster "$CLUSTER_NAME" \
            --task-definition "$TASK_DEF_NAME" \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=DISABLED}" \
            --query "tasks[0].taskArn" \
            --output text)
        
        if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
            echo "ECS task started successfully!"
            echo "Task ARN: $TASK_ARN"
            echo "Container name: $CONTAINER_NAME"
            echo "Volume '$VOLUME' is mounted at /workspace"
            echo ""
            echo "To check status, run:"
            echo "  $0 status-container --container-name $CONTAINER_NAME"
            echo ""
            echo "To stop the container, run:"
            echo "  $0 stop-container --container-name $CONTAINER_NAME"
        else
            echo "Error: Failed to start ECS task"
            exit 1
        fi
        
        # Clean up temp file
        rm -f /tmp/task-definition.json
        ;;

    stop-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        echo "Stopping ECS container '$CONTAINER_NAME'..."
        
        CLUSTER_NAME="ai-coding-factory"
        TASK_DEF_NAME="ai-coding-factory-task-$CONTAINER_NAME"
        
        # Find running tasks for this container
        echo "Looking for running tasks..."
        TASK_ARNS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_DEF_NAME" --desired-status RUNNING --query "taskArns" --output text)
        
        if [ -z "$TASK_ARNS" ] || [ "$TASK_ARNS" = "None" ]; then
            echo "No running tasks found for container '$CONTAINER_NAME'"
            
            # Check if there are any stopped tasks
            STOPPED_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_DEF_NAME" --desired-status STOPPED --query "taskArns" --output text)
            if [ -n "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
                echo "Container '$CONTAINER_NAME' is already stopped"
            else
                echo "Container '$CONTAINER_NAME' not found"
                exit 1
            fi
        else
            # Stop all running tasks
            for TASK_ARN in $TASK_ARNS; do
                echo "Stopping task: $TASK_ARN"
                aws ecs stop-task --cluster "$CLUSTER_NAME" --task "$TASK_ARN"
            done
            
            echo "Container '$CONTAINER_NAME' has been stopped"
        fi        
        ;;

    status-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        echo "Checking status for ECS container '$CONTAINER_NAME'..."
        
        CLUSTER_NAME="ai-coding-factory"
        TASK_DEF_NAME="ai-coding-factory-task-$CONTAINER_NAME"
        
        # Check for running tasks
        echo ""
        echo "=== RUNNING TASKS ==="
        RUNNING_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_DEF_NAME" --desired-status RUNNING --query "taskArns" --output text)
        
        if [ -n "$RUNNING_TASKS" ] && [ "$RUNNING_TASKS" != "None" ]; then
            for TASK_ARN in $RUNNING_TASKS; do
                echo "Task ARN: $TASK_ARN"
                
                # Get detailed task information
                aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query "tasks[0].{LastStatus:lastStatus,DesiredStatus:desiredStatus,CreatedAt:createdAt,StartedAt:startedAt,CPU:cpu,Memory:memory,PlatformVersion:platformVersion}" --output table
                
                # Get task definition details
                TASK_DEF_ARN=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query "tasks[0].taskDefinitionArn" --output text)
                echo ""
                echo "Task Definition: $TASK_DEF_ARN"
                
                # Get container details
                echo ""
                echo "Container Details:"
                aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query "tasks[0].containers[0].{Name:name,LastStatus:lastStatus,HealthStatus:healthStatus,NetworkInterfaces:networkInterfaces}" --output table
                
                echo ""
                echo "---"
            done
        else
            echo "No running tasks found"
        fi
        
        # Check for stopped tasks (last 10)
        echo ""
        echo "=== RECENT STOPPED TASKS ==="
        STOPPED_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_DEF_NAME" --desired-status STOPPED --max-items 10 --query "taskArns" --output text)
        
        if [ -n "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
            for TASK_ARN in $STOPPED_TASKS; do
                echo "Task ARN: $TASK_ARN"
                
                # Get basic task information
                aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query "tasks[0].{LastStatus:lastStatus,StoppedReason:stoppedReason,StoppedAt:stoppedAt,CreatedAt:createdAt}" --output table
                
                echo "---"
            done
        else
            echo "No stopped tasks found"
        fi
        
        # Show task definition information
        echo ""
        echo "=== TASK DEFINITION ==="
        TASK_DEF_EXISTS=$(aws ecs describe-task-definition --task-definition "$TASK_DEF_NAME" --query "taskDefinition.family" --output text 2>/dev/null)
        
        if [ -n "$TASK_DEF_EXISTS" ] && [ "$TASK_DEF_EXISTS" != "None" ]; then
            aws ecs describe-task-definition --task-definition "$TASK_DEF_NAME" --query "taskDefinition.{Family:family,Revision:revision,Status:status,CPU:cpu,Memory:memory,NetworkMode:networkMode}" --output table
        else
            echo "No task definition found for '$TASK_DEF_NAME'"
        fi
        ;;

    list-containers)
        echo "Listing AI Coding Factory ECS containers..."
        echo ""
        
        CLUSTER_NAME="ai-coding-factory"
        
        # Check if cluster exists
        CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query "clusters[0].clusterName" --output text 2>/dev/null)
        
        if [ -z "$CLUSTER_EXISTS" ] || [ "$CLUSTER_EXISTS" = "None" ]; then
            echo "ECS cluster '$CLUSTER_NAME' not found"
            exit 0
        fi
        
        # List all task definitions with our prefix and extract container names
        TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "ai-coding-factory-task-" --query "taskDefinitionArns" --output text)
        
        if [ -n "$TASK_DEFS" ] && [ "$TASK_DEFS" != "None" ]; then
            for TASK_DEF in $TASK_DEFS; do
                # Extract container name from task definition ARN
                # Format: arn:aws:ecs:region:account:task-definition/ai-coding-factory-task-CONTAINER_NAME:revision
                CONTAINER_NAME=$(echo "$TASK_DEF" | sed 's/.*ai-coding-factory-task-\([^:]*\):.*/\1/')
                echo "$CONTAINER_NAME"
            done | sort -u
        fi
        ;;
    logs-container)
        require_param "container-name" "$CONTAINER_NAME" "$COMMAND"
        
        echo "Getting logs for ECS container '$CONTAINER_NAME'..."
        
        LOG_GROUP_NAME="/ecs/ai-coding-factory"
        
        # Find the latest log stream for the container
        LOG_STREAM_NAME=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-stream-name-prefix "ecs/$CONTAINER_NAME" \
            --order-by LastEventTime \
            --descending \
            --limit 1 \
            --query "logStreams[0].logStreamName" \
            --output text)
            
        if [ -z "$LOG_STREAM_NAME" ] || [ "$LOG_STREAM_NAME" = "None" ]; then
            echo "No log stream found for container '$CONTAINER_NAME'"
            exit 1
        fi
        
        echo "Found log stream: $LOG_STREAM_NAME"
        
        # Get log events
        aws logs get-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-stream-name "$LOG_STREAM_NAME" \
            --query "events[].message" \
            --output text
        ;;
    *)
        echo "Error: No valid command specified"
        show_usage
        exit 1
        ;;
esac