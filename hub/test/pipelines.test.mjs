import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.resolve(__dirname, '.data-test-pipelines');

// Set environment for tests BEFORE importing app
process.env.DATA_DIR = DATA_DIR;
process.env.PIPELINE_IMAGE = 'mock-coding-pipeline:test';

import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import supertest from 'supertest';
import fs from 'fs-extra';
import { createApp } from '../src/app.mjs';

let server;
let api;

beforeAll(async () => {
  const app = createApp();
  server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  api = supertest(server);
  process.env.HUB_URL = `http://127.0.0.1:${server.address().port}`;
});

afterAll(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
});

async function waitForStatus(pipelineId, expectedStatus, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const res = await api.get(`/api/pipelines/${encodeURIComponent(pipelineId)}`);
    if (res.body.status === expectedStatus) return res.body;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Timed out waiting for pipeline ${pipelineId} to reach status "${expectedStatus}"`);
}

describe('Pipelines API', () => {
  const createdPipelines = [];

  beforeEach(async () => {
    await fs.remove(DATA_DIR);
    createdPipelines.length = 0;
  });

  afterEach(async () => {
    for (const id of createdPipelines) {
      try { await api.post(`/api/pipelines/${encodeURIComponent(id)}/stop`); } catch {}
    }
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

  it('should validate required fields when creating a pipeline', async () => {
    await api.post('/api/pipelines').send({ description: 'Test task' }).expect(400);
    await api.post('/api/pipelines').send({ taskId: 'test-task' }).expect(400);
  });

  it('should validate pipeline ID format for status endpoint', async () => {
    const response = await api.get('/api/pipelines/invalid-format/status').expect(400);
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });

  it('should validate pipeline ID format for logs endpoint', async () => {
    const response = await api.get('/api/pipelines/invalid-format/logs').expect(400);
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });

  it('should validate pipeline ID format for stop endpoint', async () => {
    const response = await api.post('/api/pipelines/invalid-format/stop').expect(400);
    expect(response.body.error).toBe('Invalid pipeline ID format');
  });

  it('should create a pipeline and persist the record', async () => {
    const res = await api.post('/api/pipelines')
      .send({ taskId: 'test-task', description: 'Test task', mockMode: 'instant' })
      .expect(201);

    expect(res.body.id).toBeDefined();
    expect(res.body.taskId).toBe('test-task');
    expect(res.body.status).toBe('running');
    createdPipelines.push(res.body.id);

    const getRes = await api.get(`/api/pipelines/${encodeURIComponent(res.body.id)}`).expect(200);
    expect(getRes.body.id).toBe(res.body.id);

    const listRes = await api.get('/api/pipelines?task=test-task').expect(200);
    expect(listRes.body).toContainEqual(expect.objectContaining({ id: res.body.id, taskId: 'test-task' }));
  });

  it('mock agent completes all stages', { timeout: 30000 }, async () => {
    const res = await api.post('/api/pipelines')
      .send({ taskId: 'complete-task', description: 'Completion test', mockMode: 'instant' })
      .expect(201);
    createdPipelines.push(res.body.id);

    const final = await waitForStatus(res.body.id, 'completed');
    expect(final.stages).toHaveLength(6);
    for (const stage of final.stages) {
      expect(stage.status).toBe('completed');
    }
  });

  it('mock agent fails at planning stage', { timeout: 30000 }, async () => {
    const res = await api.post('/api/pipelines')
      .send({ taskId: 'fail-task', description: 'Fail test', mockMode: 'fail_at_planning' })
      .expect(201);
    createdPipelines.push(res.body.id);

    const final = await waitForStatus(res.body.id, 'failed');
    expect(final.stages[2].status).toBe('failed');
  });

  it('can stop a hung pipeline', { timeout: 30000 }, async () => {
    const res = await api.post('/api/pipelines')
      .send({ taskId: 'hang-task', description: 'Hang test', mockMode: 'hang' })
      .expect(201);
    const pipelineId = res.body.id;
    createdPipelines.push(pipelineId);

    // Wait until stage 0 is in_progress (container is running)
    const deadline = Date.now() + 15000;
    while (Date.now() < deadline) {
      const r = await api.get(`/api/pipelines/${encodeURIComponent(pipelineId)}`);
      if (r.body.stages?.[0]?.status === 'in_progress') break;
      await new Promise((r) => setTimeout(r, 500));
    }

    await api.post(`/api/pipelines/${encodeURIComponent(pipelineId)}/stop`).expect(200);
    const r = await api.get(`/api/pipelines/${encodeURIComponent(pipelineId)}`).expect(200);
    expect(r.body.status).toBe('stopped');
  });

  it('mock agent runs a custom bash script', { timeout: 30000 }, async () => {
    const mockScript = [
      'cloning() { echo "Custom clone output"; }',
      'implementing() { echo "Custom implement output"; }',
      'verifying() { echo "Verify failed"; exit 1; }',
    ].join('\n');

    const res = await api.post('/api/pipelines')
      .send({ taskId: 'script-task', description: 'Script test', mockScript })
      .expect(201);
    createdPipelines.push(res.body.id);

    const final = await waitForStatus(res.body.id, 'failed');
    expect(final.stages[0].content).toContain('Custom clone output');
    expect(final.stages[3].content).toContain('Custom implement output');
    expect(final.stages[5].status).toBe('failed');
    expect(final.stages[5].content).toContain('Verify failed');
  });

  it('two concurrent pipelines get distinct IDs', { timeout: 30000 }, async () => {
    const taskId = `concurrent-${Date.now()}`;
    const [r1, r2] = await Promise.all([
      api.post('/api/pipelines').send({ taskId, description: 'Pipeline 1', mockMode: 'instant' }),
      api.post('/api/pipelines').send({ taskId, description: 'Pipeline 2', mockMode: 'instant' }),
    ]);
    expect(r1.status).toBe(201);
    expect(r2.status).toBe(201);
    expect(r1.body.id).not.toBe(r2.body.id);
    createdPipelines.push(r1.body.id, r2.body.id);

    const listRes = await api.get(`/api/pipelines?task=${taskId}`).expect(200);
    const ids = listRes.body.map((p) => p.id);
    expect(ids).toContain(r1.body.id);
    expect(ids).toContain(r2.body.id);
  });
});
