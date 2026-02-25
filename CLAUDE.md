# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This project is being redesigned. The previous implementation is preserved in `legacy/` for reference.

## Legacy Reference

The original hub-based architecture lives in `legacy/`. See `legacy/docs/` for the old architecture docs.

## New Architecture (planned)

Worker-based pull model where agents poll Jira directly for work, rather than a hub that imports Jira issues into a local store.

```
[Jira] ← single source of truth
   ↓  workers poll for assigned/open issues
[Worker pool]
   ↓  update ticket status, post comments
[Jira]

[Management UI] ← monitor workers, view logs, scale
```

Components to build:

```
worker/     Agent that pulls issues from Jira and works on them
manager/    Lightweight web UI for monitoring and scaling workers
```
