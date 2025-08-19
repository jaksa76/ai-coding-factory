import express from 'express';
import { $, chalk } from 'zx';
import { generateId, listTasks, readJSON, tasksPath, writeJSON } from '../utils/storage.mjs';
import fs from 'fs-extra';

const router = express.Router();

// Ensure zx doesn't print commands in tests unless DEBUG
$.verbose = !!process.env.DEBUG;

router.get('/', async (req, res) => {
  const list = await listTasks();
  res.json(list);
});

router.get('/:id', async (req, res) => {
  const id = req.params.id;
  const file = tasksPath(id);
  if (await fs.pathExists(file)) {
    const data = await readJSON(file);
    res.json(data);
  } else {
    res.status(404).json({ error: 'Task not found', message: 'Task with specified ID does not exist' });
  }
});

router.post(['/', '/:id'], async (req, res) => {
  if (req.params.id) {
    return res.status(405).json({ error: 'Method not allowed', message: 'POST with task ID is not allowed. Use PUT to update.' });
  }
  const { description = '' } = req.body || {};
  if (req.headers['content-type']?.includes('application/json') === false) {
    // keep compatible behavior but not strictly necessary
  }
  const id = generateId();
  const now = new Date().toISOString();
  const task = { id, description, status: 'pending', created_at: now, updated_at: now };
  await writeJSON(tasksPath(id), task);
  res.json(task);
});

router.put('/:id?', async (req, res) => {
  const id = req.params.id;
  if (!id) return res.status(400).json({ error: 'Missing task ID', message: 'Task ID is required for PUT requests' });
  const file = tasksPath(id);
  if (!(await fs.pathExists(file))) return res.status(404).json({ error: 'Task not found', message: 'Task with specified ID does not exist' });

  const current = await readJSON(file);
  const description = req.body?.description ?? current.description;
  const status = req.body?.status ?? current.status;
  const updated = { ...current, description, status, updated_at: new Date().toISOString() };
  await writeJSON(file, updated);
  res.json(updated);
});

router.delete('/:id?', async (req, res) => {
  const id = req.params.id;
  if (!id) return res.status(400).json({ error: 'Missing task ID', message: 'Task ID is required for DELETE requests' });
  const file = tasksPath(id);
  if (await fs.pathExists(file)) {
    await fs.remove(file);
    res.json({ message: 'Task deleted successfully' });
  } else {
    res.status(404).json({ error: 'Task not found', message: 'Task with specified ID does not exist' });
  }
});

export default router;
