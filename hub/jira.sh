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
        --help)
            show_usage
            ;;
        projects|stories|view)
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


# Subcommands

if [[ "$SUBCOMMAND" == "projects" || "$SUBCOMMAND" == "project" ]]; then
    acli jira project list --json --paginate | jq -r '.[] | .key'
    exit $?
fi

if [[ "$SUBCOMMAND" == "stories" ]]; then
    if [[ -z "$PROJECT_KEY" ]]; then
        echo "Error: --project <key> is required for stories subcommand."
        exit 1
    fi
    acli jira workitem search --jql "project=$PROJECT_KEY" --json --paginate | jq -r '.[] | .key'
    exit $?
fi

if [[ "$SUBCOMMAND" == "view" ]]; then
    if [[ -z "$STORY_ID" ]]; then
        echo "Error: --story <id> is required for view subcommand."
        exit 1
    fi
    STORY_JSON=$(acli jira workitem view "$STORY_ID" --json)
    # Output in custom format: {id, description, status}
    echo "$STORY_JSON" | jq -r '{id: .key, description: .fields.summary, status: .fields.status.name}'
    exit $?
fi

