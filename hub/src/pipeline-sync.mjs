import { $ } from 'zx';
import path from 'node:path';
import { chalk } from 'zx';
import * as pipelinesStore from './pipelines-store.mjs';

$.verbose = !!process.env.DEBUG;

const pipelineScript = path.resolve(process.cwd(), 'pipelines.sh');

function dockerStatusToPipelineStatus(dockerStatus, exitCode) {
  if (dockerStatus === 'exited') return exitCode === 0 ? 'completed' : 'failed';
  if (dockerStatus === 'dead') return 'failed';
  return null; // running or unknown — don't touch
}

async function syncPipeline(pipeline) {
  const { id: pipelineId, taskId } = pipeline;
  try {
    let stdout;
    try {
      const result = await $`${pipelineScript} status --task-id ${taskId} --pipeline-id ${pipelineId}`;
      stdout = result.stdout;
    } catch (err) {
      stdout = err.stdout || '';
    }

    const data = JSON.parse(stdout);

    if (data.error) {
      console.log(chalk.yellow(`Pipeline sync: ${pipelineId} container not found — marking failed`));
      await pipelinesStore.updatePipeline(pipelineId, { status: 'failed' });
      return;
    }

    const exitCode = data.details?.[0]?.State?.ExitCode ?? -1;
    const newStatus = dockerStatusToPipelineStatus(data.status, exitCode);

    if (newStatus) {
      console.log(chalk.blue(`Pipeline sync: ${pipelineId} docker=${data.status} exit=${exitCode} → ${newStatus}`));
      await pipelinesStore.updatePipeline(pipelineId, { status: newStatus });
    }
  } catch (err) {
    console.error(chalk.red(`Pipeline sync error for ${pipelineId}:`), err.message);
  }
}

export function startPipelineSync(intervalMs = 10_000) {
  const run = async () => {
    try {
      const all = await pipelinesStore.listPipelines();
      const running = all.filter(p => p.status === 'running');
      if (running.length > 0) {
        await Promise.all(running.map(syncPipeline));
      }
    } catch (err) {
      console.error(chalk.red('Pipeline sync loop error:'), err.message);
    }
  };

  const id = setInterval(run, intervalMs);
  id.unref(); // don't prevent clean process exit
  console.log(chalk.green(`Pipeline sync started (every ${intervalMs / 1000}s)`));
  return id;
}
