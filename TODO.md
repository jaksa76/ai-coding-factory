# TODO

## Decisions

- [ ] Choose implementation language for the CLI tools (bash+curl / Node.js / Python / Go)

## `jira` — Jira CLI tool

- [ ] Scaffold `jira/` project with a working entry point and help output
- [ ] Implement `jira issues --project <key>` — list unassigned To Do issues
- [ ] Implement `jira get <issue-key>` — fetch a single issue (id, summary, description, assignee)
- [ ] Implement `jira assign <issue-key> --account-id <id>` — assign issue to an account
- [ ] Implement `jira transition <issue-key> --to <status>` — change issue status
- [ ] Implement `jira comment <issue-key> --body <text>` — post a comment
- [ ] Test each `jira` subcommand manually against a real Jira project

## `loop` — Agent-agnostic work loop

- [ ] Scaffold `loop/` project with a working entry point and help output
- [ ] Implement claim step: assign issue, wait 10 s, re-fetch and verify assignee
- [ ] Implement git step: clone repo if not present, otherwise pull latest
- [ ] Implement agent invocation: run `--agent <cmd>` with issue title + description as input
- [ ] Implement write-back: commit + push, then post Jira comment + transition to Done
- [ ] Wire the full loop and test end-to-end using `echo` as the agent
- [ ] Test `loop` with a real Jira ticket and the `echo` agent, verify Jira state transitions correctly

## `workers/claude` — First real worker

- [ ] Write `workers/claude/Dockerfile` installing Claude CLI + `loop` + `jira`
- [ ] Test the image locally: `docker run` against a real Jira ticket, verify it completes

## `manager` — Worker pool CLI

- [ ] Scaffold `manager/` project with a working entry point and help output
- [ ] Implement `manager start --image <img> --count <n>` — launch worker containers
- [ ] Implement `manager stop <worker-id>` and `manager stop --all`
- [ ] Implement `manager status` — list running workers and their current Jira ticket
- [ ] Implement `manager logs <worker-id>` — tail container logs
- [ ] Test full cycle: start workers via `manager`, watch them process tickets, stop them

## Additional workers

- [ ] Write `workers/copilot/Dockerfile` and test end-to-end
- [ ] Write `workers/codex/Dockerfile` and test end-to-end

## `worker-builder` — Project-specific image builder

- [ ] Scaffold `worker-builder/` project with a working entry point and help output
- [ ] Implement devcontainer.json parsing (extract base image and setup commands)
- [ ] Implement Dockerfile generation layering agent + `loop` + `jira` on the devcontainer base
- [ ] Implement `worker-builder build --devcontainer <path> --type <agent> --tag <tag>`
- [ ] Test: build an image from a sample devcontainer, run it, verify it picks up a Jira ticket
