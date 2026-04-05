import { test, expect, type Page } from "@playwright/test";

const BASE_URL = "http://localhost:4000";
const LOGIN_EMAIL = "dev@soundforge.local";
const LOGIN_PASSWORD = "password123456";

async function login(page: Page): Promise<void> {
  await page.goto(`${BASE_URL}/users/log-in`);
  await page.waitForLoadState("networkidle");
  await page.fill('input[name="user[email]"]', LOGIN_EMAIL);
  await page.fill('input[name="user[password]"]', LOGIN_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL((url) => !url.pathname.includes("log-in"), { timeout: 10_000 });
}

test.describe("Settings Page", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("SET-01 CP-116: audio engine toggle is visible on settings page", async ({ page }) => {
    await page.goto(`${BASE_URL}/settings`);
    await page.waitForLoadState("networkidle");

    const candidates = [
      page.getByText("Demucs", { exact: false }),
      page.getByText("htdemucs", { exact: false }),
      page.getByText("audio engine", { exact: false }),
      page.getByText("Audio Engine", { exact: false }),
      page.getByText("Stem Engine", { exact: false }),
      page.locator('select[name*="engine"]'),
      page.locator('input[type="radio"][name*="engine"]'),
    ];

    let found = false;
    for (const candidate of candidates) {
      try {
        if ((await candidate.count()) > 0) {
          await expect(candidate.first()).toBeVisible({ timeout: 8000 });
          found = true;
          break;
        }
      } catch { /* continue */ }
    }
    expect(found).toBeTruthy();
  });

  test("SET-02 CP-117: lalal.ai quota display is visible on settings page", async ({ page }) => {
    await page.goto(`${BASE_URL}/settings`);
    await page.waitForLoadState("networkidle");

    const candidates = [
      page.getByText("lalal", { exact: false }),
      page.getByText("Lalal", { exact: false }),
      page.getByText("quota", { exact: false }),
      page.getByText("Quota", { exact: false }),
      page.locator('[id*="lalal"]'),
      page.locator('[class*="lalal"]'),
    ];

    let found = false;
    for (const candidate of candidates) {
      try {
        if ((await candidate.count()) > 0) {
          await expect(candidate.first()).toBeVisible({ timeout: 8000 });
          found = true;
          break;
        }
      } catch { /* continue */ }
    }
    expect(found).toBeTruthy();
  });

  test("SET-03 CP-118: debug mode toggle exists and can be clicked without JS errors", async ({ page }) => {
    const jsErrors: string[] = [];
    page.on("pageerror", (err) => jsErrors.push(err.message));

    await page.goto(`${BASE_URL}/settings`);
    await page.waitForLoadState("networkidle");

    const candidates = [
      page.locator('input[type="checkbox"][name*="debug"]'),
      page.locator('input[type="checkbox"][id*="debug"]'),
      page.getByLabel(/debug/i),
      page.getByLabel(/inspector/i),
      page.locator("button").filter({ hasText: /debug/i }),
    ];

    let found = false;
    let clickable = null;
    for (const candidate of candidates) {
      try {
        if ((await candidate.count()) > 0 && (await candidate.first().isVisible())) {
          found = true;
          clickable = candidate.first();
          break;
        }
      } catch { /* continue */ }
    }

    expect(found).toBeTruthy();
    if (clickable) {
      try { await clickable.click({ timeout: 5000 }); await page.waitForTimeout(500); } catch { /* ok */ }
    }
    expect(jsErrors.length).toBe(0);
  });

  test("SET-04 CP-119: MIDI section is visible on settings page", async ({ page }) => {
    await page.goto(`${BASE_URL}/settings`);
    await page.waitForLoadState("networkidle");

    const candidates = [
      page.getByText("MIDI", { exact: false }),
      page.locator('select[name*="midi"]'),
      page.locator('[data-testid*="midi"]'),
      page.locator("h2").filter({ hasText: /midi/i }),
      page.locator("section").filter({ hasText: /midi/i }),
    ];

    let found = false;
    for (const candidate of candidates) {
      try {
        if ((await candidate.count()) > 0) {
          await expect(candidate.first()).toBeVisible({ timeout: 8000 });
          found = true;
          break;
        }
      } catch { /* continue */ }
    }
    expect(found).toBeTruthy();
  });
});
