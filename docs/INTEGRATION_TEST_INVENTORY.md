# Integration Test Inventory

This document lists every test in files ending with integration.bats and states exactly what is mocked in each test.

## factory/factory-integration.bats

- status: no workers running initially
  - Mocked: none.
  - Notes: uses real Docker CLI/daemon.
- full cycle: add workers, status shows them, stop them
  - Mocked: none.
  - Notes: uses real Docker and real busybox container lifecycle.
- add: worker containers are labelled correctly
  - Mocked: none.
  - Notes: uses real Docker labels.
- logs: streams output from a running worker
  - Mocked: none.
  - Notes: reads real container logs.
- stop: stops a specific worker by name
  - Mocked: none.
  - Notes: uses real Docker stop/remove behavior.
- stop --all: with no workers prints informational message
  - Mocked: none.

## loop/loop-integration.bats

Tests:
- planning loop with gh task management using copilot (default planning)
  - Mocked: none.
  - Real dependencies used: GitHub API via gh, real Copilot CLI, real task-manager github backend logic, git.
- implementation loop with gh task management using claude (no feature branches)
  - Mocked: none.
  - Real dependencies used: GitHub API via gh, real Claude CLI, real task-manager github backend logic, git.
- planning loop with jira task management using claude (needs-plan label)
  - Mocked: none.
  - Real dependencies used: Jira API via acli, real Claude CLI, real task-manager jira backend logic, git.
- implementation loop with jira task management using copilot (feature branches)
  - Mocked: none.
  - Real dependencies used: Jira API via acli, real Copilot CLI, GitHub CLI for PR flow, real task-manager jira backend logic, git.

## worker-builder/worker-builder-integration.bats

- builds a real worker image with loop, task-manager, and claude installed
  - Mocked: none.
  - Notes: real docker build and real container execution.

## task-manager/task-manager-integration.bats

- auth: acli reports authenticated with provided credentials
  - Mocked: none.
  - Notes: real acli auth status/login against Jira.
- P1: --for-planning, PLAN_BY_DEFAULT=false, no label - issue NOT claimed
  - Mocked: none.
  - Notes: real Jira issue creation/query and claim attempt.
- P2: --for-planning, PLAN_BY_DEFAULT=false, needs-plan label - claimed + Planning
  - Mocked: none.
- P3: --for-planning, PLAN_BY_DEFAULT=false, skip-plan label - issue NOT claimed
  - Mocked: none.
- P4: --for-planning, PLAN_BY_DEFAULT=true, no label - claimed + Planning
  - Mocked: none.
- P5: --for-planning, PLAN_BY_DEFAULT=true, skip-plan label - issue NOT claimed
  - Mocked: none.
- I1: no --for-planning, PLAN_BY_DEFAULT=false, no label - claimed + In Progress
  - Mocked: none.
- I2: no --for-planning, PLAN_BY_DEFAULT=false, needs-plan label - issue NOT claimed
  - Mocked: none.
- I3: no --for-planning, PLAN_BY_DEFAULT=false, skip-plan label - claimed + In Progress
  - Mocked: none.
- I4: no --for-planning, PLAN_BY_DEFAULT=true, no label - issue NOT claimed
  - Mocked: none.
- I5: no --for-planning, PLAN_BY_DEFAULT=true, skip-plan label - claimed + In Progress
  - Mocked: none.
- I6: no --for-planning, PLAN_BY_DEFAULT=true, Plan Approved status - claimed + In Progress
  - Mocked: none.

## planner/planner-integration.bats

- image has claude installed
  - Mocked: none.
- image has agent installed
  - Mocked: none.
- image has loop installed
  - Mocked: none.
- image has plan installed
  - Mocked: none.
- image has git-utils.sh installed
  - Mocked: none.
- image has task-manager installed
  - Mocked: none.
- image has task-manager backends installed
  - Mocked: none.
- image has acli installed
  - Mocked: none.
- image has jq installed
  - Mocked: none.
- image has git installed
  - Mocked: none.
- ~/.claude directory exists and is writable
  - Mocked: none.
- entrypoint uses bash
  - Mocked: none.
- entrypoint invokes agent init and loop --for-planning
  - Mocked: none.
- loop --help prints usage
  - Mocked: none.
- loop requires --project flag
  - Mocked: none.

## workers/claude/claude-integration.bats

- claude is installed
  - Mocked: none.
- agent is installed
  - Mocked: none.
- image has loop installed
  - Mocked: none.
- image has task-manager installed
  - Mocked: none.
- image has implement installed
  - Mocked: none.
- image has plan installed
  - Mocked: none.
- image has git-utils.sh installed
  - Mocked: none.
- image has task-manager backends installed
  - Mocked: none.
- image has acli installed
  - Mocked: none.
- image has gh installed
  - Mocked: none.
- image has jq installed
  - Mocked: none.
- image has git installed
  - Mocked: none.
- ~/.claude directory exists and is writable
  - Mocked: none.
- entrypoint uses bash
  - Mocked: none.
- entrypoint invokes agent init and loop
  - Mocked: none.
- loop --help prints usage (overrides ENTRYPOINT)
  - Mocked: none.
- loop requires --project flag
  - Mocked: none.
- loop requires JIRA_SITE env var
  - Mocked: none.
- agent init writes valid credentials JSON
  - Mocked: none.
  - Notes: reads real credentials from env file and validates generated JSON.
- agent run passes prompt to claude and returns output
  - Mocked: claude binary is replaced inside container with /tmp/mock-bin/claude that prints HELLO.
- claude responds to a real prompt (live API smoke test)
  - Mocked: none.
  - Notes: real Claude API call.

## workers/copilot/copilot-integration.bats

- image has gh installed
  - Mocked: none.
- @github/copilot npm package is installed
  - Mocked: none.
- copilot wrapper is executable
  - Mocked: none.
- agent is installed
  - Mocked: none.
- copilot config template is present with placeholders
  - Mocked: none.
- image has loop installed
  - Mocked: none.
- image has task-manager installed
  - Mocked: none.
- image has implement installed
  - Mocked: none.
- image has plan installed
  - Mocked: none.
- image has git-utils.sh installed
  - Mocked: none.
- image has task-manager backends installed
  - Mocked: none.
- image has acli installed
  - Mocked: none.
- image has jq installed
  - Mocked: none.
- image has git installed
  - Mocked: none.
- entrypoint uses bash
  - Mocked: none.
- entrypoint invokes agent init and loop
  - Mocked: none.
- loop --help prints usage (overrides ENTRYPOINT)
  - Mocked: none.
- loop requires --project flag
  - Mocked: none.
- loop requires JIRA_SITE env var
  - Mocked: none.
- agent init injects credentials into config
  - Mocked: none.
  - Notes: uses env file and checks placeholder replacement.
- agent run passes prompt to copilot and returns output
  - Mocked: copilot binary is replaced inside container with /tmp/mock-bin/copilot that prints HELLO.
- copilot responds to a real prompt (live API smoke test)
  - Mocked: none.
  - Notes: real Copilot API call.

## Summary

- Total integration test files: 7
- Total integration tests: 81
- Tests with explicit runtime command stubbing/mocking: 2
  - workers/claude/claude-integration.bats: 1 test stubs claude binary in container.
  - workers/copilot/copilot-integration.bats: 1 test stubs copilot binary in container.
- Tests with no mocks (real dependencies): 79
