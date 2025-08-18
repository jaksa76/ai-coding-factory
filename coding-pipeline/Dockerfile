# Use Alpine Linux as base image
FROM alpine:latest

# Install bash (since Alpine uses ash by default)
RUN apk add --no-cache bash

# Set working directory
WORKDIR /app

# Copy the pipeline script
COPY pipeline.sh /app/

# Make the script executable
RUN chmod +x /app/pipeline.sh

# Set default environment variables (can be overridden at runtime)
ENV TASK_ID=""
ENV TASK_DESCRIPTION=""

# Run the pipeline script
CMD ["/app/pipeline.sh"]