#!/bin/bash


# Show usage information
show_usage() {
    echo "Usage: $0 [--site <site>] <subcommand> [options]"
    echo "  --site <site>           Override the JIRA_SITE environment variable."
    echo "  --help                  Show this help message."
    echo "  projects                List all Jira projects."
    echo "  stories --project <key> List all Jira workitems for the specified project."
    echo "  view --story <id>       View a Jira story as JSON (id, description, status)."
    echo "  import --project <key> --dir <data_dir>  Import all stories for a project to a directory."
    exit 0
}

# Print error and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

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
            error_exit "Unknown option or subcommand: $1"
            ;;
    esac
done


# Authenticate only if not already logged in
if ! acli jira auth status | grep -q "Authenticated"; then
    # Check required environment variables
    [[ -z "${JIRA_TOKEN}" ]] && error_exit "JIRA_TOKEN environment variable is not set."
    [[ -z "${JIRA_EMAIL}" ]] && error_exit "JIRA_EMAIL environment variable is not set."
    [[ -z "${JIRA_SITE}" ]] && error_exit "JIRA_SITE environment variable is not set and --site not provided."
    echo "$JIRA_TOKEN" | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token
fi


# List all Jira projects
list_projects() {
    acli jira project list --json --paginate | jq -r '.[] | .key'
}

# List all stories for a project
list_stories() {
    local project_key="$1"
    acli jira workitem search --jql "project=$project_key" --json --paginate | jq -r '.[] | .key'
}

# View a story as JSON
view_story() {
    local story_id="$1"
    local story_json
    story_json=$(acli jira workitem view "$story_id" --json)
    echo "$story_json" | jq -r '{id: .key, description: .fields.summary, status: .fields.status.name}'
}

# Import all stories for a project to a directory
import_stories() {
    local project_key="$1"
    local data_dir="$2"
    mkdir -p "$data_dir"
    local story_keys
    mapfile -t story_keys < <(list_stories "$project_key")
    for key in "${story_keys[@]}"; do
        local story_json
        story_json=$(view_story "$key")
        echo "$story_json" > "$data_dir/${key}.json"
        echo "Imported $key to $data_dir/${key}.json"
    done
}


# Subcommand dispatcher
case "$SUBCOMMAND" in
    projects)
        list_projects
        exit $?
        ;;
    stories)
        [[ -z "$PROJECT_KEY" ]] && error_exit "--project <key> is required for stories subcommand."
        list_stories "$PROJECT_KEY"
        exit $?
        ;;
    view)
        [[ -z "$STORY_ID" ]] && error_exit "--story <id> is required for view subcommand."
        view_story "$STORY_ID"
        exit $?
        ;;
    import)
        [[ -z "$PROJECT_KEY" || -z "$IMPORT_DIR" ]] && error_exit "--project <project_id> and --dir <data_dir> are required for import subcommand."
        import_stories "$PROJECT_KEY" "$IMPORT_DIR"
        exit $?
        ;;
    *)
        show_usage
        ;;
esac

