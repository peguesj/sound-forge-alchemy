import { test, expect } from "@playwright/test";

const BASE_URL = "http://localhost:4000";

test.describe("Practice", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE_URL}/users/log-in`);
    await page.fill('input[name="user[email]"]', "dev@soundforge.local");
    await page.fill('input[name="user[password]"]', "password123456");
    await page.click('button[type="submit"]');
    await page.waitForURL((url) => !url.pathname.includes("log-in"), { timeout: 10_000 });
  });

  test("PRC-01 CP-130: practice page renders with content or empty state", async ({ page }) => {
    await page.goto(`${BASE_URL}/practice`);
    await page.waitForLoadState("networkidle");

    await expect(page.locator("body")).not.toBeEmpty();
    const bodyText = (await page.locator("body").innerText()) ?? "";

    const pageRendered =
      /practice/i.test(bodyText) ||
      /session/i.test(bodyText) ||
      /no sessions/i.test(bodyText) ||
      /start a practice/i.test(bodyText) ||
      /get started/i.test(bodyText);

    expect(
      pageRendered,
      `Expected /practice to show "Practice", "session", or empty state. Got: "${bodyText.slice(0, 200)}"`
    ).toBe(true);
  });
});
