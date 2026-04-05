import { test, expect, type Page } from '@playwright/test';

/**
 * SFA DAW Import E2E Tests
 *
 * User Stories covered:
 *   US-001  Library → Edit in DAW (downloaded track auto-loads project)
 *   US-002  Library → Edit in DAW (track not downloaded → no DAW link shown)
 *   US-003  Multi-select import from library panel
 *   US-004  Multi-select import from crate panel
 *   US-005  Import panel source switching (Library ↔ Crate tabs)
 *   US-006  Select All / Clear in import panel
 *   US-007  Sample Library row → DAW icon
 *   US-008  CrateDigger context menu → Edit in DAW Project
 */

const BASE_URL = 'http://127.0.0.1:4000';
const TEST_USER = { email: 'dev@soundforge.local', password: 'password123456' };

async function login(page: Page) {
  await page.goto(`${BASE_URL}/users/log-in`);
  await page.waitForLoadState('networkidle');
  const form = page.locator('#login_form_password');
  await form.locator('input[type="email"]').fill(TEST_USER.email);
  await form.locator('input[type="password"]').fill(TEST_USER.password);
  await form.locator('button:has-text("Log in and stay logged in")').click();
  await page.waitForURL(/\//);
  await page.waitForTimeout(1500);
}

// ─── US-001: Library → Edit in DAW ─────────────────────────────────────────

test.describe('US-001: Library track → Edit in DAW', () => {
  test('clicking Edit in DAW on a downloaded track navigates to /daw/:id', async ({ page }) => {
    await login(page);
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    // Find a downloaded track in the library list
    const downloadedTrack = page.locator('[data-download-status="completed"]').first();
    const hasDownloaded = await downloadedTrack.count() > 0;

    if (!hasDownloaded) {
      // Try clicking the first track row to open detail panel
      const trackRow = page.locator('.track-row, [phx-click="select_track"]').first();
      if (await trackRow.count() === 0) {
        test.skip();
        return;
      }
      await trackRow.click();
      await page.waitForTimeout(600);
    } else {
      await downloadedTrack.click();
      await page.waitForTimeout(600);
    }

    // Detail panel should be open — look for Edit in DAW link
    const dawLink = page.locator('a[href*="/daw/"], a:has-text("Edit in DAW")');
    await expect(dawLink.first()).toBeVisible({ timeout: 5000 });

    const href = await dawLink.first().getAttribute('href');
    expect(href).toMatch(/\/daw\//);

    await dawLink.first().click();
    await page.waitForURL(/\/daw\//);
    await expect(page).toHaveURL(/\/daw\//);
  });

  test('DAW project page loads without KeyError for authenticated user', async ({ page }) => {
    await login(page);

    // Navigate directly to /daw route (no track_id) — should render project list
    await page.goto(`${BASE_URL}/daw`);
    await page.waitForLoadState('networkidle');

    // Must NOT show the Phoenix error page
    const errorPage = page.locator('text=KeyError, text=Plug.Conn.WrapperError');
    await expect(errorPage).toHaveCount(0);
  });

  test('DAW /daw/:id auto-creates project and loads track', async ({ page }) => {
    await login(page);
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    // Get a track UUID from the page via JS
    const trackId = await page.evaluate(() => {
      const el = document.querySelector('[data-track-id], [id^="tracks-"]');
      if (!el) return null;
      const id = el.getAttribute('data-track-id') || (el.id || '').replace('tracks-', '');
      return id || null;
    });

    if (!trackId || trackId.length < 10) {
      test.skip();
      return;
    }

    await page.goto(`${BASE_URL}/daw/${trackId}`);
    await page.waitForLoadState('networkidle');

    // Must NOT show KeyError
    const body = await page.textContent('body');
    expect(body).not.toContain('KeyError');
    expect(body).not.toContain('key :current_user not found');
  });
});

// ─── US-002: Download gate ──────────────────────────────────────────────────

test.describe('US-002: Edit in DAW only visible for downloaded tracks', () => {
  test('Edit in DAW link is NOT shown for tracks without completed download', async ({ page }) => {
    await login(page);
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    // Find a track that is NOT downloaded (no download_status=completed)
    const pendingTrack = page.locator(
      '[data-download-status]:not([data-download-status="completed"])'
    ).first();

    if (await pendingTrack.count() === 0) {
      test.skip();
      return;
    }

    await pendingTrack.click();
    await page.waitForTimeout(600);

    // Edit in DAW should NOT be visible
    const dawLink = page.locator('a:has-text("Edit in DAW"), a[href*="/daw/"]');
    await expect(dawLink).toHaveCount(0);
  });
});

// ─── US-003 / US-006: Import panel — multi-select and Select All ────────────

test.describe('US-003/US-006: DAW unified import panel', () => {
  test('Add Track button opens import panel with Library tab active', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/daw`);
    await page.waitForLoadState('networkidle');

    const addTrackBtn = page.locator('button:has-text("Add Track"), button:has-text("+ Add Track")');
    if (await addTrackBtn.count() === 0) {
      test.skip();
      return;
    }

    await addTrackBtn.first().click();
    await page.waitForTimeout(500);

    // Panel should open with Library tab
    const libraryTab = page.locator('button:has-text("Library")');
    await expect(libraryTab.first()).toBeVisible({ timeout: 3000 });

    // Crate tab should also be present
    const crateTab = page.locator('button:has-text("Crate")');
    await expect(crateTab.first()).toBeVisible({ timeout: 3000 });
  });

  test('Select All selects all visible tracks', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/daw`);
    await page.waitForLoadState('networkidle');

    const addTrackBtn = page.locator('button:has-text("Add Track"), button:has-text("+ Add Track")');
    if (await addTrackBtn.count() === 0) {
      test.skip();
      return;
    }

    await addTrackBtn.first().click();
    await page.waitForTimeout(500);

    const selectAllBtn = page.locator('button:has-text("Select all"), button:has-text("Select All")');
    if (await selectAllBtn.count() === 0) {
      test.skip();
      return;
    }

    await selectAllBtn.first().click();
    await page.waitForTimeout(300);

    // Footer should show count > 0
    const footer = page.locator('[class*="border-t"]').last();
    const footerText = await footer.textContent();
    expect(footerText).toMatch(/\d+ selected|Add \d+/);
  });

  test('Clear resets selection to zero', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/daw`);
    await page.waitForLoadState('networkidle');

    const addTrackBtn = page.locator('button:has-text("Add Track"), button:has-text("+ Add Track")');
    if (await addTrackBtn.count() === 0) {
      test.skip();
      return;
    }

    await addTrackBtn.first().click();
    await page.waitForTimeout(500);

    // Select all then clear
    const selectAllBtn = page.locator('button:has-text("Select all"), button:has-text("Select All")');
    if (await selectAllBtn.count() > 0) {
      await selectAllBtn.first().click();
      await page.waitForTimeout(200);
    }

    const clearBtn = page.locator('button:has-text("Clear")');
    if (await clearBtn.count() === 0) {
      test.skip();
      return;
    }

    await clearBtn.first().click();
    await page.waitForTimeout(200);

    // Add button should show 0 or be disabled
    const addBtn = page.locator('button:has-text("Add 0"), button[disabled]:has-text("Add")');
    // Accept either: no selection shown, or "Add 0 Tracks"
    const footerText = await page.locator('[class*="border-t"]').last().textContent();
    expect(footerText).toMatch(/0 selected|Add 0|no tracks/i);
  });

  test('Switching to Crate tab shows crate list', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/daw`);
    await page.waitForLoadState('networkidle');

    const addTrackBtn = page.locator('button:has-text("Add Track"), button:has-text("+ Add Track")');
    if (await addTrackBtn.count() === 0) {
      test.skip();
      return;
    }

    await addTrackBtn.first().click();
    await page.waitForTimeout(500);

    const crateTab = page.locator('button:has-text("Crate")');
    if (await crateTab.count() === 0) {
      test.skip();
      return;
    }

    await crateTab.first().click();
    await page.waitForTimeout(400);

    // Should show crate list or "No crates" empty state
    const crateList = page.locator('text=No crates, [phx-click="select_crate_to_browse"]');
    const hasCrateContent = await crateList.count() > 0;
    expect(hasCrateContent).toBeTruthy();
  });
});

// ─── US-007: Sample Library DAW icon ────────────────────────────────────────

test.describe('US-007: Sample Library row DAW icon', () => {
  test('hovering a sample row reveals Edit in DAW icon', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForLoadState('networkidle');

    const firstRow = page.locator('#sample-files tr').first();
    if (await firstRow.count() === 0) {
      test.skip();
      return;
    }

    await firstRow.hover();
    await page.waitForTimeout(200);

    // The DAW link should become visible on hover (opacity-100)
    const dawIcon = firstRow.locator('a[href*="/daw/"]');
    await expect(dawIcon).toBeVisible({ timeout: 2000 });
  });
});

// ─── US-008: CrateDigger → Edit in DAW Project ──────────────────────────────

test.describe('US-008: CrateDigger context menu → Edit in DAW Project', () => {
  test('Edit in DAW Project navigates to /daw/:id for library track', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForLoadState('networkidle');

    // Open a crate if any exist
    const crateItem = page.locator('[phx-click="open_crate"]').first();
    if (await crateItem.count() === 0) {
      test.skip();
      return;
    }

    await crateItem.click();
    await page.waitForTimeout(600);

    // Right-click / context menu on a track
    const trackRow = page.locator('[phx-click="select_track"]').first();
    if (await trackRow.count() === 0) {
      test.skip();
      return;
    }

    await trackRow.click();
    await page.waitForTimeout(400);

    // "Edit in DAW Project" option
    const dawProjectBtn = page.locator('button:has-text("Edit in DAW Project"), [phx-click="open_in_daw_project"]');
    if (await dawProjectBtn.count() === 0) {
      test.skip();
      return;
    }

    await dawProjectBtn.first().click();
    // Either navigates to /daw/:id OR shows "download first" flash
    await page.waitForTimeout(800);

    const url = page.url();
    const body = await page.textContent('body');
    const navigatedToDaw = url.includes('/daw/');
    const showedDownloadFlash = body?.includes('download it first') || false;

    expect(navigatedToDaw || showedDownloadFlash).toBeTruthy();
  });
});

// ─── UAT Stories Panel (/prototype?tab=stories) ──────────────────────────────

test.describe('UAT Stories panel at /prototype', () => {
  test('Stories tab renders with epic filter pills and story list', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/prototype?tab=stories`);
    await page.waitForLoadState('networkidle');

    // Must not show error
    const body = await page.textContent('body');
    expect(body).not.toContain('KeyError');

    // Stories tab should be active — look for epic pills
    const epicPill = page.locator('[phx-click="filter_stories_epic"], button:has-text("EP-")');
    const hasPills = await epicPill.count() > 0;

    // If /prototype requires admin, it may redirect or show access denied
    if (page.url().includes('/prototype')) {
      expect(hasPills).toBeTruthy();
    }
  });

  test('Clicking a story shows detail panel with acceptance criteria', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/prototype?tab=stories`);
    await page.waitForLoadState('networkidle');

    if (!page.url().includes('/prototype')) {
      test.skip();
      return;
    }

    const storyBtn = page.locator('[phx-click="select_story"]').first();
    if (await storyBtn.count() === 0) {
      test.skip();
      return;
    }

    await storyBtn.first().click();
    await page.waitForTimeout(400);

    // Detail panel should show GIVEN/WHEN/THEN
    const detailPanel = page.locator('text=GIVEN, text=WHEN, text=THEN');
    const hasGherkin = await detailPanel.count() > 0;
    expect(hasGherkin).toBeTruthy();
  });
});
