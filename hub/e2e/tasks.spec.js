import { test, expect } from '@playwright/test';

test.describe('Tasks Page', () => {
  async function createTask(request, description) {
    const res = await request.post('/api/tasks', { data: { description } });
    return res.json();
  }

  async function deleteTask(request, taskId) {
    await request.delete(`/api/tasks/${taskId}`);
  }

  async function waitForTasksLoaded(page) {
    // Wait for the loading placeholder inside #tasks to disappear
    await page.waitForSelector('#tasks .loading', { state: 'detached', timeout: 10000 }).catch(() => {});
  }

  test('should display the tasks page with correct title and elements', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/AI Coding Factory Hub/);
    await expect(page.locator('h1.page-title')).toHaveText('Tasks');
    await expect(page.locator('.brand-name')).toContainText('AI Coding Factory Hub');
    await expect(page.locator('#btnAdd')).toBeVisible();
    await expect(page.locator('#btnImportJira')).toBeVisible();
    await expect(page.locator('#btnRefresh')).toBeVisible();
    await expect(page.locator('#search')).toBeVisible();
    await expect(page.locator('#statusFilter')).toBeVisible();
  });

  test('should show and hide the Add Task form', async ({ page }) => {
    await page.goto('/');
    const form = page.locator('#taskForm');

    await expect(form).toBeHidden();

    await page.click('#btnAdd');
    await expect(form).toBeVisible();
    await expect(page.locator('#taskDescription')).toBeFocused();

    await page.click('#btnCancel');
    await expect(form).toBeHidden();
    await expect(page.locator('#taskDescription')).toHaveValue('');
  });

  test('should show error when creating task with empty description', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnAdd');
    await page.click('#btnCreate');
    await expect(page.locator('.msg.error')).toContainText('Please enter a description');
  });

  test('should create a new task and display it in the list', async ({ page, request }) => {
    const description = `Playwright E2E test task ${Date.now()}`;
    await page.goto('/');

    await page.click('#btnAdd');
    await page.fill('#taskDescription', description);
    await page.click('#btnCreate');

    await expect(page.locator('.msg.success')).toContainText('Task created');
    await expect(page.locator('#taskForm')).toBeHidden();

    const taskRow = page.locator('table.table tbody tr', { hasText: description });
    await expect(taskRow).toBeVisible();
    await expect(taskRow.locator('.col-id')).not.toBeEmpty();
    await expect(taskRow.locator('.status')).toContainText('pending');

    const taskId = await taskRow.locator('.col-id').textContent();
    await deleteTask(request, taskId.trim());
  });

  test('should search tasks by description', async ({ page, request }) => {
    const uniqueTerm = `searchtest-${Date.now()}`;
    const task = await createTask(request, `Task with ${uniqueTerm} in it`);

    await page.goto('/');
    await waitForTasksLoaded(page);

    await page.fill('#search', uniqueTerm);
    await expect(page.locator('table.table tbody tr', { hasText: uniqueTerm })).toBeVisible();

    await page.fill('#search', 'NOMATCH_XXXXXXXXXXX');
    await expect(page.locator('#tasks .empty')).toContainText('No tasks match');

    await deleteTask(request, task.id);
  });

  test('should filter tasks by status', async ({ page, request }) => {
    const description = `Status filter test task ${Date.now()}`;
    const task = await createTask(request, description);

    await page.goto('/');
    await waitForTasksLoaded(page);

    await page.selectOption('#statusFilter', 'pending');
    await expect(page.locator('table.table tbody tr', { hasText: description })).toBeVisible();

    await page.selectOption('#statusFilter', 'completed');
    await expect(page.locator('table.table tbody tr', { hasText: description })).not.toBeVisible();

    await page.selectOption('#statusFilter', '');

    await deleteTask(request, task.id);
  });

  test('should delete a task', async ({ page, request }) => {
    const description = `Delete test task ${Date.now()}`;
    await createTask(request, description);

    await page.goto('/');
    await waitForTasksLoaded(page);

    const taskRow = page.locator('table.table tbody tr', { hasText: description });
    await expect(taskRow).toBeVisible();

    page.once('dialog', dialog => dialog.accept());
    await taskRow.locator('[aria-label="Delete"]').click();

    await expect(taskRow).not.toBeVisible();
    await expect(page.locator('.msg.success')).toContainText('Task deleted');
  });

  test('should open Jira import modal', async ({ page }) => {
    await page.goto('/');

    await page.click('#btnImportJira');

    const modal = page.locator('#jiraModal');
    await expect(modal).toBeVisible();
    await expect(page.locator('.modal-title')).toContainText('Import Tasks from Jira');
    await expect(page.locator('#jiraSite')).toBeVisible();
    await expect(page.locator('#jiraEmail')).toBeVisible();
    await expect(page.locator('#jiraToken')).toBeVisible();
    await expect(page.locator('#jiraProject')).toBeVisible();
    await expect(page.locator('#jiraSite')).toBeFocused();
  });

  test('should close Jira modal with Cancel button', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnImportJira');
    await expect(page.locator('#jiraModal')).toBeVisible();

    await page.click('#jiraModalCancel');
    await expect(page.locator('#jiraModal')).toBeHidden();
  });

  test('should close Jira modal with × button', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnImportJira');
    await expect(page.locator('#jiraModal')).toBeVisible();

    await page.click('#jiraModalClose');
    await expect(page.locator('#jiraModal')).toBeHidden();
  });

  test('should close Jira modal when clicking the backdrop', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnImportJira');
    await expect(page.locator('#jiraModal')).toBeVisible();

    // Click on the backdrop (top-left corner, outside the modal-content box)
    await page.locator('#jiraModal').click({ position: { x: 10, y: 10 } });
    await expect(page.locator('#jiraModal')).toBeHidden();
  });

  test('should show error when Jira import fields are empty', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnImportJira');
    await page.click('#jiraModalImport');
    await expect(page.locator('.msg.error')).toContainText('Please fill in all Jira configuration fields');
  });

  test('should open task form with Ctrl+N keyboard shortcut', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#taskForm')).toBeHidden();

    await page.keyboard.press('Control+n');
    await expect(page.locator('#taskForm')).toBeVisible();
  });

  test('should close task form with Escape key', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnAdd');
    await expect(page.locator('#taskForm')).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(page.locator('#taskForm')).toBeHidden();
  });

  test('should close Jira modal with Escape key', async ({ page }) => {
    await page.goto('/');
    await page.click('#btnImportJira');
    await expect(page.locator('#jiraModal')).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(page.locator('#jiraModal')).toBeHidden();
  });

  test('should navigate to pipeline details page', async ({ page, request }) => {
    const description = `Navigation test task ${Date.now()}`;
    const task = await createTask(request, description);

    await page.goto('/');
    await waitForTasksLoaded(page);

    const taskRow = page.locator('table.table tbody tr', { hasText: description });
    await taskRow.locator('[aria-label="Details"]').click();

    await expect(page).toHaveURL(/pipeline\.html/);
    await expect(page.locator('h1.page-title')).toContainText('Pipeline Details');

    await deleteTask(request, task.id);
  });

  test('should refresh task list when Refresh button is clicked', async ({ page, request }) => {
    await page.goto('/');
    await waitForTasksLoaded(page);

    const description = `Refresh test task ${Date.now()}`;
    const task = await createTask(request, description);

    await page.click('#btnRefresh');
    await waitForTasksLoaded(page);

    await expect(page.locator('table.table tbody tr', { hasText: description })).toBeVisible();

    await deleteTask(request, task.id);
  });

  test('should show Start Pipeline button for pending tasks', async ({ page, request }) => {
    const description = `Start pipeline button test ${Date.now()}`;
    const task = await createTask(request, description);

    await page.goto('/');
    await waitForTasksLoaded(page);

    const taskRow = page.locator('table.table tbody tr', { hasText: description });
    await expect(taskRow.locator('[aria-label="Start Pipeline"]')).toBeVisible();

    await deleteTask(request, task.id);
  });
});
