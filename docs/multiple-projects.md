# Factory as Orchestrator: Problem Analysis

## Context

Each project has its own devcontainer → separate worker containers per project are unavoidable.
The factory needs to evolve from a thin `docker run` wrapper into a scheduler/orchestrator that:

1. Manages a **pool of Claude/Copilot accounts**, distributing workers across them to stay within rate limits
2. Enforces a **maximum concurrent worker count** (memory/resource cap)
3. Uses a **config file** (factory.json) as the project registry
4. Implements **scheduling algorithms** to decide which project gets the next available worker slot

---

## The Unifying Solution: Account Pooling

The rate limit problem (concurrent sessions, tokens/min, API 429s) is best addressed not by
coordinating between containers but by treating Claude credentials as a **pool**:

- Each Claude account has its own rate limit envelope
- The factory assigns each worker a specific account when it starts
- No more than `max_workers_per_account` workers share any single account
- Total capacity = (number of accounts) × (max workers per account)

This avoids any need for inter-container coordination (shared files, token buckets, proxies).
Workers remain completely independent; the factory controls which credentials they get.

---

## Problems to Solve

### 1. Config File Schema (factory.json)

The factory needs two registries: projects and accounts.

```json
{
  "max_workers": 10,
  "scheduling": "round-robin",
  "accounts": [
    {
      "id": "account-a",
      "max_workers": 3,
      "env": {
        "ANTHROPIC_API_KEY": "${ACCOUNT_A_KEY}"
      }
    },
    {
      "id": "account-b",
      "max_workers": 3,
      "env": {
        "CLAUDE_ACCESS_TOKEN": "${ACCOUNT_B_ACCESS_TOKEN}",
        "CLAUDE_REFRESH_TOKEN": "${ACCOUNT_B_REFRESH_TOKEN}"
      }
    }
  ],
  "projects": [
    {
      "key": "FOO",
      "image": "worker-claude-foo",
      "priority": 1,
      "env": {
        "JIRA_PROJECT": "FOO",
        "GIT_REPO_URL": "https://github.com/org/foo.git",
        "FEATURE_BRANCHES": "true"
      }
    },
    {
      "key": "BAR",
      "image": "worker-claude-bar",
      "priority": 2,
      "env": {
        "JIRA_PROJECT": "BAR",
        "GIT_REPO_URL": "https://github.com/org/bar.git"
      }
    }
  ]
}
```

Account auth type is flexible: an account entry with `ANTHROPIC_API_KEY` uses API key auth;
one with `CLAUDE_ACCESS_TOKEN` + `CLAUDE_REFRESH_TOKEN` uses OAuth. The factory just merges
whichever env vars are present into the `docker run` call.

Credential values use `${VAR}` substitution — actual secrets come from the factory process's
own environment, not stored in the config file.

### 2. Factory Daemon (scheduler loop)

The factory needs to become a long-running process:

```
factory schedule --config factory.json
```

Core loop:
1. Get running workers from Docker (already works via label filter)
2. For each running worker, check if it is still alive
3. Count workers per account → which accounts have free capacity
4. Count total workers → is total < max_workers?
5. Apply scheduling policy → which project gets next slot?
6. Pick account with most free capacity → assign credentials
7. `docker run -d` the worker with the right image + credentials + env vars
8. Sleep, repeat

### 3. Worker State Tracking

The factory must track:
- Which container is running which project
- Which account each container is using

Docker labels are the right mechanism (already used for `ai-coding-factory.worker=true`):

```
--label ai-coding-factory.project=FOO
--label ai-coding-factory.account=account-a
```

This keeps the factory stateless (no separate state file) — all state is in Docker's labels.

### 4. Scheduling Algorithms

"Which project gets the next available slot?" Starting with round-robin is fine; others can be
added later:

| Algorithm | Description |
|---|---|
| **round-robin** | Cycle through projects in order, one slot each |
| **priority** | Higher-priority projects fill slots first |
| **fair-share** | Cap max running workers per project; prevent monopolization |
| **demand-based** | Query Jira for open issue count; weight slots accordingly |

Round-robin covers the common case. Demand-based requires Jira API calls from the factory (complex).

### 5. Account Assignment Strategy

When starting a new worker, pick the account with the most free capacity:

```
free_slots(account) = max_workers_per_account - running_workers_on_account
pick account with max free_slots (break ties arbitrarily)
```

If all accounts are at capacity → don't start new worker, wait for next loop iteration.

### 6. Worker Lifecycle

Workers stop naturally (Jira project has no more issues), fail, or are stopped manually.
The scheduler loop detects this by comparing running containers to expected state and fills
vacated slots on next iteration. No special lifecycle hooks needed beyond Docker label queries.

### 7. Credential Security

Credentials should not be hardcoded in factory.json. Options:
- **Account credentials as env vars** the factory reads and distributes: `ACCOUNT_A_KEY=...`
- **Secret references** (e.g. Docker secrets, Vault) — more complex, out of scope for now
- Simplest: factory.json holds non-secret config (account IDs, limits); credentials come from env

---

## Resolved Design Decisions

- **Auth type**: factory.json supports both API key and OAuth token accounts; factory passes
  whichever env vars an account entry specifies
- **Per-project config**: factory.json carries all per-project env vars (JIRA_PROJECT, GIT_REPO_URL, etc.)
- **Image building**: factory assumes images are pre-built by worker-builder; no on-demand builds
- **Credentials in config**: `${VAR}` substitution; secrets come from factory's own environment

---

## Critical Files

- `factory/factory` — primary change; add `schedule` subcommand (daemon loop)
- No changes to `loop/`, `claim/`, or worker Dockerfiles (they stay the same)
- New: `factory.json` schema definition (or documented by example)
