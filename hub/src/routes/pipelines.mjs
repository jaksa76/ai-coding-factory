import express from 'express';
import { $, chalk } from 'zx';
import path from 'node:path';

const router = express.Router();

// Ensure zx doesn't print commands in tests unless DEBUG
$.verbose = !!process.env.DEBUG;


const listPipelines = async (taskId) => {
  try {
    const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
    const result = await $`${pipelineScript} list --task-id ${taskId}`;
    // The agent scripts return container names in the form:
    //   pipe-<taskId>-<pipelineId>
    // We need to convert those to just the pipelineId (the part after the task prefix)
    return result.stdout
      .split('\n')
      .map(line => line.trim())
      .filter(line => line)
      .map(line => {
        const prefix = `pipe-${taskId}-`;
        if (line.startsWith(prefix)) return line.slice(prefix.length);
        // fallback: if the line is already a pipeline id, return as-is
        return line;
      });
  } catch (error) {
    console.error('Error listing pipelines via script:', error);
    return [];
  }
};

const generatePipelineId = async (taskId) => {
  // Get existing pipeline IDs (we return plain pipeline ids from listPipelines)
  const existingPipelines = await listPipelines(taskId);
  const pipelineNumbers = existingPipelines
    .map(pipelineId => {
      // Extract numbers from pipeline ids like "<taskId>_pipeline_1"
      const match = pipelineId.match(new RegExp(`${taskId}_pipeline_(\\d+)$`));
      return match ? parseInt(match[1]) : 0;
    })
    .filter(num => !isNaN(num) && num > 0);

  const nextNumber = pipelineNumbers.length > 0 ? Math.max(...pipelineNumbers) + 1 : 1;
  return `${taskId}_pipeline_${nextNumber}`;
};


// GET /pipelines?task=<task_id> - List all pipelines for a task
router.get('/', async (req, res) => {
  try {
    const taskId = req.query.task;
    if (!taskId) {
      return res.status(400).json({ error: 'Missing task parameter', message: 'task query parameter is required' });
    }
    
  const pipelines = await listPipelines(taskId);

  // Return objects with `id` to match API contract used in tests
  res.json(pipelines.map(id => ({ id })));
  } catch (error) {
    console.error('Error listing pipelines:', error);
    res.status(500).json({ error: 'Internal server error', message: 'Failed to list pipelines' });
  }
});


// POST /pipelines - Create and start a new pipeline for a task
router.post('/', async (req, res) => {
  try {
    const { taskId, description, gitUrl, gitUsername, gitToken } = req.body || {};
    
    if (!taskId) {
      return res.status(400).json({ error: 'Missing required field', message: 'taskId is required' });
    }
    
    if (!description) {
      return res.status(400).json({ error: 'Missing required field', message: 'description is required' });
    }

    const pipelineId = await generatePipelineId(taskId);
    
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
      
      await $`${pipelineScript} ${args}`;
            
      res.status(201).json({ 
        id: pipelineId
      });
    } catch (err) {
      console.error(chalk.red(`Pipeline ${pipelineId} failed to start:`), err);
      
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
    const pipelineId = req.params.pipelineId;
    
    // Extract task ID from pipeline ID (format: taskId_pipeline_N)
    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }
    
    const taskId = taskIdMatch[1];

    // Stop the pipeline
    console.log(chalk.yellow(`Stopping pipeline ${pipelineId}...`));
    
    try {
      const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');
      await $`${pipelineScript} stop --task-id ${taskId} --pipeline-id ${pipelineId}`;
      
      res.json({ 
        id: pipelineId
      });
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
    const pipelineId = req.params.pipelineId;
    
    // Extract task ID from pipeline ID (format: taskId_pipeline_N)
    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }
    
    const taskId = taskIdMatch[1];
    
    // Get live status from the pipeline script
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
    
    // Extract task ID from pipeline ID (format: taskId_pipeline_N)
    const taskIdMatch = pipelineId.match(/^(.+)_pipeline_\d+$/);
    if (!taskIdMatch) {
      return res.status(400).json({ error: 'Invalid pipeline ID format', message: 'Pipeline ID must be in format taskId_pipeline_N' });
    }
    
    const taskId = taskIdMatch[1];
    
    // Get logs from the pipeline script
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