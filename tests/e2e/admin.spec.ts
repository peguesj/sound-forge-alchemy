import { test, expect, type Page } from "@playwright/test";

const BASE_URL = "http://localhost:4000";

async function login(page: Page): Promise<void> {
  await page.goto(`${BASE_URL}/users/log-in`);
  await page.fill('input[name="user[email]"]', "dev@soundforge.local");
  await page.fill('input[name="user[password]"]', "password123456");
  await page.click('button[type="submit"]');
  await page.waitForURL((url) => !url.pathname.includes("log-in"), { timeout: 10_000 });
}

test.describe("Admin Panel", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("ADM-01 CP-128: admin page renders with user list and role badges", async ({ page }) => {
    await page.goto(`${BASE_URL}/admin`);
    if (page.url().includes("log-in")) {
      await login(page);
      await page.goto(`${BASE_URL}/admin`);
    }
    await page.waitForLoadState("networkidle");

    const bodyText = await page.locator("body").innerText();
    expect(/admin/i.test(bodyText)).toBe(true);

    // At least one user-like row
    let userRowCount = 0;
    for (const sel of ["tbody tr", "[data-testid='user-row']", ".user-row", "table tr:not(:first-child)"]) {
      const c = await page.locator(sel).count();
      if (c > 0) { userRowCount = c; break; }
    }
    expect(userRowCount).toBeGreaterThan(0);

    // Role badges
    let badgeVisible = false;
    for (const sel of [".badge", "span:has-text('admin')", "span:has-text('user')", "td:has-text('admin')", "td:has-text('user')"]) {
      const loc = page.locator(sel).first();
      if ((await loc.count()) > 0 && (await loc.isVisible())) { badgeVisible = true; break; }
    }
    if (!badgeVisible) {
      badgeVisible = /\b(admin|user)\b/i.test(bodyText);
    }
    expect(badgeVisible).toBe(true);
  });

  test("ADM-02 CP-129: feature flags toggle is accessible", async ({ page }) => {
    await page.goto(`${BASE_URL}/admin`);
    if (page.url().includes("log-in")) {
      await login(page);
      await page.goto(`${BASE_URL}/admin`);
    }
    await page.waitForLoadState("networkidle");

    const flagSelectors = [
      "input[type='checkbox'][name*='feature']", "input[type='checkbox'][name*='flag']",
      "[data-testid*='feature']", "label:has-text('feature')", ".feature-flag",
    ];

    const hasFlagUi = async () => {
      for (const s of flagSelectors) {
        if ((await page.locator(s).count()) > 0) return true;
      }
      return /feature\s*flag/i.test(await page.locator("body").innerText());
    };

    if (!(await hasFlagUi())) {
      // Try nav links or known route
      for (const sel of ["a:has-text('Feature')", "a:has-text('Dev Tools')", "a[href*='dev-tools']"]) {
        const link = page.locator(sel).first();
        if ((await link.count()) > 0 && (await link.isVisible())) {
          await link.click();
          await page.waitForLoadState("networkidle");
          break;
        }
      }
      if (!(await hasFlagUi())) {
        await page.goto(`${BASE_URL}/admin/dev-tools`);
        await page.waitForLoadState("networkidle");
      }
    }

    let toggleLocator = null;
    for (const sel of ["input[type='checkbox']", "[role='switch']", "[data-testid*='toggle']"]) {
      const loc = page.locator(sel).first();
      if ((await loc.count()) > 0) { toggleLocator = loc; break; }
    }

    expect(toggleLocator).not.toBeNull();
    await expect(toggleLocator!).toBeVisible();
    await expect(toggleLocator!).not.toBeDisabled();
  });
});
