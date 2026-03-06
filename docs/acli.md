# acli — Atlassian CLI Usage Guide

`acli` is the Atlassian command-line tool used throughout this project for Jira interactions (authenticating, searching, viewing, assigning, transitioning, and commenting on work items).

## Installation / version

```sh
acli --version
```

## Top-level commands

```
acli [command]

Commands:
  auth        Authenticate to use Atlassian CLI.
  confluence  Confluence Cloud commands.
  jira        Jira Cloud commands.
  rovodev     Atlassian's AI coding agent: Rovo Dev (Beta).
  config      Commands for changing configuration settings.
  completion  Generate the autocompletion script for the specified shell.
  feedback    Submit a request or report a problem.
  help        Help about any command.
```

---

## Authentication — `acli jira auth`

### Check login status

```sh
acli jira auth status
```

Returns `unauthorized` if not logged in.

### Log in with API token

```sh
echo "$JIRA_TOKEN" | acli jira auth login \
    --site "$JIRA_SITE" \
    --email "$JIRA_EMAIL" \
    --token
```

| Flag | Description |
|---|---|
| `--site` | Jira host, e.g. `mycompany.atlassian.net` |
| `--email` | Account email |
| `--token` | Read token from stdin |
| `--web` | Authenticate interactively via browser |

### Log out / switch accounts

```sh
acli jira auth logout
acli jira auth switch
```

---

## Work items — `acli jira workitem`

The canonical subcommand for all issue/ticket operations is `acli jira workitem`.  
**There is no `acli jira issue` command** — avoid it.

### View a work item

```sh
acli jira workitem view KEY-123 --json
```

Retrieve specific fields only:

```sh
acli jira workitem view KEY-123 --fields labels --json
acli jira workitem view KEY-123 --fields summary,description --json
```

| Flag | Description |
|---|---|
| `--json` | Output as JSON |
| `--fields` | Comma-separated list of fields to return (default: `key,issuetype,summary,status,assignee,description`) |
| `--web` | Open in browser |

### Search with JQL

```sh
acli jira workitem search --jql "project = MYPROJ AND status = 'To Do'" --json --paginate
```

| Flag | Description |
|---|---|
| `--jql` | JQL query string |
| `--json` | Output as JSON array |
| `--paginate` | Fetch all results (not just the first page) |
| `--limit` | Maximum number of results |
| `--fields` | Fields to include in output |
| `--csv` | CSV output |

### Assign a work item

```sh
acli jira workitem assign --key "KEY-123" --assignee "user@example.com" --yes
acli jira workitem assign --key "KEY-123" --assignee "@me" --yes
```

| Flag | Description |
|---|---|
| `--key` | Work item key(s), comma-separated |
| `--assignee` | Email, account ID, `@me`, or `default` |
| `--yes` | Skip confirmation prompt |

### Transition a work item

```sh
acli jira workitem transition --key "KEY-123" --status "In Progress" --yes
acli jira workitem transition --key "KEY-123" --status "Done" --yes
acli jira workitem transition --jql "project = MYPROJ" --status "In Review" --yes
```

| Flag | Description |
|---|---|
| `--key` | Work item key(s), comma-separated |
| `--jql` | JQL query to select work items |
| `--status` | Target status name |
| `--yes` | Skip confirmation prompt |
| `--json` | JSON output |
| `--ignore-errors` | Continue if some transitions fail |

### Comment on a work item

```sh
acli jira workitem comment create --key "KEY-123" --body "Pull request opened: https://..."
```

