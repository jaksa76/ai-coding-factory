#!/bin/bash

# Show usage if no arguments or --help is provided
show_usage() {
    echo "Usage: $0 [--site <site>] <subcommand> [options]"
    echo "  --site <site>           Override the JIRA_SITE environment variable."
    echo "  --help                  Show this help message."
    echo "  projects                List all Jira projects."
    echo "  stories --project <key> List all Jira workitems for the specified project."
    echo "  view --story <id>       View a Jira story as JSON (id, description, status)."
    exit 0
}

if [[ $# -eq 0 ]]; then
    show_usage
fi


# Parse options and capture subcommand and project key
SUBCOMMAND=""
PROJECT_KEY=""
STORY_ID=""
IMPORT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --site)
            JIRA_SITE="$2"
            shift 2
            ;;
        --project)
            PROJECT_KEY="$2"
            shift 2
            ;;
        --story)
            STORY_ID="$2"
            shift 2
            ;;
        --dir)
            IMPORT_DIR="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        projects|stories|view|import)
            SUBCOMMAND="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "${JIRA_TOKEN}" ]]; then
    echo "Error: JIRA_TOKEN environment variable is not set."
    exit 1
fi

if [[ -z "${JIRA_EMAIL}" ]]; then
    echo "Error: JIRA_EMAIL environment variable is not set."
    exit 1
fi

if [[ -z "${JIRA_SITE}" ]]; then
    echo "Error: JIRA_SITE environment variable is not set and --site not provided."
    exit 1
fi


# Authenticate only if not already logged in
if ! acli jira auth status | grep -q "Authenticated"; then
    echo $JIRA_TOKEN | acli jira auth login --site "${JIRA_SITE}" --email "${JIRA_EMAIL}" --token
fi



# Functions for subcommands
list_projects() {
    acli jira project list --json --paginate | jq -r '.[] | .key'
}

list_stories() {
    local project_key="$1"
    acli jira workitem search --jql "project=$project_key" --json --paginate | jq -r '.[] | .key'
}

view_story() {
    local story_id="$1"
    STORY_JSON=$(acli jira workitem view "$story_id" --json)
    echo "$STORY_JSON" | jq -r '{id: .key, description: .fields.summary, status: .fields.status.name}'
}

import_stories() {
    local project_key="$1"
    local data_dir="$2"
    mkdir -p "$data_dir"
    # Get all story keys
    story_keys=( $(list_stories "$project_key") )
    for key in "${story_keys[@]}"; do
        STORY_JSON=$(view_story "$key")
        echo "$STORY_JSON" > "$data_dir/${key}.json"
        echo "Imported $key to $data_dir/${key}.json"
    done
}

# Subcommand dispatcher
if [[ "$SUBCOMMAND" == "projects" || "$SUBCOMMAND" == "project" ]]; then
    list_projects
    exit $?
fi

if [[ "$SUBCOMMAND" == "stories" ]]; then
    if [[ -z "$PROJECT_KEY" ]]; then
        echo "Error: --project <key> is required for stories subcommand."
        exit 1
    fi
    list_stories "$PROJECT_KEY"
    exit $?
fi

if [[ "$SUBCOMMAND" == "view" ]]; then
    if [[ -z "$STORY_ID" ]]; then
        echo "Error: --story <id> is required for view subcommand."
        exit 1
    fi
    view_story "$STORY_ID"
    exit $?
fi

# Import subcommand
if [[ "$SUBCOMMAND" == "import" ]]; then
    if [[ -z "$PROJECT_KEY" || -z "$IMPORT_DIR" ]]; then
        echo "Error: --project <project_id> and --dir <data_dir> are required for import subcommand."
        exit 1
    fi
    import_stories "$PROJECT_KEY" "$IMPORT_DIR"
    exit $?
fi

