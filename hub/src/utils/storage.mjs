import fs from 'fs-extra';
import path from 'node:path';

const DATA_DIR = process.env.DATA_DIR || '/tmp/ai-coding-factory';
const TASKS_DIR = path.join(DATA_DIR, 'tasks');
await fs.ensureDir(TASKS_DIR);

export const tasksPath = (id) => path.join(TASKS_DIR, `${id}.json`);

export async function readJSON(file) {
  return fs.readJSON(file);
}

export async function writeJSON(file, data) {
  await fs.outputJSON(file, data, { spaces: 2 });
}

export async function listTasks() {
  const files = await fs.readdir(TASKS_DIR);
  const jsons = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    const full = path.join(TASKS_DIR, f);
    try {
      const data = await fs.readJSON(full);
      jsons.push(data);
    } catch {}
  }
  return jsons;
}

export function generateId() {
  return `task_${Date.now()}_${process.pid}`;
}
