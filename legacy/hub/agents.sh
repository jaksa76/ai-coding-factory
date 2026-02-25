#!/bin/bash

# Default to docker if AGENT_HOST is not set
AGENT_HOST=${AGENT_HOST:-docker}

if [ "$AGENT_HOST" = "docker" ]; then
    # Use the local docker agent script
    ./agents-docker.sh "$@"
elif [ "$AGENT_HOST" = "aws" ]; then
    # Use the aws agent script
    ./agents-aws.sh "$@"
else
    echo "Error: Unknown AGENT_HOST '$AGENT_HOST'"
    echo "Valid options are 'docker' or 'aws'"
    exit 1
fi
