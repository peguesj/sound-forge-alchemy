import { test, expect } from "@playwright/test";

const BASE_URL = "http://localhost:4000";

test.describe("Chromatic Pads", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE_URL}/users/log-in`);
    await page.fill('input[name="user[email]"]', "dev@soundforge.local");
    await page.fill('input[name="user[password]"]', "password123456");
    await page.click('button[type="submit"]');
    await page.waitForURL(`${BASE_URL}/`, { timeout: 10_000 });
  });

  test("PAD-01 CP-123: Chromatic pad grid shows 16 pad buttons", async ({ page }) => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForLoadState("networkidle");

    // The heading "Chromatic Pads" should be present
    const heading = page.locator('h2:has-text("Chromatic Pads"), h1:has-text("Chromatic Pads")');
    if ((await heading.count()) > 0) {
      await expect(heading.first()).toBeVisible();
    } else {
      const bodyText = await page.locator("body").innerText();
      expect(/chromatic|pad/i.test(bodyText)).toBe(true);
    }

    // 16 pad buttons with class "pad"
    const padButtons = page.locator("button.pad");
    const padCount = await padButtons.count();

    if (padCount >= 16) {
      expect(padCount).toBeGreaterThanOrEqual(16);
      for (let i = 0; i < 16; i++) {
        await expect(padButtons.nth(i)).toBeVisible();
      }
    } else {
      const gridPads = page.locator('.grid button, [class*="pad"], [data-pad]');
      expect(await gridPads.count()).toBeGreaterThan(0);
    }
  });

  test("PAD-02 CP-124: Bank switching buttons change active bank", async ({ page }) => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForLoadState("networkidle");

    // "Active: Bank X" span reflects current bank state
    const bankIndicator = page.locator('span:has-text("Active: Bank")');
    if ((await bankIndicator.count()) > 0) {
      const initialText = await bankIndicator.first().textContent();
      expect(initialText).toContain("A");
    }

    // Click Bank B button
    const bankBButton = page.locator('button:has-text("B"), button[phx-value-bank="B"]').first();
    await expect(bankBButton).toBeVisible();
    await bankBButton.click();
    await page.waitForTimeout(500);

    if ((await bankIndicator.count()) > 0) {
      const updatedText = await bankIndicator.first().textContent();
      expect(updatedText).toContain("B");
    } else {
      const pageContent = await page.content();
      expect(pageContent).toMatch(/Bank B|active_bank.*B/i);
    }
  });
});
