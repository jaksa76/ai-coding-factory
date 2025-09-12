# Use Alpine Linux as base image
FROM alpine:latest

# Install bash (since Alpine uses ash by default) and git
RUN apk add --no-cache bash git

# Set working directory
WORKDIR /app

# Copy the pipeline script
COPY pipeline.sh /app/

# Make the script executable
RUN chmod +x /app/pipeline.sh

# Set default environment variables (can be overridden at runtime)
ENV TASK_ID=""
ENV TASK_DESCRIPTION=""
ENV GIT_REPO_URL=""
ENV GIT_USERNAME=""
ENV GIT_TOKEN=""

# Run the pipeline script
CMD ["/app/pipeline.sh"]
