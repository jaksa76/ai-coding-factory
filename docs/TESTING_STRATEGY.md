# Testing Strategy

## Framework

All tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Two-tier structure

Each tool has two test files:

| File | Purpose | External calls |
|---|---|---|
| `<tool>.bats` | Unit tests — stub all dependencies | None |
| `<tool>-integration.bats` | Integration tests — hit real APIs | Jira, Git, etc. |

## Unit tests

Dependencies are stubbed by injecting a `STUB_DIR` at the front of `PATH`. Helper functions:

```bash
stub <cmd> [stdout]         # exits 0, prints optional stdout
stub_exit <cmd> <code> [stdout]  # exits with given code
stub_script <cmd> <body>    # full bash script for stateful stubs
```

`setup()` creates a fresh `STUB_DIR` per test; `teardown()` deletes it.
`sleep` is always stubbed to keep unit tests fast.

Unit tests cover:
- Argument validation (missing flags, unknown flags, `--help`)
- Environment variable validation (missing required vars)
- Happy path through the full flow
- Error/edge paths (no issues found, race condition, non-fatal failures)

## Integration tests

Require a `.env` file at the repo root with real credentials:

```
JIRA_SITE=mycompany.atlassian.net
JIRA_EMAIL=me@example.com
JIRA_TOKEN=...
```

`setup_file()` creates a real Jira issue before the suite; `teardown_file()` deletes it.
`sleep` is still stubbed to keep integration tests reasonably fast.

Run integration tests explicitly — they are not part of the default `bats` invocation:

```bash
bats claim/claim-integration.bats
```

## Running tests

```bash
# Unit tests for a tool
bats claim/claim.bats

# Integration tests (requires .env)
bats claim/claim-integration.bats

# All unit tests
bats **/*.bats --exclude '**/*-integration.bats'
```

## Conventions

- Test files live alongside the tool they test (same directory).
- Integration test filenames end in `-integration.bats`.
- Each test asserts both exit code (`[ "$status" -eq 0 ]`) and relevant output fragments.
- JSON output is validated by piping through `jq -e` (non-zero exit on null/false).
- Counter files (`mktemp`) model multi-call stateful stubs when a single stub body is insufficient.
