import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import path from 'node:path';
import fs from 'fs-extra';
import { fileURLToPath } from 'node:url';
import { createApp } from '../src/app.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let app;

describe('Hub API', () => {
  beforeAll(async () => {
    process.env.DATA_DIR = path.join(__dirname, '.data-test');
    await fs.ensureDir(process.env.DATA_DIR);
    app = createApp();
  });

  beforeEach(async () => {
    await fs.emptyDir(path.join(process.env.DATA_DIR, 'tasks'));
  });

  it('hub is running', async () => {
    const res = await request(app).get('/');
    expect([200, 304]).toContain(res.status);
  });

  it('create a task and fetch it', async () => {
    const desc = `Test task ${Date.now()}`;
    const create = await request(app)
      .post('/api/tasks.cgi')
      .set('Content-Type', 'application/json')
      .send({ description: desc });
    expect(create.status).toBe(200);
    expect(create.body.id).toBeTruthy();

    const list = await request(app).get('/api/tasks.cgi');
    expect(list.status).toBe(200);
    expect(Array.isArray(list.body)).toBe(true);
    const found = list.body.find((t) => t.description === desc);
    expect(found).toBeTruthy();

    const one = await request(app).get(`/api/tasks.cgi/${found.id}`);
    expect(one.status).toBe(200);
    expect(one.body.id).toBe(found.id);
  });

  it('CRUD: create, get, update, delete a task', async () => {
    const create = await request(app)
      .post('/api/tasks.cgi')
      .send({ description: 'CRUD test' })
      .set('Content-Type', 'application/json');
    expect(create.status).toBe(200);
    const id = create.body.id;
    expect(id).toBeTruthy();
    expect(create.body.status).toBe('pending');

    const get = await request(app).get(`/api/tasks.cgi/${id}`);
    expect(get.status).toBe(200);

    const upd = await request(app)
      .put(`/api/tasks.cgi/${id}`)
      .send({ status: 'done' })
      .set('Content-Type', 'application/json');
    expect(upd.status).toBe(200);
    expect(upd.body.status).toBe('done');

    const del = await request(app).delete(`/api/tasks.cgi/${id}`);
    expect(del.status).toBe(200);
    expect(del.body.message).toBe('Task deleted successfully');

    const notFoundAfter = await request(app).get(`/api/tasks.cgi/${id}`);
    expect(notFoundAfter.status).toBe(404);
  });

  it('invalid JSON returns 400', async () => {
    const res = await request(app)
      .post('/api/tasks.cgi')
      .set('Content-Type', 'application/json')
      .send('{invalid');
    expect(res.status).toBe(400);
  });

  it('PUT without ID returns 400', async () => {
    const res = await request(app)
      .put('/api/tasks.cgi')
      .set('Content-Type', 'application/json')
      .send({ status: 'done' });
    expect(res.status).toBe(400);
  });

  it('POST with ID not allowed returns 405', async () => {
    const res = await request(app)
      .post('/api/tasks.cgi/someid')
      .set('Content-Type', 'application/json')
      .send({ description: 'x' });
    expect(res.status).toBe(405);
  });

  it('update non-existing returns 404', async () => {
    const res = await request(app)
      .put('/api/tasks.cgi/task_000000_nonexistent')
      .set('Content-Type', 'application/json')
      .send({ status: 'done' });
    expect(res.status).toBe(404);
  });

  it('delete non-existing returns 404', async () => {
    const res = await request(app).delete('/api/tasks.cgi/task_000000_nonexistent');
    expect(res.status).toBe(404);
  });
});
