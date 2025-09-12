#!/bin/bash
exec 2>&1

# This script runs the coding pipeline for a given task (user story)
# It takes the information about the user story as a set of environment variables:
#   TASK_ID - The ID of the task to work on
#   TASK_DESCRIPTION - The description of the task
#   GIT_REPO_URL - The URL of the git repository
#   GIT_TOKEN - The git access token (optional)
#   GIT_USERNAME - The git username (optional)

# Define the pipeline stages
stages=("cloning" "refining" "planning" "implementing" "deploying" "verifying")

# Define the cloning stage
cloning() {
  echo "AGENT: Cloning the repository from ${GIT_REPO_URL}"
  cd /workspace
  # Clone the repository using the provided credentials (if any
  if [ -n "$GIT_USERNAME" ] && [ -n "$GIT_TOKEN" ]; then
    TRUNCATED_TOKEN="****${GIT_TOKEN: -4}"
    echo "AGENT: Using GIT_USERNAME=${GIT_USERNAME} and GIT_TOKEN=${TRUNCATED_TOKEN}"
    # Use sed to inject username and token into the URL
    # This is a bit of a hack, but it's simple and works for https URLs
    CLONE_URL=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_USERNAME}:${GIT_TOKEN}@|")
    git clone "$CLONE_URL" .
  else
    git clone "$GIT_REPO_URL" .
  fi
  sleep 2
  echo "AGENT: I have cloned the repository."
  ls -la
}

# Define the refining stage
refining() {
  echo "AGENT: Refining the requirements..."
  sleep 3
  echo "AGENT: First, I need to understand the requirements."
  echo "AGENT: Task ID: $TASK_ID"
  echo "AGENT: Task Description:"
  echo "$TASK_DESCRIPTION"
  echo
  echo "AGENT: Identifying vague points..."
  sleep 1
  echo "AGENT: Generating clarifying questions..."
  sleep 1
  echo "AGENT: Asking stakeholders for clarification on the requirements..."
  sleep 5
  echo "AGENT: Updating requirements with new information..."
  sleep 1
  echo "AGENT: I have refined the requirements."
}

# Define the planning stage
planning() {
  echo "AGENT: Planning the implementation..."
  echo "AGENT: Now that I understand the requirements, I will create a plan."
  echo "AGENT: Creating several options..."
  sleep 2
  echo "AGENT: 3 options generated."
  echo "AGENT: Evaluating pros and cons of option 1..."
  sleep 2
  echo "AGENT: Evaluating pros and cons of option 2..."
  sleep 2
  echo "AGENT: Evaluating pros and cons of option 3..."
  sleep 2
  echo "AGENT: Choosing the best option..."
  sleep 1
  echo "AGENT: Detailing the chosen option..."
  sleep 1
  echo "AGENT: Validating the detailed plan..."
  sleep 1
  echo "AGENT: I have created a plan."
}

# Define the implementing stage
implementing() {
  echo "AGENT: Implementing the solution..."
  echo "AGENT: The plan is ready, I will start coding now."
  for i in {1..3}; do
    echo "AGENT: Coding iteration $i..."
    sleep 2
    echo "AGENT: Running tests..."
    sleep 1
    echo "AGENT: Refactoring code..."
    sleep 1
  done
  echo "AGENT: Reviewing the security aspects..."
  sleep 1
  echo "AGENT: Reviewing the performance aspects..."
  sleep 1
  echo "AGENT: Running integration tests..."
  sleep 3
  echo "AGENT: I have implemented the solution."
}

# Define the deploying stage
deploying() {
  echo "AGENT: Deploying the application..."
  echo "AGENT: Creating ephemeral environment..."
  sleep 2
  echo "AGENT: The code is ready, I will deploy it now."
  sleep 1
  echo "AGENT: Running readiness probe..."
  sleep 1
  echo "AGENT: I have deployed the application."
}

# Define the verifying stage
verifying() {
  echo "AGENT: Verifying the deployment..."
  echo "AGENT: The deployment is done, I will verify it now."
  echo "AGENT: Running smoke tests..."
  sleep 1
  echo "AGENT: Running full e2e test suite..."
  sleep 5
  echo "AGENT: Requesting code review from reviewer..."
  sleep 1
  echo "AGENT: Taking screenshots..."
  sleep 1
  echo "AGENT: Creating QA report..."
  sleep 1
  echo "AGENT: Creating PR..."
  sleep 1
  echo "AGENT: Requesting QA review from QA team..."
  sleep 1
  echo "AGENT: Requesting UAT from product team..."
}


# Execute the pipeline stages
for stage in "${stages[@]}"; do
  echo
  echo "AGENT: ============ Starting stage: $stage ================"
  $stage
  echo "AGENT: ============ Finished stage: $stage ================"
done
