import path from 'node:path';

const DATA_DIR = path.resolve('test/.data-test-pipelines');
const TASKS_DIR = path.join(DATA_DIR, 'tasks');
const PIPELINES_DIR = path.join(DATA_DIR, 'pipelines');

// Set environment for tests BEFORE importing app
process.env.DATA_DIR = DATA_DIR;

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import supertest from 'supertest';
import fs from 'fs-extra';
import { createApp } from '../src/app.mjs';

const app = createApp();
const api = supertest(app);

describe('Pipelines API', () => {
  beforeEach(async () => {
    await fs.remove(DATA_DIR);
    await fs.ensureDir(TASKS_DIR);
    await fs.ensureDir(PIPELINES_DIR);
  });

  afterEach(async () => {
    await fs.remove(DATA_DIR);
  });

  it('should list empty pipelines', async () => {
    const response = await api.get('/api/pipelines').expect(200);
    expect(response.body).toEqual([]);
  });

  it('should list pipelines for a specific task', async () => {
    // First create a task
    const taskResponse = await api
      .post('/api/tasks')
      .send({ description: 'Test task' })
      .expect(200);
    
    const taskId = taskResponse.body.id;

    // Create a pipeline manually for testing
    const pipelineId = `${taskId}_pipeline_1`;
    const pipeline = {
      id: pipelineId,
      taskId,
      description: 'Test task',
      status: 'starting',
      createdAt: new Date().toISOString(),
      containerName: `pipe-${pipelineId}`,
      volumeName: `vol-${pipelineId}`
    };

    await fs.outputJSON(path.join(PIPELINES_DIR, `${pipelineId}.json`), pipeline, { spaces: 2 });

    const response = await api.get(`/api/pipelines?task=${taskId}`).expect(200);
    expect(response.body).toHaveLength(1);
    expect(response.body[0].id).toBe(pipelineId);
    expect(response.body[0].taskId).toBe(taskId);
  });

  it('should get a specific pipeline', async () => {
    // First create a task
    const taskResponse = await api
      .post('/api/tasks')
      .send({ description: 'Test task' })
      .expect(200);
    
    const taskId = taskResponse.body.id;
    const pipelineId = `${taskId}_pipeline_1`;
    const pipeline = {
      id: pipelineId,
      taskId,
      description: 'Test task',
      status: 'starting',
      createdAt: new Date().toISOString(),
      containerName: `pipe-${pipelineId}`,
      volumeName: `vol-${pipelineId}`
    };

    await fs.outputJSON(path.join(PIPELINES_DIR, `${pipelineId}.json`), pipeline, { spaces: 2 });

    const response = await api.get(`/api/pipelines/${pipelineId}`).expect(200);
    expect(response.body.id).toBe(pipelineId);
    expect(response.body.taskId).toBe(taskId);
  });

  it('should return 404 for non-existing pipeline', async () => {
    const response = await api.get('/api/pipelines/non-existing').expect(404);
    expect(response.body.error).toBe('Pipeline not found');
  });

  it('should validate required fields when creating a pipeline', async () => {
    // Test missing taskId
    await api
      .post('/api/pipelines')
      .send({ description: 'Test task' })
      .expect(400);

    // Test missing description
    await api
      .post('/api/pipelines')
      .send({ taskId: 'test-task' })
      .expect(400);
  });

  it('should return 404 when creating pipeline for non-existing task', async () => {
    const response = await api
      .post('/api/pipelines')
      .send({ taskId: 'non-existing-task', description: 'Test description' })
      .expect(404);
    
    expect(response.body.error).toBe('Task not found');
  });

  it('should return 404 when stopping non-existing pipeline', async () => {
    const response = await api
      .post('/api/pipelines/non-existing/stop')
      .expect(404);
    
    expect(response.body.error).toBe('Pipeline not found');
  });

  it('should return 400 when stopping non-running pipeline', async () => {
    // First create a task
    const taskResponse = await api
      .post('/api/tasks')
      .send({ description: 'Test task' })
      .expect(200);
    
    const taskId = taskResponse.body.id;
    const pipelineId = `${taskId}_pipeline_1`;
    const pipeline = {
      id: pipelineId,
      taskId,
      description: 'Test task',
      status: 'completed', // Not running
      createdAt: new Date().toISOString(),
      containerName: `pipe-${pipelineId}`,
      volumeName: `vol-${pipelineId}`
    };

    await fs.outputJSON(path.join(PIPELINES_DIR, `${pipelineId}.json`), pipeline, { spaces: 2 });

    const response = await api
      .post(`/api/pipelines/${pipelineId}/stop`)
      .expect(400);
    
    expect(response.body.error).toBe('Pipeline not running');
  });
});