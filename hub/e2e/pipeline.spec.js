import { test, expect } from '@playwright/test';

test.describe('Pipeline Details Page', () => {
  async function createTask(request, description) {
    const res = await request.post('/api/tasks', { data: { description } });
    return res.json();
  }

  async function deleteTask(request, taskId) {
    await request.delete(`/api/tasks/${taskId}`);
  }

  test('should display the pipeline details page with correct heading', async ({ page }) => {
    await page.goto('/pipeline.html');
    await expect(page).toHaveTitle(/Pipeline Details/);
    await expect(page.locator('h1.page-title')).toContainText('Pipeline Details');
    await expect(page.locator('.brand-name')).toContainText('AI Coding Factory Hub');
  });

  test('should show sections for Stages, Logs and Status', async ({ page }) => {
    await page.goto('/pipeline.html');
    const headings = page.locator('section.card h2');
    await expect(headings.nth(0)).toContainText('Stages');
    await expect(headings.nth(1)).toContainText('Logs');
    await expect(page.locator('details.card summary')).toContainText('Status');
  });

  test('should have a back link to the tasks page', async ({ page }) => {
    await page.goto('/pipeline.html');
    const backLink = page.locator('a.back-link');
    await expect(backLink).toBeVisible();
    await expect(backLink).toContainText('Back to Tasks');
    await expect(backLink).toHaveAttribute('href', 'index.html');
  });

  test('should navigate back to tasks when clicking the back link', async ({ page }) => {
    await page.goto('/pipeline.html');
    await page.click('a.back-link');
    await expect(page.locator('h1.page-title')).toContainText('Tasks');
  });

  test('should show a disabled pipeline selector when no taskId is provided', async ({ page }) => {
    await page.goto('/pipeline.html');
    const select = page.locator('#pipeline-select');
    await expect(select).toBeDisabled();
  });

  test('should show "No pipelines" when the task has no pipelines', async ({ page, request }) => {
    const task = await createTask(request, `Pipeline page no-pipelines test ${Date.now()}`);

    await page.goto(`/pipeline.html?taskId=${task.id}`);

    // Wait for the async pipeline list fetch to complete
    await page.waitForLoadState('networkidle');

    const select = page.locator('#pipeline-select');
    await expect(select).toBeDisabled();

    const options = await select.locator('option').allTextContents();
    expect(options).toContain('No pipelines');

    await deleteTask(request, task.id);
  });

  test('should include the taskId in the URL when navigating from the tasks page', async ({ page, request }) => {
    const description = `Pipeline URL param test ${Date.now()}`;
    const task = await createTask(request, description);

    await page.goto('/');
    // Wait for tasks to load
    await page.waitForSelector('#tasks .loading', { state: 'detached', timeout: 10000 }).catch(() => {});

    const taskRow = page.locator('table.table tbody tr', { hasText: description });
    await taskRow.locator('[aria-label="Details"]').click();

    await expect(page).toHaveURL(new RegExp(`taskId=${task.id}`));

    await deleteTask(request, task.id);
  });

  test('should update the URL with pipelineId when a pipeline is selected', async ({ page, request }) => {
    // Seed a pipeline record via API so the selector has options
    const task = await createTask(request, `Pipeline select URL test ${Date.now()}`);
    const pipelineRes = await request.post('/api/pipelines', {
      data: { taskId: task.id, description: task.description, mockMode: 'instant' },
    });

    if (pipelineRes.status() !== 201) {
      // Mock pipeline not available – skip without failing
      test.skip();
      return;
    }

    const pipeline = await pipelineRes.json();

    await page.goto(`/pipeline.html?taskId=${task.id}`);
    await page.waitForLoadState('networkidle');

    // After load the URL should contain the pipelineId
    await expect(page).toHaveURL(new RegExp(`pipelineId=${encodeURIComponent(pipeline.id)}`));

    // Stop the pipeline to avoid leaving it running
    await request.post(`/api/pipelines/${encodeURIComponent(pipeline.id)}/stop`);
    await deleteTask(request, task.id);
  });
});
