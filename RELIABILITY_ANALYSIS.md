# Worker Reliability Analysis

This document analyses the reliability of the AI coding factory worker system and proposes concrete improvements. The system consists of a `claim` script for picking up Jira issues, a `loop` script that orchestrates the claim/work/report cycle, and Docker workers that wrap `loop` with a specific agent CLI.

---

## Summary of Findings

| Severity | Count |
|---|---|
| High | 5 |
| Medium | 6 |
| Low | 3 |

---

## High Severity

### H1: Loop exits permanently on non-rate-limit agent failure

**Problem:** `run_agent_with_retry` only retries when the agent output contains rate-limit keywords. Any other non-zero exit (network blip, OOM, tool crash, authentication error) propagates out of the function, bubbles through `set -euo pipefail`, and terminates the loop permanently. Because the Docker container has no restart policy or supervisor, the worker goes dark silently.

**Impact:** A single transient agent failure halts all future work from that container with no recovery.

**Suggested fix:** Distinguish between retriable failures (all non-zero exits that are not clearly "bad input") and permanent failures. Add a retry-with-backoff for transient errors, or at minimum catch unexpected exits and continue to the next issue rather than exiting the loop entirely.

---

### H2: Orphaned "In Progress" issues when a worker crashes

**Problem:** After `claim` transitions an issue to "In Progress", the worker begins running the agent. If the container crashes or is killed at any point before completing, the issue remains assigned and "In Progress" forever. The JQL in `claim` is:

```
project = "..." AND assignee is EMPTY AND statusCategory != Done
```

This filters only *unassigned* issues, so the orphaned issue is invisible to all future workers.

**Impact:** Issues silently disappear from the queue. Undetected without manual Jira audit.

**Suggested fix:** Either (a) add a periodic sweep that re-queues "In Progress" issues older than a configurable threshold (e.g. 2 hours), or (b) change the claim query to also pick up issues assigned to this worker account that are still "In Progress" with no recent activity.

---

### H3: Concurrent workers pushing to the same branch cause permanent failures

**Problem:** `loop` pushes directly to the default branch (typically `main`). With two or more workers running concurrently on the same repository, the second worker's `git push` will be rejected with "updates were rejected because the remote contains work you do not have locally". Because `set -euo pipefail` is active and there is no retry on push failure, the loop exits.

**Impact:** All workers except the first to push on a given round will crash. In a scaled deployment this effectively limits throughput to one worker.

**Suggested fix:** Create a per-issue feature branch (`git checkout -b $ISSUE_KEY`), push that branch, and open a PR instead of pushing directly to main. This removes the conflict entirely and also enables code review.

---

### H4: Failing unit tests reveal a contract mismatch

**Current state:** Running `bats loop/loop.bats` shows 3 failing tests:

- `happy path: claims issue, clones repo, runs agent, pushes, comments, transitions` — expects the loop to print "Pushing changes", call `git push`, call `acli comment`, and call `acli transition`; none of these happen in the current implementation.
- `comment failure is non-fatal: warning printed, loop continues` — expects loop to post a Jira comment itself.
- `transition failure is non-fatal: warning printed, loop continues` — expects loop to transition the issue itself.

The current `loop` implementation delegates commit, push, Jira comment, and transition entirely to the agent via the prompt. The tests expect these to be steps in the loop script itself.

**Impact:** The system relies on the agent faithfully executing all post-work steps. If the agent skips the push, comment, or transition (which LLMs do sometimes), there is no fallback. Work may be done but never surfaced in Jira, and the issue never transitions to Done.

**Suggested fix:** Move git commit/push, Jira comment, and Jira transition into explicit `loop` steps executed *after* the agent exits. This matches what the tests already describe and makes the loop resilient to agent prompt-following failures. Remove these responsibilities from the agent prompt and let the agent focus only on the code changes.

---

### H5: OAuth tokens expire with no refresh path

**Problem:** `init-claude.sh` writes OAuth credentials to `~/.claude/.credentials.json` at container startup. OAuth access tokens have a finite lifetime. When the token expires, Claude CLI calls start failing. The failure mode (non-zero exit without rate-limit keywords) matches H1 — the loop terminates.

**Impact:** Containers die silently some hours after startup.

**Suggested fix:** Either (a) mount a secret that holds a long-lived API key (`ANTHROPIC_API_KEY`) instead of OAuth tokens, or (b) add a pre-agent step that refreshes the token using the refresh token before each task, writing the updated credentials back to disk. Option (a) is simpler.

---

## Medium Severity

### M1: No container restart policy or supervisor

**Problem:** The Docker `ENTRYPOINT` is a bare `bash -c "init-claude && exec loop ..."`. If the loop exits for any reason, the container stops. There is no `docker run --restart=always` requirement documented, no supervisor process (e.g. `supervisord`, `s6`), and no healthcheck in the Dockerfile.

**Suggested fix:** Add `HEALTHCHECK` to the Dockerfile (e.g. check that the process is still running) and document a mandatory `--restart=unless-stopped` or `--restart=on-failure` flag for `docker run`. The `factory` CLI should enforce this when starting containers.

---

### M2: Hardcoded 20-minute inter-task sleep with no override

**Problem:** After completing each issue, `loop` unconditionally sleeps 1200 seconds:

```bash
sleep 1200 # Sleep for 20 minutes before claiming the next issue
```

Unlike `NO_ISSUES_WAIT` and `RATE_LIMIT_WAIT`, this is not configurable via an environment variable.

**Impact:** Even with a backlog of 100 issues, each worker processes at most ~3 issues per hour. A 10-worker pool that each take 5 minutes per task processes issues at 30/hour in theory, but in practice at most ~1.5/hour.

**Suggested fix:** Expose as `INTER_TASK_WAIT` env var (defaulting to the current 1200 for backwards compatibility) or remove it entirely — it appears to be a rate-limit precaution, which is already handled separately by `RATE_LIMIT_WAIT`.

---

### M3: git push credentials exposed in process list

**Problem:** The authenticated remote URL is built as:

```bash
AUTH_URL="${GIT_REPO_URL/#https:\/\//https://$GIT_USERNAME:$GIT_TOKEN@}"
```

This URL is passed directly to `git clone` and `git remote set-url`, which means `GIT_USERNAME:GIT_TOKEN` appears in the process argument list (`ps aux`) during git operations, visible to any process running as the same user or as root.

**Suggested fix:** Use `git credential.helper store` or set the `GIT_ASKPASS` env var to a helper script. Alternatively, configure `git` with a credentials file or use `git config --global url."https://...@".insteadOf "https://"` so the token never appears on the command line.

---

### M4: No git identity configured in the loop

**Problem:** `loop` calls `git commit` (delegated to agent) without ensuring `user.name` and `user.email` are set. If the container's global git config lacks these, the commit fails. The worker Dockerfile does not set them either.

**Impact:** Commits fail silently (or loudly, crashing the loop) on a fresh container build.

**Suggested fix:** Add `git config --global user.email` and `git config --global user.name` to the Dockerfile or to `loop` before the agent is invoked. Using the Jira email/name from existing env vars is natural: `git config --global user.email "$JIRA_EMAIL"`.

---

### M5: No timeout on agent execution

**Problem:** `run_agent_with_retry` has no timeout. If an agent hangs (infinite tool loop, waiting for a subprocess, etc.) the container is stuck indefinitely, consuming a slot in the worker pool without making progress.

**Suggested fix:** Wrap the agent invocation with `timeout` (e.g. `timeout "${AGENT_TIMEOUT:-3600}" bash -c "..."`) and treat a timeout exit (code 124) as a retriable failure with a distinct log message.

---

### M6: Excessive debug output in claim pollutes logs

**Problem:** `claim` prints raw `acli` output at every step:

```
Search result: [{"key":"PROJ-1",...}]
Verify output: {"key":"PROJ-1","fields":{...}}
```

This dumps full JSON blobs from the Jira API into stdout on every call. In a production deployment with many issues, this creates noisy, hard-to-parse logs.

**Suggested fix:** Move verbose Jira output to stderr or behind a `--verbose` / `DEBUG` flag. Keep only human-readable progress messages on stdout.

---

## Low Severity

### L1: JQL search includes "In Progress" issues in the exclusion filter

**Problem:** The JQL is `statusCategory != Done`, which *does* include "In Progress" issues — these are excluded only because `assignee is EMPTY`. An orphaned "In Progress" issue assigned to the worker account (see H2) satisfies neither filter condition and is permanently invisible.

**Suggested fix:** If orphan recovery is implemented (H2 fix), adjust the query to allow reclaiming assigned-but-stale issues.

---

### L2: JSON extraction from claim output is fragile

**Problem:** `loop` extracts the JSON block from `claim` output using:

```bash
ISSUE_JSON="$(printf '%s\n' "$CLAIM_OUTPUT" | awk '/^\{/{f=1} f')"
```

This works only if the JSON starts at column 0 on its own line and `claim` prints no other `{`-starting lines. The approach is brittle and will silently misparse if `claim`'s output format changes or if the JSON is pretty-printed across multiple lines.

**Suggested fix:** Have `claim` write the issue JSON to a temp file path (passed via flag or stdout with a sentinel prefix), or have `claim` exit with the JSON on a dedicated file descriptor, rather than mixing it with human-readable progress messages.

---

### L3: Single-point-of-failure architecture for Jira auth

**Problem:** Both `claim` and the agent's post-task acli calls share the same Jira account. If the account is locked, rate-limited by Jira, or the token revoked, all workers fail simultaneously.

**Suggested fix:** Support multiple Jira tokens rotated per-worker, or use a Jira service-account token with higher rate limits for automated use.

---

## Prioritised Improvement Roadmap

| Priority | Item | Effort |
|---|---|---|
| 1 | **H4** — Move git push + Jira comment/transition into loop (fix failing tests) | Low |
| 2 | **H3** — Feature-branch-per-issue instead of pushing to main | Medium |
| 3 | **H1** — Retry loop continues on non-rate-limit agent failures | Low |
| 4 | **H2** — Orphan recovery: re-queue stale In Progress issues | Medium |
| 5 | **H5** — Switch Claude auth to `ANTHROPIC_API_KEY` (long-lived) | Low |
| 6 | **M1** — Add `HEALTHCHECK` + document `--restart` policy | Low |
| 7 | **M4** — Configure git identity in Dockerfile | Trivial |
| 8 | **M2** — Expose `INTER_TASK_WAIT` env var | Trivial |
| 9 | **M5** — Wrap agent with `timeout` | Low |
| 10 | **M3** — Use git credential helper instead of URL embedding | Low |
| 11 | **M6** — Suppress verbose debug output in claim | Low |
| 12 | **L2** — Separate JSON from human output in claim | Medium |
