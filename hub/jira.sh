#!/bin/bash

# Show usage if no arguments or --help is provided
show_usage() {
    echo "Usage: $0 [--site <site>] <subcommand>"
    echo "  --site <site>    Override the JIRA_SITE environment variable."
    echo "  --help           Show this help message."
    echo "  project          List all Jira projects."
    exit 0
}

if [[ $# -eq 0 ]]; then
    show_usage
fi


# Parse options and capture subcommand
SUBCOMMAND=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --site)
            JIRA_SITE="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        project|projects)
            SUBCOMMAND="$1"
            shift
            ;;
        *)
            # Ignore unknown options, but keep for subcommand
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

echo "Jira CLI configured successfully."
