- [ ] Create worker project - a docker image for running the pipelines
    - [ ] Capture logs
    - [ ] Update pipeline status (logs, running/finished)
    - [ ] Clone repo
    - [ ] Fake coding agent (changes background color)

- [ ] Create a UI using mini_httpd
    - [ ] Predefined task list
    - [ ] List tasks
    - [ ] Delete task
    - [ ] Start pipeline on a task
    - [ ] List tasks by status
    - [ ] See pipeline details (logs)
    - [ ] Create task (id, description)
    - [ ] Stop pipeline

Milestone 1: Demo

- [ ] Create pipelines.sh - a module to launch, list and stop pipelines (will leverage agents.sh)
    - [ ] Launch a pipeline (git url, git credentials, task id, task desc) - returns id
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
