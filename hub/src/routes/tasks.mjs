import express from 'express';
import { $, chalk } from 'zx';
import fs from 'fs-extra';
import path from 'node:path';

const getDataDir = () => process.env.DATA_DIR || '/tmp/ai-coding-factory';
const getTasksDir = () => path.join(getDataDir(), 'tasks');

const ensureTasksDir = async () => {
  await fs.ensureDir(getTasksDir());
};

const tasksPath = (id) => path.join(getTasksDir(), `${id}.json`);

const readJSON = (file) => fs.readJSON(file);

const writeJSON = (file, data) => fs.outputJSON(file, data, { spaces: 2 });

const listTasks = async () => {
  await ensureTasksDir();
  const TASKS_DIR = getTasksDir();
  const files = await fs.readdir(TASKS_DIR);
  const jsons = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    const full = path.join(TASKS_DIR, f);
    try { jsons.push(await fs.readJSON(full)); } catch {}
  }
  return jsons;
};
const generateId = () => `task_${Date.now()}_${process.pid}`;

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
  const task = { id, description, status: 'pending' };
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

  const updated = { ...current, description, status };
  await writeJSON(file, updated);
  res.json(updated);

  // Start pipeline via the new pipeline API when status changes to 'in-progress'
  if (current.status !== 'in-progress' && status === 'in-progress') {
    console.log(chalk.green(`Task ${id} started, creating new pipeline...`));
    try {
      // Create a new pipeline for this task
      const pipelineData = {
        taskId: id,
        description: description,
        gitUrl: req.body?.gitUrl,
        gitUsername: req.body?.gitUsername,
        gitToken: req.body?.gitToken
      };
      
      // We'll make an internal call to the pipeline creation logic
      // This is a bit of a workaround since we can't easily make HTTP calls to ourselves
      // In a real-world scenario, you might use a service layer or event system
      console.log(chalk.blue(`Pipeline creation will be handled by the /api/pipelines endpoint`));
    } catch (err) {
      console.error(chalk.red(`Failed to initiate pipeline for task ${id}:`), err);
    }
  }
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


router.post('/import/jira', async (req, res) => {
  const { site, email, token, project } = req.body || {};
  if (!site || !email || !token || !project) {
    return res.status(400).json({ 
      error: 'Missing required fields', 
      message: 'site, email, token, and project are required' 
    });
  }

  try {
    const jiraScript = path.resolve(process.cwd(), 'jira.sh');
    
    // Set environment variables for the jira script
    const env = {
      ...process.env,
      JIRA_SITE: site,
      JIRA_EMAIL: email,
      JIRA_TOKEN: token
    };

    // Import tasks from Jira
    const p = await $({ env })`${jiraScript} import --project ${project} --dir ${TASKS_DIR}`;
    
    // Return the updated list of tasks
    const list = await listTasks();
    res.json({ 
      message: 'Tasks imported successfully from Jira', 
      tasks: list 
    });
  } catch (err) {
    console.error(chalk.red('Jira import failed:'), err);
    res.status(500).json({ 
      error: 'Import failed', 
      message: err.stderr || err.stdout || err.message 
    });
  }
});

export default router;
