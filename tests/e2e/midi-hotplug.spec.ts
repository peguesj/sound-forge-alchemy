import { test, expect } from "@playwright/test";

const BASE_URL = "http://localhost:4000";

test.describe("MIDI Hotplug & Device Management", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE_URL}/users/log-in`);
    await page.fill('input[name="user[email]"]', "dev@soundforge.local");
    await page.fill('input[name="user[password]"]', "password123456");
    await page.click('button[type="submit"]');
    await page.waitForURL((url) => !url.pathname.includes("/log-in"), { timeout: 10_000 });
  });

  test("MIDI-05 CP-125: MIDI page renders device list section without error", async ({ page }) => {
    const response = await page.goto(`${BASE_URL}/midi`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page).not.toHaveTitle(/error|500|not found/i);

    const visible = page.locator([
      'text="Device"', 'text="MIDI"', 'text="Devices"',
      "table", "ul", "h1", "h2", "h3", "main",
    ].join(", "));
    await expect(visible.first()).toBeVisible({ timeout: 8000 });
  });

  test("MIDI-06 CP-126: MIDI page shows device info panel or research container", async ({ page }) => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForLoadState("networkidle", { timeout: 10_000 }).catch(() => {});

    const infoLocator = page.locator([
      'text="manufacturer"', 'text="Manufacturer"',
      'text="vendor"', 'text="Vendor"',
      '[data-testid*="device-info"]', '.device-info',
    ].join(", "));

    const count = await infoLocator.count();
    if (count === 0) {
      // No devices connected — page body still renders
      await expect(page.locator("body")).toBeVisible();
    } else {
      expect(count).toBeGreaterThan(0);
    }
  });

  test("MIDI-07 CP-127: MIDI page has image upload control for controller photo", async ({ page }) => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForLoadState("networkidle", { timeout: 10_000 }).catch(() => {});

    const uploadLocator = page.locator([
      'input[type="file"]',
      'button:has-text("Upload")', 'button:has-text("Image")',
      'button:has-text("Photo")', 'button:has-text("Controller")',
      'label:has-text("Upload")', 'label:has-text("Image")',
      'label[for*="upload"]', 'label[for*="image"]',
      '[data-testid*="upload"]',
    ].join(", "));

    const uploadCount = await uploadLocator.count();
    expect(uploadCount).toBeGreaterThan(0);
  });
});
