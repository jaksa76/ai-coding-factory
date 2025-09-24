import path from 'node:path';

const DATA_DIR = path.resolve('test/.data-test-pipelines');

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
  });

  afterEach(async () => {
    await fs.remove(DATA_DIR);
  });

  it('should list empty pipelines', async () => {
    const response = await api.get('/api/pipelines?task=non-existing-task').expect(200);
    expect(response.body).toEqual([]);
  });

  it('should require task parameter when listing pipelines', async () => {
    const response = await api.get('/api/pipelines').expect(400);
    expect(response.body.error).toBe('Missing task parameter');
  });

  it('should create a new pipeline', async () => {
    const response = await api.post('/api/pipelines')
      .send({ taskId: 'test-task', description: 'Test task' })
      .set('Content-Type', 'application/json')
      .expect(201);
    
    expect(response.body.id).toBeDefined();
    const pipelineId = response.body.id;

    // now list the pipelines for the task
    const listResponse = await api.get('/api/pipelines?task=test-task').expect(200);
    
    // expect list to include the pipeline we just created
    expect(listResponse.body).toContainEqual(expect.objectContaining({ id: pipelineId }));
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

  it('should validate pipeline ID format for status endpoint', async () => {
    const response = await api
      .get('/api/pipelines/invalid-format/status')
      .expect(400);
    
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });

  it('should validate pipeline ID format for logs endpoint', async () => {
    const response = await api
      .get('/api/pipelines/invalid-format/logs')
      .expect(400);
    
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });

  it('should validate pipeline ID format for stop endpoint', async () => {
    const response = await api
      .post('/api/pipelines/invalid-format/stop')
      .expect(400);
    
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });
});