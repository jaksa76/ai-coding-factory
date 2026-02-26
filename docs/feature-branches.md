# Feature Branches & Pull Requests — Functional Requirements

## 1. Overview

Currently, workers commit their changes directly to the default branch of the target repository. This means there is no human review of the code before it lands in main, which may be undesirable for teams that require a pull-request-based workflow.

This feature introduces an optional mode in which the worker:

1. Creates a dedicated feature branch for each issue.
2. Implements the work on that branch.
3. Opens a pull request (PR) against the default branch upon completion.
4. Posts a Jira comment with the PR link and optionally transitions the issue to an "In Review" status.

A human then reviews and merges the PR through the normal code review process. The worker never merges the branch itself.

---

## 2. Opt-In / Opt-Out Mechanism

### Project-wide default

The environment variable **`FEATURE_BRANCHES`** sets the default for the entire project:

| Value | Meaning |
|---|---|
| unset or `false` | Workers push directly to the default branch (existing behaviour) |
| `true` | Workers always create a feature branch and open a PR |

### Per-issue override via Jira labels

A label on the Jira issue can override the project-wide default:

| Label | Effect |
|---|---|
| `needs-branch` | Force feature-branch flow for this issue, even when `FEATURE_BRANCHES` is `false` |
| `skip-branch` | Skip feature-branch flow for this issue, even when `FEATURE_BRANCHES` is `true` |

If both labels are present on the same issue, `skip-branch` takes precedence.

### Decision matrix

| `FEATURE_BRANCHES` | Issue label | Feature branch used? |
|---|---|---|
| `false` (or unset) | _(none)_ | No |
| `false` (or unset) | `needs-branch` | Yes |
| `false` (or unset) | `skip-branch` | No |
| `true` | _(none)_ | Yes |
| `true` | `needs-branch` | Yes |
| `true` | `skip-branch` | No |

---

## 3. Branch Naming Convention

Feature branches follow a predictable, machine-readable pattern:

```
feature/<ISSUE-KEY>
```

Examples: `feature/MYPROJ-42`, `feature/ACME-7`.

The branch is created from the tip of the current default branch at the time the worker starts implementation. If a branch with the same name already exists (e.g. a previous aborted attempt), the worker resets it to the current default branch tip before starting, so each run is always a clean slate.

---

## 4. Pull Request

| Property | Value |
|---|---|
| Base branch | Repository default branch (e.g. `main`) |
| Head branch | `feature/<ISSUE-KEY>` |
| Title | `[<ISSUE-KEY>] <issue summary>` |
| Body | Links to the Jira issue; brief description of changes made |
| Draft | No — opened as a ready-for-review PR |
| Auto-merge | Not enabled by the worker; CI/merge policies are the team's concern |
| Merge | Performed by a human reviewer, not the worker |

PRs are created via the **`gh` CLI** (GitHub) using the `GH_TOKEN` environment variable. Support for other platforms (GitLab, Bitbucket) is out of scope for this iteration.

---

## 5. Agent Prompt Changes

When the feature-branch flow is active, the agent's prompt is adjusted to reflect the different commit/push workflow:

**Without feature branches (current):**
> Implement the issue … commit the change … push the changes … comment on Jira … transition the issue to Done.

**With feature branches:**
> Implement the issue … create a feature branch named `feature/<ISSUE-KEY>` from the current default branch … commit all changes to that branch … push the branch … open a pull request against the default branch with the title `[<ISSUE-KEY>] <summary>` … add a Jira comment with the PR URL … transition the issue to `In Review` (if that status is available, otherwise leave it as `In Progress`).

The agent is responsible for all git and `gh` operations within the work directory.

---

## 6. Jira Workflow

### With feature branches

```
To Do → In Progress → In Review → Done
```

| Transition | Meaning |
|---|---|
| To Do → In Progress | Worker has claimed the issue and is implementing |
| In Progress → In Review | PR has been opened; human review is required |
| In Review → Done | PR has been merged (performed by a human; Jira transition is manual or via automation) |

The worker transitions the issue to `In Review` after the PR is created. The final `Done` transition is outside the worker's scope — it is expected to happen manually or via a Jira/GitHub automation triggered by the PR merge.

### Without feature branches

```
To Do → In Progress → Done
```

The existing behaviour is unchanged.

---

## 7. Jira Issue Linkage

After the PR is opened, the worker adds a comment to the Jira issue containing:

- The PR URL (e.g. `https://github.com/org/repo/pull/123`).
- A one-line summary of what was implemented.

This comment is the primary notification mechanism. No other alerting is provided.

---

## 8. Environment Variables

| Variable | Purpose |
|---|---|
| `FEATURE_BRANCHES` | Set to `true` to enable feature-branch flow project-wide |
| `GH_TOKEN` | GitHub personal access token used by `gh` to open PRs |

`GH_TOKEN` is already present in the `workers/copilot` worker. It must be added to any other worker containers that use the feature-branch flow.

---

## 9. Jira Status: `In Review`

The `In Review` status is optional infrastructure. If the worker cannot transition to it (because the status does not exist in the project's workflow), it falls back gracefully:

| Situation | Behaviour |
|---|---|
| `In Review` status exists | Issue is transitioned after PR creation |
| `In Review` status is absent | Issue remains `In Progress`; a warning is logged; the Jira comment with the PR link is still posted |

The worker never fails or leaves the issue in a broken state because of a missing status.

---

## 10. Interaction with the Planning Phase

Feature branches and the planning phase are independent features that can be combined:

| Planning | Feature branches | Resulting flow |
|---|---|---|
| Off | Off | To Do → In Progress → Done (direct push, current behaviour) |
| On | Off | To Do → Planning → Awaiting Plan Review → Plan Approved → In Progress → Done (direct push) |
| Off | On | To Do → In Progress → In Review → Done (PR-based) |
| On | On | To Do → Planning → Awaiting Plan Review → Plan Approved → In Progress → In Review → Done (PR-based) |

When both are active, the planner worker generates and commits the plan to the **default branch** even when feature branches are enabled (the plan is infrastructure, not a code change). The implementer worker then operates on a feature branch as normal.

---

## 11. Constraints and Non-Goals

- **GitHub only.** PR creation uses `gh`; GitLab/Bitbucket support is not in scope.
- **No auto-merge.** The worker opens the PR but never merges it.
- **No branch protection enforcement.** The worker does not verify that branch protection rules are configured; it simply follows the flow.
- **One branch per issue.** The branch is always named `feature/<ISSUE-KEY>`; multiple workers racing on the same issue would collide (the `claim` race-detection mechanism prevents this).
- **Workers do not delete branches.** Branch cleanup after merge is left to the team's repository settings (e.g. GitHub's "automatically delete head branches" option).
- **The `Done` transition remains manual (or automated externally).** The worker is not involved in the final merge-to-Done step.
