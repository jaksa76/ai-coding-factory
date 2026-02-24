The AI Codibng Factory is an attempt at automating software development using AI agents with minimal human supervision. The goal is to streamline the software development process, from understanding requirements to deploying and maintaining applications without sacrificing quality or security. This document outlines the requirements for the AI Coding Factory project, including functional and non-functional requirements, as well as any constraints and assumptions.


## High-Level Requirements

- manage multiple projects
- manage tasks for each project
- trigger implementation planning of tasks
- review implementation plans of tasks
- trigger implementation of tasks
- review code changes of implemented tasks
- access ephemeral environments for testing tasks
- observe progress of tasks

## UI

The UI is a browser-based single-page application. The default (and primary) screen is the **Tasks** board. Projects are selected via a dropdown in the header — there is no dedicated project list screen. Detail screens for individual task stages open on top of the board. All data is fetched from the hub REST API; no full page reloads are required.

---

### Global Header

- Brand logo and name ("AI Coding Factory") on the left.
- **Project selector** — a searchable dropdown listing all projects. Typing filters the list by name. A "New Project" option at the bottom of the list opens a small inline form (name + optional description). Selecting a project switches the board to that project's tasks.
- A refresh button and a user/settings icon on the right.

---

### Screen 1 – Tasks Board (default screen)

**Purpose:** shows all tasks for the selected project as a prioritised, reorderable list.

#### Task Table

Each task occupies one row. Rows can be reordered by drag-and-drop (a grab handle on the left edge indicates draggability). The saved order represents priority.

Columns:

| Column | Detail |
|---|---|
| ⠿ (handle) | Drag handle for reordering |
| Title | Short story title / description; click to open the Description screen (3a) |
| **Stage pipeline** | A horizontal sequence of stage chips — one per stage (see below) |
| Delete | Trash icon; requires a confirmation dialog |

#### Stage Pipeline Chips

Each chip represents one stage of the task lifecycle. Chips appear inline in the row in order:

| Stage | Chip label | Active action |
|---|---|---|
| Description | Description | Edit button → opens Screen 3a |
| Planning | Plan | Trigger button to start planning, or Review button when plan is ready → opens Screen 3b |
| Implementation | Code | Trigger button to start implementation (enabled after plan approved), or Review button when code is ready → opens Screen 3c |
| Testing / Environment | App | Open button when an ephemeral environment is available → opens Screen 3d |

Each chip shows a status icon (idle / in-progress spinner / needs-review / done / error). Chips that have an action surface a small button directly in the row; no navigation to a detail screen is required to trigger actions.

#### Toolbar (above the table)

- Search box — filters rows by title or ID.
- Status filter dropdown — All / Pending / Planning / In Progress / Review / Done.
- "New Task" button — appends an editable row at the top of the table (inline: title field + Create / Cancel).
- "Import from Jira" button — opens a modal with site, email, API token, and project key fields.

---

### Screen 3a – Task Description

**Purpose:** view and edit the full task description.

- Opened by clicking the task title or the Description chip's Edit button.
- Displays as an overlay or a dedicated route (e.g., `/tasks/:id/description`).
- Editable text area pre-populated with the current description.
- **Save** button (appears when content changes) and a **Back** / **Close** control to return to the board.
- Note: this screen may be replaced by a Jira or GitHub issue view when the task originates from an external tool.

---

### Screen 3b – Implementation Plan

**Purpose:** review and approve the AI-generated implementation plan for a task.

- Opened by clicking the Plan chip's Review button.
- Displays as an overlay or a dedicated route (e.g., `/tasks/:id/plan`).
- Shows the plan as a structured, numbered list of steps.
- A **Review Plan** form lets the user approve the plan or request changes with a free-text feedback field.
- Status indicator at the top: "No plan yet" / "Planning…" / "Plan ready – awaiting review" / "Approved".
- Note: this screen may be replaced by a Jira or GitHub PR/issue view.

---

### Screen 3c – Code Changes

**Purpose:** review the AI-generated code changes.

- Opened by clicking the Code chip's Review button.
- Displays as an overlay or a dedicated route (e.g., `/tasks/:id/code`).
- Shows a unified or side-by-side diff of changed files.
- A **Review Changes** form lets the user approve or request changes with a comment.
- Status indicator: "Not started" / "Implementing…" / "Changes ready – awaiting review" / "Approved".
- Note: this screen may be replaced by a GitHub Pull Request view.

---

### Screen 3d – Ephemeral Environment

**Purpose:** access the live preview of the implemented task.

- Opened by clicking the App chip's Open button.
- Displays as an overlay or a dedicated route (e.g., `/tasks/:id/app`).
- Shows an embedded preview (iframe) or a prominent link to the environment URL.
- Includes a pipeline activity log: timeline of pipeline runs (newest first), each expandable to a live log viewer (auto-scrolling, monospaced font).
- **Stop** button for the currently running pipeline.
- Note: ephemeral environment provisioning may be delegated to an external CI/CD tool.

---

### Progress Observation

- The board auto-refreshes every 10 seconds while any task has a pipeline in progress.
- Spinning indicators appear on the relevant stage chip(s) during active runs.
- A small animated indicator in the browser tab title reflects background activity.
- Toast notifications appear in the top-right corner for success and error events (auto-dismiss after 4 s).

---

### Non-Functional UI Requirements

- Responsive layout supporting viewports from 1024 px upward.
- Keyboard accessible: all actions reachable without a mouse; modal dialogs and overlays trap focus.
- `Ctrl+N` / `Cmd+N` opens the "New Task" inline form; `Esc` closes any open modal, overlay, or inline form.
- No external framework dependency beyond what is already in use (vanilla JS + Font Awesome icons).
- All destructive actions (delete, stop) require a confirmation dialog.
- Stage detail screens (3a–3d) are designed to be replaceable with external tool integrations (Jira, GitHub) without changing the board layout.

