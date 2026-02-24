import { test, expect } from '@playwright/test';

/**
 * End-to-end test that exercises the full pipeline lifecycle:
 *   create task → start pipeline → wait for all stages → verify completion
 *
 * Requires a fully configured hub (running with .env credentials) and a
 * working coding-pipeline Docker image. The pipeline makes a real commit /
 * pull-request to the configured Git repository.
 *
 * Run with: npm run test:e2e -- e2e/pipeline-run.spec.js
 */

test('should run a pipeline that ticks the first unchecked TODO item in the dummy project', async ({ page, request }) => {
  test.setTimeout(600_000); // 10 minutes – real coding agent takes time

  const taskDescription =
    'In TODO.md find the first item that is still unchecked (marked `[ ]`) ' +
    'and mark it as done by changing `[ ]` to `[x]`. ' +
    'Commit the change and open a pull request.';

  // ── 1. Create task via the Tasks UI ──────────────────────────────────────
  await page.goto('/');
  await page.click('#btnAdd');
  await page.fill('#taskDescription', taskDescription);
  await page.click('#btnCreate');
  await expect(page.locator('.msg.success')).toContainText('Task created');

  const taskRow = page.locator('table.table tbody tr', { hasText: 'first item that is still unchecked' });
  await expect(taskRow).toBeVisible();
  const taskId = (await taskRow.locator('.col-id').textContent()).trim();

  // ── 2. Start the pipeline via the UI ─────────────────────────────────────
  await taskRow.locator('[aria-label="Start Pipeline"]').click();
  await expect(page.locator('.msg.success')).toContainText('Pipeline started');

  // ── 3. Navigate to pipeline details ──────────────────────────────────────
  // Re-query the row since clicking Start re-renders it
  const taskRowAfter = page.locator('table.table tbody tr', { hasText: 'first item that is still unchecked' });
  await taskRowAfter.locator('[aria-label="Details"]').click();
  await expect(page).toHaveURL(/pipeline\.html/);

  // Wait for the pipeline list to load and the selector to show the pipeline
  await expect(page.locator('#pipeline-select')).not.toBeDisabled({ timeout: 15_000 });
  const pipelineId = await page.locator('#pipeline-select').inputValue();
  expect(pipelineId).toBeTruthy();

  // ── 4. Poll hub API until the pipeline reaches a terminal state ───────────
  await expect(async () => {
    const res = await request.get(`/api/pipelines/${encodeURIComponent(pipelineId)}`);
    const pipeline = await res.json();
    expect(['completed', 'failed']).toContain(pipeline.status);
  }).toPass({ timeout: 590_000, intervals: [10_000] });

  // ── 5. Assert the pipeline completed successfully (not failed) ────────────
  const finalRes = await request.get(`/api/pipelines/${encodeURIComponent(pipelineId)}`);
  const finalPipeline = await finalRes.json();
  expect(finalPipeline.status, `Pipeline ended with status "${finalPipeline.status}"`).toBe('completed');

  // ── 6. Verify the pipeline page still shows the correct pipeline ──────────
  await page.reload();
  await expect(page.locator('#pipeline-select')).not.toBeDisabled({ timeout: 15_000 });
  await expect(page.locator('#pipeline-select')).toHaveValue(pipelineId);

  // ── 7. Verify the pipeline actually executed all stages via the logs ───────
  //    The pipeline image logs "Starting stage: <name>" for each stage it runs.
  const logsRes = await request.get(`/api/pipelines/${encodeURIComponent(pipelineId)}/logs`);
  expect(logsRes.status()).toBe(200);
  const logs = await logsRes.text();
  expect(logs).toContain('Starting stage: cloning');
  expect(logs).toContain('Starting stage: planning');
  expect(logs).toContain('Starting stage: implementing');
  expect(logs).toContain('Starting stage: verifying');

  // ── 8. Verify the logs are also visible in the pipeline details UI ─────────
  const logSection = page.locator('#logs pre.log-output');
  await expect(logSection).toBeVisible({ timeout: 10_000 });
  await expect(logSection).toContainText('Starting stage:');

  // ── 9. Cleanup ────────────────────────────────────────────────────────────
  await request.delete(`/api/tasks/${taskId}`);
});
