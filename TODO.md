- [ ] Create worker project - a docker image for running the pipelines
    - [x] Capture logs
    - [ ] Update pipeline status (logs, running/finished)
    - [ ] Clone repo
    - [ ] Fake coding agent (changes background color)

- [ ] Create a UI using mini_httpd
    - [x] Predefined task list
    - [x] List tasks
    - [x] Delete task
    - [x] Start pipeline on a task
    - [x] List tasks by status
    - [x] See pipeline details (logs)
    - [x] Create task (id, description)
    - [ ] Stop pipeline

Milestone 1: Demo

- [x] Create pipelines.sh - a module to launch, list and stop pipelines (will leverage agents.sh)
    - [x] Launch a pipeline (task id, task desc)
    - [ ] Pass git credentials to pipeline
    - [ ] List pipelines
    - [ ] Stop pipeline (id)
    - [ ] Update pipeline status - save info to disk (set number of stages, current stage, current stage uptime)
    - [ ] Get pipeline status
    - [ ] Get pipeline logs (by stage)

- [ ] Improve worker project
    - [ ] Fake deploy
    - [ ] Update pipeline status (deployed url)
    - [ ] Create PR
    - [ ] Real coding agent
    - [ ] Deploy

Milestone 2: MVP

- [ ] Custom pipeline definition
- [ ] Containerized Pipeline stages
- [ ] Jira integration
- [ ] Teams integration
