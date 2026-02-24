import fs from 'fs-extra';
import path from 'node:path';

const getDataDir = () => process.env.DATA_DIR || '/tmp/ai-coding-factory';

export const getPipelinesDir = () => path.join(getDataDir(), 'pipelines');

export const pipelinePath = (pipelineId) => path.join(getPipelinesDir(), `${pipelineId}.json`);

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
