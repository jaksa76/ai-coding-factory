- [ ] coding-pipeline - a docker image for running the pipelines
    - [x] Capture logs in Docker
    - [ ] Capture logs on AWS ECS using CloudWatch
    - [ ] Enable coding pipeline to update the pipeline status in the hub (logs, running/finished)
    - [x] Clone the git repo at the start of the pipeline
    - [ ] Implement a fake coding agent that doesn't use AI (changes background color depending on the task description)

- [ ] Hub - a web app to manage tasks and pipelines
    - [x] Predefined task list
    - [x] List tasks
    - [x] Delete task
    - [x] Start pipeline on a task
    - [x] List tasks by status
    - [x] See pipeline details (logs)
    - [x] Create task (id, description)
    - [x] Import tasks from Jira
    - [ ] Properly distinguish active and stopped pipelines

Milestone 1: Demo

- [x] Create pipelines.sh - a module to launch, list and stop pipelines (will leverage agents.sh)
    - [x] Launch a pipeline (task id, task desc)
    - [x] Pass git credentials to pipeline
    - [x] List pipelines for a task
    - [x] Stop pipeline (id)
    - [ ] Update pipeline status - save info to disk (set number of stages, current stage, current stage uptime)
    - [x] Get pipeline status

- [ ] Improve worker project
    - [ ] Fake deploy
    - [ ] Update pipeline status (deployed url)
    - [ ] Create PR
    - [ ] Real coding agent
    - [ ] Deploy

Milestone 2: MVP

- [ ] Custom pipeline definition
- [ ] Containerized Pipeline stages
- [ ] Better Jira integration (import more details, comments, attachments)
- [ ] Teams integration (ask stakeholders for feedback, notifications etc.)
