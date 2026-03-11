# Test Blind Spots and Potential Improvements

## Executive Summary

The test suite is well-structured with a clear two-tier approach (unit + integration).
Unit tests stub all external dependencies and cover argument validation, happy paths, and most
failure modes. Integration tests exercise real Jira and Git APIs.

Despite this coverage, several classes of errors can slip through undetected.

---

## 1. Stub Contract Drift

**Risk:** Medium–High

Unit tests stub `acli`, `git`, `gh`, and the agent with hardcoded responses. If the real tools
change their output format or exit codes, stubs stay green while the real system breaks.

Examples:
- `acli jira workitem search` returns a JSON array today. If it changes to a paginated envelope,
  `jq '.[0].key'` in `task-manager` silently returns null.
- `git symbolic-ref --short HEAD` format varies between Git versions.
- `gh pr create` output format changed in past CLI versions.

**What's not tested:** The interface contract between each tool's real output and the parser
inside `task-manager` / `implement` / `plan`. Only integration tests catch this, but they
require real credentials and aren't run in CI by default.

**Improvement:** Add a small "contract test" layer that replays recorded real API responses
through the parsing logic. These are fast (no network), reproducible, and detect format drift
early.

---

## 2. Agent Output Handling

**Risk:** High

The agent is an AI. In unit tests, the `agent` stub either succeeds silently or prints a
rate-limit string. In integration tests, the agent is mocked as a shell script.

Undetected failure modes:
- Agent produces no output and exits 0 (vacuous success) — `implement` would proceed to push
  an empty commit and close the issue.
- Agent creates `plans/PROJ-1.md` with zero bytes — `plan` would commit and post an empty plan.
- Agent prints to stderr instead of stdout; rate-limit detection (`grep "rate limit"`) operates
  on combined output but relies on exact string patterns. OpenAI, Anthropic, and Copilot each
  have different rate-limit message formats.
- Agent modifies files outside the repo directory — not sandboxed, no validation.
- Agent loops or hangs — no timeout enforced at the `implement`/`plan` level.

**Improvement:**
- Add a test where the agent exits 0 but does nothing; verify the loop emits a warning rather
  than silently transitioning the issue to Done.
- Add timeout handling around the agent invocation.
- Normalise rate-limit detection to cover all known agent CLI patterns.

---

## 3. Git Failure Modes

**Risk:** Medium

Git operations (`clone`, `pull`, `push`, `commit`) are stubbed in unit tests. Failure cases
that are not tested:

- `git push` fails (branch protection, remote deleted, diverged history) — `implement` would
  still transition the issue to Done, leaving code unpushed.
- `git clone` times out on first run, leaving a partial `.git` directory — next run detects the
  directory and issues `git pull` instead of `clone`, which then also fails.
- Merge conflict on `git pull` (planner and implementer both touched the same branch).
- `git commit` exits 0 with "nothing to commit" — the agent made no file changes; issue
  is still transitioned to Done.

**Improvement:**
- Unit test for "push fails: issue is NOT transitioned to Done".
- Unit test for "nothing to commit after agent runs: emit warning, skip close".
- Unit test for partial `.git` directory recovery.

---

## 4. Concurrent Worker Race Conditions

**Risk:** Medium

Optimistic locking in `task-manager claim` is unit-tested for a single simulated race
(two sequential `view` calls). Real concurrent workers are never tested.

Undetected failures:
- Two workers claim the same issue within the assignment propagation window (Jira's eventual
  consistency means the 10-second wait may be insufficient under load).
- Multiple workers push to the same branch simultaneously.
- Race between planner finishing and implementer picking up the issue before the
  `Plan Approved` label is set.

**Improvement:** Integration test that launches two workers against the same Jira project
and verifies each issue is claimed at most once. This requires the Docker integration
path to be more exercised.

---

## 5. End-to-End System Gap

**Risk:** High

No test exercises the full stack:

```
factory add → Docker container → loop → task-manager → real agent → git push → Jira close
```

The worker integration tests (`claude-integration.bats`, `copilot-integration.bats`) verify
the worker image builds and that tools are installed, plus one live smoke test. But they
don't verify that a complete work cycle actually completes successfully.

**What can break here without being caught:**
- `LOOP_WORK_DIR` not set inside the container, causing the repo to clone into `/`.
- Environment variables dropped between `factory` → Docker `--env-file` → loop.
- The `agent` wrapper inside the container not found on `$PATH` when `loop` shells out.
- Token refresh logic never exercised in a running container (only in unit tests).

**Improvement:** Add one "smoke test" integration test that:
1. Starts a worker container with a mock agent.
2. Waits for it to claim a real Jira issue, run the mock agent, push a commit, and close the
   issue.
3. Asserts on the final Jira status and git history.

This is the most valuable missing test.

---

## 6. Issue Content Edge Cases

**Risk:** Low–Medium

Issue descriptions and summaries from Jira can contain:
- Newlines and embedded quotes (break shell here-documents and string comparisons).
- Unicode characters (Jira stores in UTF-8; some pipeline steps use `echo` which can mangle).
- Empty description (`null` in Jira JSON) — currently handled by defaulting to empty string,
  but not tested when the acli returns `null` vs. the string `"null"` vs. absent field.
- Very long descriptions (>32KB) — shell argument limits may truncate the prompt silently.

**Improvement:** Add unit test cases with special characters and null descriptions flowing
through `task-manager view` and then into the `implement`/`plan` prompt construction.

---

## 7. Polling Loop Longevity

**Risk:** Low (correctness) / Medium (reliability)

Unit tests run the loop for 1–2 iterations. A production worker runs indefinitely.

Undetected issues:
- Accumulation of temp files if a `mktemp` path is never cleaned up after a failed iteration.
- A bash subprocess leak if the agent hangs and is killed, leaving orphan processes.
- The credential store (`git credential approve`) invoked thousands of times — no test
  verifies it doesn't grow unboundedly.

**Improvement:** This is hard to test directly. At minimum, audit the loop iteration for
resource cleanup (temp files, subshells) and add a `trap ... EXIT` guard to the iteration body.

---

## 8. `worker-builder` Output Correctness

**Risk:** Medium

`worker-builder` generates a Dockerfile and builds it. The integration test verifies the
build succeeds, but doesn't verify the *contents* of the generated Dockerfile match expectations.

Undetected failures:
- A devcontainer that uses a base image without `bash` (the generated Dockerfile assumes bash).
- `worker-builder` generates a valid Dockerfile that builds, but the resulting image doesn't
  have `loop` or `agent` on `$PATH`.
- Feature flags or optional layers (e.g., jira vs. github backend) emitted incorrectly.

**Improvement:**
- Unit test the Dockerfile-generation step in isolation: given a known `devcontainer.json`,
  assert specific `FROM`, `RUN`, `COPY` lines appear in the generated Dockerfile.
- Add a post-build smoke check (`docker run --rm <image> which loop`) to the integration test.

---

## 9. Rate-Limit Detection Fragility

**Risk:** Medium

Rate-limit retry in `implement` uses `grep -i "rate limit\|overloaded\|529\|429"` (or similar)
on agent output. This pattern:
- Will miss new error messages added by agent CLI maintainers.
- May false-positive on issue descriptions that contain the string "rate limit".
- Does not distinguish transient from permanent errors (e.g., invalid API key also returns
  non-zero, but the loop should not retry those).

**Improvement:**
- Detect rate limits via exit code conventions rather than output parsing where possible.
- Add a test where the issue *description* contains "rate limit" — the agent succeeds, but
  verify the loop does NOT enter retry mode.

---

## 10. Backend Portability

**Risk:** Low

The `task-manager` dispatcher supports three backends (jira, github, todo). Most unit tests
cover all three, but:
- The GitHub backend `transitions` command returns a hardcoded static list (not from the API).
  If a workflow requires a status not in that list, the fallback silently skips the transition.
- The `todo` backend is only used for local development; it has no cleanup for `.md` marker
  characters if a task is abandoned mid-run.

**Improvement:**
- Document that `github transitions` is hardcoded and add a comment/warning in the source.
- Add a test that exercises `loop --project todo-file` end-to-end with a mock agent to catch
  any backend-specific divergence.

---

## Summary Table

| Area | Risk | Covered by existing tests | Suggested fix |
|---|---|---|---|
| Stub contract drift | Medium–High | Partially (integration) | Contract tests with recorded responses |
| Agent vacuous success | High | No | Unit test: agent exits 0, no changes |
| Agent timeout/hang | High | No | Timeout wrapper in implement/plan |
| Git push failure before transition | Medium | No | Unit test: push fails → issue stays open |
| Nothing-to-commit case | Medium | No | Unit test + warning/skip logic |
| Concurrent workers | Medium | No | Integration test with two workers |
| Full-stack E2E | High | No | Smoke test: container → Jira closed |
| Issue content edge cases | Low–Medium | Partially | Add unit tests for special chars / null |
| Rate-limit false positives | Medium | No | Test issue containing "rate limit" text |
| worker-builder Dockerfile | Medium | No | Unit test generated Dockerfile contents |
| Loop resource leaks | Low | No | Audit + EXIT trap |
| GitHub backend static transitions | Low | No | Document; add E2E todo test |
