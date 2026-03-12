# acli — Atlassian CLI Usage Guide

`acli` is the Atlassian command-line tool used throughout this project for Jira interactions (authenticating, searching, viewing, assigning, transitioning, and commenting on work items).

## Help

Always use the `--help` flag before interacting with a new command/subcommand to understand its usage and available options.

```sh
acli help
acli [command] --help
acli [command] [subcommand] --help
acli [command] [subcommand] [subsubcommand] --help
```

## Top-level commands

```
  auth        Authenticate to use Atlassian CLI.
  confluence  Confluence Cloud commands.
  jira        Jira Cloud commands.
  rovodev     Atlassian's AI coding agent: Rovo Dev (Beta).
  config      Commands for changing configuration settings.
  completion  Generate the autocompletion script for the specified shell.
  feedback    Submit a request or report a problem.
  help        Help about any command.
```

### Jira commands

```
  auth        Authenticate to use Atlassian CLI.
  board       Jira board commands.
  dashboard   Jira dashboard commands.
  field       Jira field commands.
  filter      Jira filter commands.
  project     Jira project commands.
  sprint      Jira sprint commands.
  workitem    Jira work item commands.
```

### Workitem subcommands

```
  archive     Archives a work item or multiple work items.
  assign      Assign a work item(s) to an assignee(s).
  attachment  Work item attachments commands.
  clone       Create a duplicate work item(s).
  comment     Work item comments commands.
  create      Create a Jira work item.
  create-bulk Bulk create Jira issues.
  delete      Delete a work item or multiple work items.
  edit        Edit a Jira work item or multiple work items.
  link        Link work items commands.
  search      Searches for work item or multiple work items.
  transition  Transitioning a work item.
  unarchive   Unarchives work item or multiple work items.
  view        Retrieve information about Jira work items.
  watcher     Work item watcher commands.
```

## Examples

```sh
acli jira auth status
echo "$JIRA_TOKEN" | acli jira auth login --site "$JIRA_SITE" --email "$JIRA_EMAIL" --token
acli jira workitem view KEY-123 --json
acli jira workitem view KEY-123 --fields labels --json
acli jira workitem view KEY-123 --fields summary,description --json
acli jira workitem search --jql "project = MYPROJ AND status = 'To Do'" --json --paginate
acli jira workitem assign --key "KEY-123" --assignee "user@example.com" --yes
acli jira workitem transition --key "KEY-123" --status "In Progress" --yes
acli jira workitem transition --key "KEY-123" --status "Done" --yes
acli jira workitem comment create --key "KEY-123" --body "Pull request opened: https://..."
```

## Tips

There is no built in command for listing available transitions. Just try transitioning to the desired status.