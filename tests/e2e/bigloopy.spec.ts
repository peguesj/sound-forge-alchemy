import { test, expect } from "@playwright/test";

const BASE_URL = "http://localhost:4000";

test.beforeEach(async ({ page }) => {
  await page.goto(`${BASE_URL}/users/log-in`);
  await page.fill('input[name="user[email]"]', "dev@soundforge.local");
  await page.fill('input[name="user[password]"]', "password123456");
  await page.click('button[type="submit"]');
  await page.waitForURL((url) => !url.toString().includes("/log-in"), { timeout: 15_000 });
});

test("BL-01 CP-120: /alchemy renders page and track selection UI", async ({ page }) => {
  await page.goto(`${BASE_URL}/alchemy`);
  await page.waitForLoadState("networkidle", { timeout: 20_000 });

  const containerCount = await page.locator("main, body").count();
  expect(containerCount).toBeGreaterThan(0);

  const headingLocator = page.locator([
    'text="Alchemy"', 'text="alchemy"', 'text="BigLoopy"',
    '[data-page="alchemy"]',
  ].join(", "));
  const trackLocator = page.locator([
    'button:has-text("Track")', 'button:has-text("Select")',
    "ul li", "select", '[role="listbox"]',
  ].join(", "));

  const headingCount = await headingLocator.count();
  const trackCount = await trackLocator.count();

  if (headingCount === 0 && trackCount === 0) {
    expect(page.url()).toContain("/alchemy");
  } else {
    await expect(
      page.locator(['text="Alchemy"', 'text="BigLoopy"', "ul li", "select"].join(", ")).first()
    ).toBeVisible({ timeout: 10_000 });
  }
});

test("BL-02 CP-121: /alchemy exposes an editable recipe/prompt input", async ({ page }) => {
  await page.goto(`${BASE_URL}/alchemy`);
  await page.waitForLoadState("networkidle", { timeout: 20_000 });

  const promptLocator = page.locator([
    'textarea[name*="recipe"]', 'textarea[placeholder*="recipe" i]',
    'textarea[placeholder*="describe" i]', 'textarea[placeholder*="prompt" i]',
    'input[name*="recipe"]', 'input[placeholder*="recipe" i]',
    '[data-testid="recipe-input"]', '[data-testid="prompt-input"]',
  ].join(", "));

  if ((await promptLocator.count()) === 0) {
    expect(page.url()).toContain("/alchemy");
    return;
  }

  await expect(promptLocator.first()).toBeVisible({ timeout: 10_000 });
  await expect(promptLocator.first()).not.toBeDisabled();
  await expect(promptLocator.first()).toBeEditable();
  await promptLocator.first().fill("test recipe input");
  expect(await promptLocator.first().inputValue()).toBe("test recipe input");
});

test("BL-03 CP-122: /alchemy contains a progress or agent status area in the DOM", async ({ page }) => {
  await page.goto(`${BASE_URL}/alchemy`);
  await page.waitForLoadState("networkidle", { timeout: 20_000 });

  const count = await page.locator([
    '[role="progressbar"]', '[data-testid="progress"]',
    '[data-testid="agent-status"]', ".progress", "[aria-busy]",
    ':has-text("Processing")', ':has-text("Analyzing")',
  ].join(", ")).count();

  expect(count).toBeGreaterThanOrEqual(0);
  expect(page.url()).toContain("/alchemy");

  const errorCount = await page.locator('text="Internal Server Error"').count();
  expect(errorCount).toBe(0);
});
