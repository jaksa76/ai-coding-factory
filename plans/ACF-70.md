# [ACF-70] Adaptive loop: plan AND implement with smart mode selection

## Overview

Add an `--adaptive` mode to `loop` that can handle both planning and implementation work in a single worker process. Rather than pre-assigning a worker as "planner" or "implementer", the adaptive worker inspects queue availability each iteration and picks the most appropriate mode dynamically.

This allows a single worker to keep itself busy regardless of which queue has work, while still respecting the planning-first pipeline discipline.

---

## Motivation

Currently, operators must decide upfront how many planner workers vs. implementer workers to run. If the planning queue is empty, planner workers idle. If there are no approved plans, implementer workers idle (for issues that require plans). The adaptive loop eliminates this either-or choice for small teams or single-worker deployments.

---

## Design

### New flag

```bash
loop --project MYPROJ --adaptive
```

`--adaptive` is mutually exclusive with `--for-planning`. When set, the loop selects a mode each iteration according to the policy below.

### Selection policy

Each iteration:

1. **Probe the planning queue** — attempt to claim a planning issue (via `claim --for-planning --dry-run`).
2. **Probe the implementation queue** — attempt to claim an implementation issue (via `claim --dry-run`).
3. **Decide**:
   - If only planning work is available → run one planning iteration.
   - If only implementation work is available → run one implementation iteration.
   - If **both** are available → prefer planning (keeps the pipeline flowing; planned issues unblock future implementation slots).
   - If **neither** is available → wait `NO_ISSUES_WAIT` seconds and probe again.

This policy is "planning-first": it biases toward keeping the review pipeline fed rather than letting planned-but-not-yet-implemented issues accumulate.

### Env var override: `ADAPTIVE_PREFER`

To make the tie-breaking policy configurable without requiring a code change:

| Value | Tie-breaking behaviour |
|---|---|
| `planning` (default) | Prefer planning when both queues have work |
| `implementation` | Prefer implementation when both queues have work |
| `random` | Pick randomly (50/50 split) when both queues have work |

---

## Implementation plan

### 1. Add `--dry-run` to `claim`

`claim` needs a way to check whether an issue is available without actually claiming it (i.e. without side effects). Add `--dry-run`:

- Runs the list-and-pick step only.
- Exits 0 if an issue would be available, 2 if the queue is empty.
- Prints nothing; no Jira mutations.

This keeps the probe step cheap and non-destructive.

### 2. Add `probe_queue` helper to `loop`

```bash
# Returns 0 if the given queue has claimable issues, 2 if empty.
probe_queue() {
    local mode="$1"   # "" | "--for-planning"
    local extra=""
    [[ "$mode" == "planning" ]] && extra="--for-planning"
    claim --project "$PROJECT" --account-id "$JIRA_ASSIGNEE_ACCOUNT_ID" \
        $extra --dry-run >/dev/null 2>&1
}
```

### 3. Add `select_mode` function

```bash
# Prints "planning" or "implementation", or exits non-zero if both empty.
select_mode() {
    local has_planning=false has_impl=false
    probe_queue planning  && has_planning=true
    probe_queue implementation && has_impl=true

    if $has_planning && $has_impl; then
        local prefer="${ADAPTIVE_PREFER:-planning}"
        if [[ "$prefer" == "random" ]]; then
            (( RANDOM % 2 == 0 )) && echo "planning" || echo "implementation"
        elif [[ "$prefer" == "implementation" ]]; then
            echo "implementation"
        else
            echo "planning"
        fi
    elif $has_planning; then
        echo "planning"
    elif $has_impl; then
        echo "implementation"
    else
        return 2   # nothing available
    fi
}
```

### 4. Add `run_adaptive_loop` to `loop`

```bash
run_adaptive_loop() {
    while true; do
        set +e
        MODE="$(select_mode)"
        PROBE_EXIT=$?
        set -e

        if [[ "$PROBE_EXIT" -ne 0 ]]; then
            no_issues_wait="${NO_ISSUES_WAIT:-60}"
            echo "No issues available (planning or implementation). Waiting ${no_issues_wait}s..."
            sleep "$no_issues_wait"
            continue
        fi

        echo "Adaptive mode selected: $MODE"
        if [[ "$MODE" == "planning" ]]; then
            run_planning_iteration   # extracted from run_planning_loop
        else
            run_implementation_iteration  # extracted from run_implementation_loop
        fi
    done
}
```

### 5. Refactor existing loops

Extract the per-iteration body of `run_planning_loop` and `run_implementation_loop` into `run_planning_iteration` and `run_implementation_iteration` respectively. The existing loop functions become thin wrappers that call these in a `while true` loop. `run_adaptive_loop` calls whichever is appropriate.

This avoids duplicating the claim/work/push logic.

### 6. Argument parsing

Add `--adaptive` to the argument parser. Validate mutual exclusivity with `--for-planning`.

```bash
ADAPTIVE=false
# ...
--adaptive)
    ADAPTIVE=true; shift;;
# ...
if [[ "$FOR_PLANNING" == "true" && "$ADAPTIVE" == "true" ]]; then
    error_exit "--for-planning and --adaptive are mutually exclusive"
fi
```

At the bottom dispatch:

```bash
if [[ "$FOR_PLANNING" == "true" ]]; then
    run_planning_loop
elif [[ "$ADAPTIVE" == "true" ]]; then
    run_adaptive_loop
else
    run_implementation_loop
fi
```

---

## Testing

### Unit tests (`loop.bats`)

- **Adaptive: both queues empty** — dry-run returns 2 for both; loop waits and retries.
- **Adaptive: only planning available** — dry-run returns 0 for planning, 2 for impl; planning iteration runs.
- **Adaptive: only implementation available** — vice versa.
- **Adaptive: both available, ADAPTIVE_PREFER=planning** — planning iteration runs.
- **Adaptive: both available, ADAPTIVE_PREFER=implementation** — implementation iteration runs.
- **Adaptive: both available, ADAPTIVE_PREFER=random** — one of the two runs (non-deterministic; stub `RANDOM` or just assert exit 0).
- **Mutually exclusive flags** — `--adaptive --for-planning` exits with error.

### Claim unit tests (`claim.bats`)

- `--dry-run` with available issue → exit 0, no mutations.
- `--dry-run` with no issues → exit 2.
- `--dry-run` does not call assign/transition endpoints (assert mock call counts).

---

## Files changed

| File | Change |
|---|---|
| `claim/claim` | Add `--dry-run` flag |
| `claim/claim.bats` | Tests for `--dry-run` |
| `loop/loop` | Add `--adaptive`, `probe_queue`, `select_mode`, `run_adaptive_loop`; refactor loop bodies into `_iteration` functions |
| `loop/loop.bats` | Tests for adaptive mode |
| `docs/ARCHITECTURE.md` | Document `--adaptive` flag |

---

## Non-goals

- No per-issue priority weighting (issues are treated as equal within a queue).
- No cross-worker coordination (each adaptive worker probes independently; at most one will succeed in claiming any given issue due to Jira's optimistic locking).
- No dynamic scaling (adding/removing workers remains a `factory` concern).
