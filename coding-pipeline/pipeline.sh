#!/bin/bash
exec 2>&1

# This script runs the coding pipeline for a given task (user story)
# It takes the information about the user story as a set of environment variables:
#   TASK_ID - The ID of the task to work on
#   TASK_DESCRIPTION - The description of the task
#   GIT_REPO_URL - The URL of the git repository
#   GIT_TOKEN - The git access token (optional)
#   GIT_USERNAME - The git username (optional)
#   GH_TOKEN - GitHub token for Copilot CLI authentication (required)
#   GH_USERNAME - GitHub username for Copilot CLI authentication (required)

# Verify GH_TOKEN and GH_USERNAME are set before proceeding
if [ -z "$GH_TOKEN" ]; then
  echo "ERROR: GH_TOKEN is required for GitHub Copilot CLI authentication"
  exit 1
fi
if [ -z "$GH_USERNAME" ]; then
  echo "ERROR: GH_USERNAME is required for GitHub Copilot CLI authentication"
  exit 1
fi

# Inject credentials into copilot config
sed -i "s|\${GH_USERNAME}|${GH_USERNAME}|g; s|\${GH_TOKEN}|${GH_TOKEN}|g" /root/.copilot/config.json

# Define the pipeline stages
stages=("cloning" "refining" "planning" "implementing" "deploying" "verifying")

# Define the cloning stage
cloning() {
  echo "AGENT: Cloning the repository from ${GIT_REPO_URL}"
  cd /workspace
  # Clone the repository using the provided credentials (if any)
  if [ -n "$GIT_USERNAME" ] && [ -n "$GIT_TOKEN" ]; then
    TRUNCATED_TOKEN="****${GIT_TOKEN: -4}"
    echo "AGENT: Using GIT_USERNAME=${GIT_USERNAME} and GIT_TOKEN=${TRUNCATED_TOKEN}"
    # Use sed to inject username and token into the URL
    CLONE_URL=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_USERNAME}:${GIT_TOKEN}@|")
    git clone "$CLONE_URL" .
  else
    git clone "$GIT_REPO_URL" .
  fi
  echo "AGENT: Repository cloned successfully."
  ls -la
}

# Common copilot flags for non-interactive pipeline use
COPILOT_FLAGS="--yolo --no-ask-user --add-dir /workspace --model gpt-4.1"

# Define the refining stage
refining() {
  echo "AGENT: Refining requirements using GitHub Copilot..."
  cd /workspace
  copilot -p "Analyze the following task requirements and identify any ambiguities, edge cases, or missing details. Provide a refined specification ready for implementation. Task ID: $TASK_ID. Task: $TASK_DESCRIPTION" \
    $COPILOT_FLAGS
}

# Define the planning stage
planning() {
  echo "AGENT: Planning the implementation using GitHub Copilot..."
  cd /workspace
  copilot -p "Based on the repository codebase, create a detailed step-by-step implementation plan for the following task. Identify which files to modify, functions to add or change, and the testing approach. Task: $TASK_DESCRIPTION" \
    $COPILOT_FLAGS
}

# Define the implementing stage
implementing() {
  echo "AGENT: Implementing the solution using GitHub Copilot..."
  cd /workspace
  copilot -p "Implement the following task in the repository at /workspace. Make all necessary code changes, run tests to verify correctness, and ensure the implementation is complete. Task: $TASK_DESCRIPTION" \
    $COPILOT_FLAGS
}

# Define the deploying stage
deploying() {
  echo "AGENT: Preparing deployment summary using GitHub Copilot..."
  cd /workspace
  copilot -p "Review the implemented changes in the repository and prepare a deployment summary. List all changed files, describe what was changed and why, and provide any deployment instructions or configuration changes needed. Task: $TASK_DESCRIPTION" \
    $COPILOT_FLAGS
}

# Define the verifying stage
verifying() {
  echo "AGENT: Verifying the implementation using GitHub Copilot..."
  cd /workspace
  copilot -p "Verify the implementation of the following task. Run any available tests, check code quality, review edge cases, and produce a verification report with a pass/fail status and findings. Task: $TASK_DESCRIPTION" \
    $COPILOT_FLAGS
}


# Execute the pipeline stages
for stage in "${stages[@]}"; do
  echo
  echo "AGENT: ============ Starting stage: $stage ================"
  $stage
  echo "AGENT: ============ Finished stage: $stage ================"
done
