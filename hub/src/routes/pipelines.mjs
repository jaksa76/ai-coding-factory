import express from 'express';
import { $, chalk } from 'zx';
import fs from 'fs-extra';
import path from 'node:path';

const getDataDir = () => process.env.DATA_DIR || '/tmp/ai-coding-factory';
const getPipelinesDir = () => path.join(getDataDir(), 'pipelines');

// Ensure directory exists when functions are called, not at module level
const ensurePipelinesDir = async () => {
  await fs.ensureDir(getPipelinesDir());
};

const pipelinePath = (id) => path.join(getPipelinesDir(), `${id}.json`);
const readJSON = (file) => fs.readJSON(file);
const writeJSON = (file, data) => fs.outputJSON(file, data, { spaces: 2 });

const listPipelines = async (taskId = null) => {
  await ensurePipelinesDir();
  const PIPELINES_DIR = getPipelinesDir();
  
  const files = await fs.readdir(PIPELINES_DIR);
  const jsons = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    const full = path.join(PIPELINES_DIR, f);
    try {
      const pipeline = await fs.readJSON(full);
      if (!taskId || pipeline.taskId === taskId) {
        jsons.push(pipeline);
      }
    } catch {}
  }
  // Sort by creation time, most recent first
  return jsons.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
};

// Alternative implementation using pipelines.sh script
const listPipelinesViaScript = async (taskId = null) => {
  try {
    const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
    const args = ['list', '--format', 'json'];
    
    if (taskId) {
      args.push('--task-id', taskId);
    }
    
    const result = await $`${pipelineScript} ${args}`;
    const pipelines = JSON.parse(result.stdout);
    
    // Sort by creation time, most recent first (same as the file-based version)
    return pipelines.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  } catch (error) {
    console.error('Error listing pipelines via script:', error);
    // Fallback to the file-based implementation
    return await listPipelines(taskId);
  }
};

const generatePipelineId = async (taskId) => {
  // Get existing pipelines for this task to determine next sequential number
  const existingPipelines = await listPipelines(taskId);
  const pipelineNumbers = existingPipelines
    .map(p => {
      const match = p.id.match(new RegExp(`${taskId}_pipeline_(\\d+)`));
      return match ? parseInt(match[1]) : 0;
    })
    .filter(num => !isNaN(num));
  
  const nextNumber = pipelineNumbers.length > 0 ? Math.max(...pipelineNumbers) + 1 : 1;
  return `${taskId}_pipeline_${nextNumber}`;
};

const router = express.Router();

// Ensure zx doesn't print commands in tests unless DEBUG
$.verbose = !!process.env.DEBUG;

// GET /pipelines?task=<task_id> - List all pipelines for a task
router.get('/', async (req, res) => {
  try {
    const taskId = req.query.task;
    // Use shell script implementation for better consistency with command-line tools
    const pipelines = await listPipelinesViaScript(taskId);
    res.json(pipelines);
  } catch (error) {
    console.error('Error listing pipelines:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to list pipelines' });
  }
});

// GET /pipelines/:pipelineId - Get details of a specific pipeline
router.get('/:pipelineId', async (req, res) => {
  try {
    await ensurePipelinesDir();
    const pipelineId = req.params.pipelineId;
    const file = pipelinePath(pipelineId);
    
    if (await fs.pathExists(file)) {
      const pipeline = await readJSON(file);
      res.json(pipeline);
    } else {
      res.status(404).json({ error: 'Pipeline not found', message: 'Pipeline with specified ID does not exist' });
    }
  } catch (error) {
    console.error('Error getting pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to get pipeline details' });
  }
});

// POST /pipelines - Create and start a new pipeline for a task
router.post('/', async (req, res) => {
  try {
    await ensurePipelinesDir();
    const { taskId, description, gitUrl, gitUsername, gitToken } = req.body || {};
    
    if (!taskId) {
      return res.status(400).json({ error: 'Missing required field', message: 'taskId is required' });
    }
    
    if (!description) {
      return res.status(400).json({ error: 'Missing required field', message: 'description is required' });
    }

    // Check if task exists
    const TASKS_DIR = path.join(getDataDir(), 'tasks');
    const taskFile = path.join(TASKS_DIR, `${taskId}.json`);
    if (!(await fs.pathExists(taskFile))) {
      return res.status(404).json({ error: 'Task not found', message: 'Task with specified ID does not exist' });
    }

    // Stop any currently active pipeline for this task
    const existingPipelines = await listPipelines(taskId);
    const activePipeline = existingPipelines.find(p => p.status === 'running' || p.status === 'starting');
    
    if (activePipeline) {
      console.log(chalk.yellow(`Stopping active pipeline ${activePipeline.id} for task ${taskId}`));
      try {
        const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
        await $`${pipelineScript} stop --task-id ${taskId} --pipeline-id ${activePipeline.id}`;
        
        // Update pipeline status
        activePipeline.status = 'stopped';
        activePipeline.stoppedAt = new Date().toISOString();
        await writeJSON(pipelinePath(activePipeline.id), activePipeline);
      } catch (err) {
        console.error(chalk.red(`Failed to stop pipeline ${activePipeline.id}:`), err);
      }
    }

    // Generate new pipeline ID
    const pipelineId = await generatePipelineId(taskId);
    
    // Create pipeline metadata
    const pipeline = {
      id: pipelineId,
      taskId,
      description,
      status: 'starting',
      createdAt: new Date().toISOString(),
      containerName: `pipe-${pipelineId}`,
      volumeName: `vol-${pipelineId}`,
      gitUrl,
      gitUsername,
      gitToken: gitToken ? '[REDACTED]' : undefined // Don't store the actual token
    };

    // Save pipeline metadata
    await writeJSON(pipelinePath(pipelineId), pipeline);

    // Start the pipeline
    console.log(chalk.green(`Starting pipeline ${pipelineId} for task ${taskId}...`));
    
    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const args = ['start', '--task-id', taskId, '--pipeline-id', pipelineId, '--task-description', description];
      
      // Add git parameters if provided
      if (gitUrl) {
        args.push('--git-url', gitUrl);
      }
      if (gitUsername) {
        args.push('--git-username', gitUsername);
      }
      if (gitToken) {
        args.push('--git-token', gitToken);
      }
      
      const p = await $`${pipelineScript} ${args}`;
      
      // Update pipeline status to running
      pipeline.status = 'running';
      pipeline.startedAt = new Date().toISOString();
      await writeJSON(pipelinePath(pipelineId), pipeline);
      
      res.json(pipeline);
    } catch (err) {
      console.error(chalk.red(`Pipeline ${pipelineId} failed to start:`), err);
      
      // Update pipeline status to failed
      pipeline.status = 'failed';
      pipeline.error = err.stderr || err.message;
      await writeJSON(pipelinePath(pipelineId), pipeline);
      
      res.status(500).json({ 
        error: 'Pipeline start failed', 
        message: 'Failed to start pipeline',
        pipeline 
      });
    }
  } catch (error) {
    console.error('Error creating pipeline:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to create pipeline' });
  }
});

// POST /pipelines/:pipelineId/stop - Stop a running pipeline
router.post('/:pipelineId/stop', async (req, res) => {
  try {
    await ensurePipelinesDir();
    const pipelineId = req.params.pipelineId;
    const file = pipelinePath(pipelineId);
    
    if (!(await fs.pathExists(file))) {
      return res.status(404).json({ error: 'Pipeline not found', message: 'Pipeline with specified ID does not exist' });
    }

    const pipeline = await readJSON(file);
    
    if (pipeline.status !== 'running' && pipeline.status !== 'starting') {
      return res.status(400).json({ 
        error: 'Pipeline not running', 
        message: 'Pipeline is not currently running and cannot be stopped' 
      });
    }

    // Stop the pipeline
    console.log(chalk.yellow(`Stopping pipeline ${pipelineId}...`));
    
    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      await $`${pipelineScript} stop --task-id ${pipeline.taskId} --pipeline-id ${pipelineId}`;
      
      // Update pipeline status
      pipeline.status = 'stopped';
      pipeline.stoppedAt = new Date().toISOString();
      await writeJSON(file, pipeline);
      
      res.json(pipeline);
    } catch (err) {
      console.error(chalk.red(`Failed to stop pipeline ${pipelineId}:`), err);
      res.status(500).json({ 
        error: 'Stop failed', 
        message: 'Failed to stop pipeline',
        details: err.stderr || err.message
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
    await ensurePipelinesDir();
    const pipelineId = req.params.pipelineId;
    const file = pipelinePath(pipelineId);
    
    if (!(await fs.pathExists(file))) {
      return res.status(404).json({ error: 'Pipeline not found', message: 'Pipeline with specified ID does not exist' });
    }

    const pipeline = await readJSON(file);
    
    // Get live status from the pipeline script
    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const p = await $`${pipelineScript} status --task-id ${pipeline.taskId} --pipeline-id ${pipelineId}`;
      
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
    await ensurePipelinesDir();
    const pipelineId = req.params.pipelineId;
    const file = pipelinePath(pipelineId);
    
    if (!(await fs.pathExists(file))) {
      return res.status(404).json({ error: 'Pipeline not found', message: 'Pipeline with specified ID does not exist' });
    }

    const pipeline = await readJSON(file);
    
    // Get logs from the pipeline script
    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      const p = await $`${pipelineScript} logs --task-id ${pipeline.taskId} --pipeline-id ${pipelineId}`;
      
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