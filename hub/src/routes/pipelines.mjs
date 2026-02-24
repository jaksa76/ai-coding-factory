import express from 'express';
import { $, chalk } from 'zx';
import path from 'node:path';

const router = express.Router();

const getDataDir = () => process.env.DATA_DIR || '/tmp/ai-coding-factory';

export const getPipelinesDir = () => path.join(getDataDir(), 'pipelines');

export const pipelinePath = (pipelineId) => path.join(getPipelinesDir(), `${pipelineId}.json`);

// Ensure zx doesn't print commands in tests unless DEBUG
$.verbose = !!process.env.DEBUG;

// Per-taskId locks to serialize concurrent POSTs so each gets a unique number
const _locks = new Map();

export const createPipeline = async (record) => {
  await fs.ensureDir(getPipelinesDir());
  await fs.outputJSON(pipelinePath(record.id), record, { spaces: 2 });
};

export const getPipeline = async (pipelineId) => {
  const file = pipelinePath(pipelineId);
  if (!(await fs.pathExists(file))) return null;
  return fs.readJSON(file);
};

export const listPipelines = async (taskId) => {
  await fs.ensureDir(getPipelinesDir());
  const files = await fs.readdir(getPipelinesDir());
  const results = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    if (taskId && !f.startsWith(`${taskId}_pipeline_`)) continue;
    try {
      const record = await fs.readJSON(path.join(getPipelinesDir(), f));
      results.push(record);
    } catch {}
  }
  return results;
};

export const updatePipeline = async (pipelineId, fields) => {
  const file = pipelinePath(pipelineId);
  const current = await fs.readJSON(file);
  const updated = { ...current, ...fields };
  await fs.outputJSON(file, updated, { spaces: 2 });
  return updated;
};

export const upsertStage = async (pipelineId, position, stageData) => {
  const file = pipelinePath(pipelineId);
  const record = await fs.readJSON(file);
  const stages = record.stages || [];
  stages[position] = { ...stageData };
  record.stages = stages;
  await fs.outputJSON(file, record, { spaces: 2 });
  return record;
};


// Allocate a pipeline ID and write the initial record atomically under a per-taskId lock
const allocatePipeline = async (taskId, record) => {
  const prev = _locks.get(taskId) ?? Promise.resolve();
  let resolve;
  const next = new Promise((r) => { resolve = r; });
  _locks.set(taskId, next);
  try {
    await prev;
    const existing = await pipelinesStore.listPipelines(taskId);
    const numbers = existing
      .map(p => {
        const match = p.id.match(new RegExp(`${taskId}_pipeline_(\\d+)$`));
        return match ? parseInt(match[1]) : 0;
      })
      .filter(n => n > 0);
    const nextNum = numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
    const pipelineId = `${taskId}_pipeline_${nextNum}`;
    await pipelinesStore.createPipeline({ ...record, id: pipelineId });
    return pipelineId;
  } finally {
    resolve();
  }
};

// GET /pipelines?task=<task_id> - List all pipelines for a task
router.get('/', async (req, res) => {
  try {
    const taskId = req.query.task;
    if (!taskId) {
      return res.status(400).json({ error: 'Missing task parameter', message: 'task query parameter is required' });
    }
    const pipelines = await pipelinesStore.listPipelines(taskId);
    res.json(pipelines);
  } catch (error) {
    console.error('Error listing pipelines:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to list pipelines' });
  }
});

// GET /pipelines/:pipelineId - Get a single pipeline record
router.get('/:pipelineId', async (req, res) => {
  try {
    const pipeline = await pipelinesStore.getPipeline(req.params.pipelineId);
    if (!pipeline) return res.status(404).json({ error: 'Pipeline not found' });
    res.json(pipeline);
  } catch (error) {
    console.error('Error getting pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to get pipeline' });
  }
});

// POST /pipelines - Create and start a new pipeline for a task
router.post('/', async (req, res) => {
  try {
    const { taskId, description, gitUrl, gitUsername, gitToken, mockMode, mockScript } = req.body || {};

    if (!taskId) {
      return res.status(400).json({ error: 'Missing required field', message: 'taskId is required' });
    }

    if (!description) {
      return res.status(400).json({ error: 'Missing required field', message: 'description is required' });
    }

    const pipelineId = await allocatePipeline(taskId, {
      taskId,
      status: 'pending',
      createdAt: new Date().toISOString(),
      stages: [],
    });

    console.log(chalk.green(`Starting pipeline ${pipelineId} for task ${taskId}...`));

    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const args = ['start', '--task-id', taskId, '--pipeline-id', pipelineId, '--task-description', description];

      if (gitUrl) args.push('--git-url', gitUrl);
      if (gitUsername) args.push('--git-username', gitUsername);
      if (gitToken) args.push('--git-token', gitToken);

      await $({ env: { ...process.env, MOCK_MODE: mockMode || '', MOCK_SCRIPT: mockScript || '' } })`${pipelineScript} ${args}`;

      await pipelinesStore.updatePipeline(pipelineId, { status: 'running' });

      res.status(201).json(await pipelinesStore.getPipeline(pipelineId));
    } catch (err) {
      console.error(chalk.red(`Pipeline ${pipelineId} failed to start:`), err);
      res.status(500).json({
        error: 'Pipeline start failed',
        message: 'Failed to start pipeline',
      });
    }
  } catch (error) {
    console.error('Error creating pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to create pipeline' });
  }
});

// PUT /pipelines/:pipelineId - Update pipeline status (agent write-back)
router.put('/:pipelineId', async (req, res) => {
  try {
    const { pipelineId } = req.params;
    const pipeline = await pipelinesStore.getPipeline(pipelineId);
    if (!pipeline) return res.status(404).json({ error: 'Pipeline not found' });
    const updated = await pipelinesStore.updatePipeline(pipelineId, req.body);
    res.json(updated);
  } catch (error) {
    console.error('Error updating pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to update pipeline' });
  }
});

// PUT /pipelines/:pipelineId/stages/:position - Upsert a stage (agent write-back)
router.put('/:pipelineId/stages/:position', async (req, res) => {
  try {
    const { pipelineId } = req.params;
    const position = parseInt(req.params.position);
    if (isNaN(position)) {
      return res.status(400).json({ error: 'Invalid position', message: 'Stage position must be a number' });
    }
    const pipeline = await pipelinesStore.getPipeline(pipelineId);
    if (!pipeline) return res.status(404).json({ error: 'Pipeline not found' });
    const updated = await pipelinesStore.upsertStage(pipelineId, position, req.body);
    res.json(updated);
  } catch (error) {
    console.error('Error upserting stage:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to upsert stage' });
  }
});

// POST /pipelines/:pipelineId/stop - Stop a running pipeline
router.post('/:pipelineId/stop', async (req, res) => {
  try {
    const pipelineId = req.params.pipelineId;

    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }

    const taskId = taskIdMatch[1];

    console.log(chalk.yellow(`Stopping pipeline ${pipelineId}...`));

    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      await $`${pipelineScript} stop --task-id ${taskId} --pipeline-id ${pipelineId}`;

      await pipelinesStore.updatePipeline(pipelineId, { status: 'stopped' });

      res.json(await pipelinesStore.getPipeline(pipelineId));
    } catch (err) {
      console.error(chalk.red(`Failed to stop pipeline ${pipelineId}:`), err);
      res.status(500).json({
        error: 'Stop failed',
        message: 'Failed to stop pipeline',
        details: err.stderr || err.message,
      });
    }
  } catch (error) {
    console.error('Error stopping pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to stop pipeline' });
  }
});

// GET /pipelines/:pipelineId/status - Get the live status of a pipeline
router.get('/:pipelineId/status', async (req, res) => {
  try {
    const pipelineId = req.params.pipelineId;

    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }

    const taskId = taskIdMatch[1];

    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const p = await $`${pipelineScript} status --task-id ${taskId} --pipeline-id ${pipelineId}`;
      res.setHeader('Content-Type', 'text/plain');
      res.send(p.stdout);
    } catch (err) {
      res.status(500).setHeader('Content-Type', 'text/plain').send(err.stderr || err.stdout);
    }
  } catch (error) {
    console.error('Error getting pipeline status:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to get pipeline status' });
  }
});

// GET /pipelines/:pipelineId/logs - Fetch logs for a pipeline
router.get('/:pipelineId/logs', async (req, res) => {
  try {
    const pipelineId = req.params.pipelineId;

    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }

    const taskId = taskIdMatch[1];

    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const p = await $`${pipelineScript} logs --task-id ${taskId} --pipeline-id ${pipelineId}`;
      res.setHeader('Content-Type', 'text/plain');
      res.send(p.stdout);
    } catch (err) {
      res.status(500).setHeader('Content-Type', 'text/plain').send(err.stderr || err.stdout);
    }
  } catch (error) {
    console.error('Error getting pipeline logs:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to get pipeline logs' });
  }
});

export default router;
