# Plan: ACF-48 — Create a wrapper for agents

## Goal

Replace the agent-specific CLI flags hard-coded in Dockerfile ENTRYPOINTs and
the `--agent` parameter in `loop` with a standardised `agent` wrapper script
in each worker. `loop` becomes truly agent-agnostic by always calling
`agent run <prompt>`, while each worker exposes:

- `agent init` — one-time initialisation (auth / credential setup)
- `agent run <prompt>` — invoke the underlying AI agent in batch mode with all
  permissions allowed

## Motivation

Currently the agent command is assembled in two places:

1. The Dockerfile ENTRYPOINT embeds the raw CLI flags:
   `--agent 'claude --dangerously-skip-permissions -p'`
2. `loop` accepts and stores this string in `$AGENT_CMD`.

Adding a new worker means knowing which flags to pass, and any flag change
requires touching the Dockerfile _and_ re-reading the loop source. A thin
`agent` wrapper centralises this knowledge inside the worker image.

## Interface

New script per worker: `workers/<type>/agent`

### Subcommands

```
agent init
    One-time initialisation. Sets up credentials / config for the underlying
    agent CLI. Equivalent to the existing init-claude / init-copilot scripts.
    Idempotent; safe to call on every container start.

agent run <prompt>
    Execute <prompt> in non-interactive (batch) mode with all tool permissions
    granted. The full prompt is passed as a single argument.
    Exit code mirrors the underlying agent's exit code.
```

Any other subcommand or missing subcommand prints usage and exits non-zero.

## Files to create

### `workers/claude/agent`

Bash script. Dispatches on `$1`:

- `init`: contains the logic currently in `init-claude.sh` (write OAuth
  credentials or no-op when `ANTHROPIC_API_KEY` is set).
- `run`: executes `claude --dangerously-skip-permissions -p "$2"`.
- default: prints usage, exits 1.

Must be executable (`chmod +x`).

### `workers/claude/agent.bats`

Unit tests for the claude `agent` script. Key cases:

- `agent init` with `ANTHROPIC_API_KEY` set: no credentials file written,
  exits 0.
- `agent init` with OAuth vars set: credentials file written, exits 0.
- `agent init` missing required OAuth var: exits 1 with error message.
- `agent run "hello"`: invokes `claude` with the correct flags and prompt.
- `agent` with no subcommand: exits 1 with usage message.
- `agent` with unknown subcommand: exits 1 with usage message.

### `workers/copilot/agent`

Bash script. Dispatches on `$1`:

- `init`: contains the logic currently in `init-copilot.sh` (substitute
  `GH_TOKEN` / `GH_USERNAME` into the config file).
- `run`: executes `copilot --allow-all --no-ask-user -p "$2"`.
- default: prints usage, exits 1.

Must be executable.

### `workers/copilot/agent.bats`

Unit tests for the copilot `agent` script. Key cases:

- `agent init` with `GH_TOKEN` and `GH_USERNAME` set: config file updated,
  exits 0.
- `agent init` missing `GH_TOKEN`: exits 1 with error message.
- `agent init` missing `GH_USERNAME`: exits 1 with error message.
- `agent run "hello"`: invokes `copilot` with the correct flags and prompt.
- `agent` with no subcommand: exits 1.
- `agent` with unknown subcommand: exits 1.

## Files to modify

### `loop/loop`

- Remove the `--agent <command>` CLI parameter and all related parsing /
  validation.
- Replace `$AGENT_CMD "$prompt"` with `agent run "$prompt"` everywhere
  (currently one call site inside `run_agent_with_retry`).
- Update the usage string to remove the `--agent` reference.
- The `--for-planning` flag (introduced by the planner-loop merge) is retained
  as-is.

The `agent` binary is expected to be on `PATH`; the worker Dockerfile ensures
this. Tests stub it by name.

### `loop/loop.bats`

- Remove `--agent agent` from every `run "$LOOP" …` invocation.
- The `stub agent ""` in `setup()` remains unchanged — the stub is now invoked
  as `agent run <prompt>` but still exits 0 and produces no output, which is
  all loop needs.
- Tests that capture agent output (`stub_script agent "echo …"`) continue to
  work; the logged string will now include the `run` prefix before the prompt,
  so adjust any assertions that check exact args if needed.
- Tests for `--agent` validation (missing flag error) are removed.

### `workers/claude/Dockerfile`

- Add `COPY workers/claude/agent /usr/local/bin/agent` and `chmod +x`.
- Update ENTRYPOINT: replace `init-claude && exec loop --project … --agent
  'claude --dangerously-skip-permissions -p'` with
  `agent init && exec loop --project "$JIRA_PROJECT"`.
- Keep `init-claude.sh` installed for backwards compatibility but it is no
  longer called by the ENTRYPOINT.

  > **Alternative**: remove `init-claude.sh` entirely since its logic is now
  > inside `agent init`. Preferred — less dead code. Remove the COPY line and
  > chmod for `init-claude` from the Dockerfile.

### `workers/copilot/Dockerfile`

- Add `COPY workers/copilot/agent /usr/local/bin/agent` and `chmod +x`.
- Update ENTRYPOINT analogously: `agent init && exec loop --project
  "$JIRA_PROJECT"`.
- Remove the COPY / chmod for `init-copilot`.

### `planner/Dockerfile`

- Add `COPY workers/claude/agent /usr/local/bin/agent` and `chmod +x`.
- Update ENTRYPOINT: replace `init-claude && exec loop --for-planning --project
  "$JIRA_PROJECT" --agent 'claude --dangerously-skip-permissions -p'` with
  `agent init && exec loop --for-planning --project "$JIRA_PROJECT"`.
- Remove the COPY / chmod for `init-claude`.

## Test strategy

### New: `workers/claude/agent.bats` and `workers/copilot/agent.bats`

Each test file stubs the underlying CLI (`claude` / `copilot`) to verify that:

- the correct flags are forwarded by `agent run`
- `agent init` writes or skips credentials as expected
- error cases produce the right exit codes and messages

### Existing: `loop/loop.bats`

After removing `--agent`, the stubs stay the same. Tests verify that `loop`
correctly invokes the `agent` stub (now as `agent run <prompt>`). All
assertions on prompt content remain valid; only assertion lines that check the
literal argument list including the old CLI flags need updating.

## Implementation steps

1. Create `workers/claude/agent` (absorbing `init-claude.sh` logic) and make
   it executable.
2. Create `workers/claude/agent.bats`.
3. Create `workers/copilot/agent` (absorbing `init-copilot.sh` logic) and make
   it executable.
4. Create `workers/copilot/agent.bats`.
5. Update `loop/loop`: remove `--agent`, call `agent run "$prompt"` directly.
6. Update `loop/loop.bats`: remove `--agent agent` from invocations, remove
   `--agent` validation tests.
7. Update `workers/claude/Dockerfile`: install `agent`, update ENTRYPOINT,
   remove `init-claude` install.
8. Update `workers/copilot/Dockerfile`: install `agent`, update ENTRYPOINT,
   remove `init-copilot` install.
8a. Update `planner/Dockerfile`: install `workers/claude/agent`, update
    ENTRYPOINT to `agent init && exec loop --for-planning --project "$JIRA_PROJECT"`,
    remove `init-claude` install.
9. Delete `workers/claude/init-claude.sh`, `workers/claude/init-claude.bats`,
   `workers/copilot/init-copilot.sh` (logic is now in `agent`).
10. Run all bats test suites to confirm no regressions.
