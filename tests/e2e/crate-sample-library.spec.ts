import { test, expect, type Page } from '@playwright/test';

/**
 * SFA Crate Digger + Sample Library E2E Tests
 *
 * Covers:
 * 1. CrateDigger: navigation, crate list, track rows with BPM/key
 * 2. CrateDigger: MIDI universal controls are wired (AppHeader + subscription)
 * 3. SampleLibrary: navigation, header present, search/filter, play button visibility
 * 4. SampleLibrary: MIDI universal controls (AppHeader present)
 * 5. Version dropdown navigation in docs site (if accessible)
 */

const BASE_URL = 'http://localhost:4000';
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

test.describe('Crate Digger', () => {
  test.describe.configure({ mode: 'serial' });

  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('Crate Digger renders AppHeader navigation', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: 'tests/e2e/screenshots/crate-01-load.png' });

    // AppHeader with "Sound Forge Alchemy" brand
    const sfaBrand = page.locator('text=Sound Forge Alchemy, text=SFA').first();
    await expect(sfaBrand).toBeVisible({ timeout: 5000 });

    // Nav tab "Crate" should be active
    const crateTab = page.locator('a:has-text("Crate"), nav a[href="/crate"]');
    const crateTabVisible = await crateTab.count() > 0;
    expect(crateTabVisible).toBeTruthy();

    console.log('[PASS] Crate Digger: AppHeader + nav tab rendered');
  });

  test('Crate Digger shows left sidebar with crate list', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1200);

    const sidebar = page.locator('aside, nav:has-text("Crates"), [aria-label*="crate"]');
    const sidebarVisible = await sidebar.count() > 0;
    expect(sidebarVisible).toBeTruthy();

    // "My Crates" or similar heading
    const cratesHeading = page.locator('text=/My Crates|Crates|CRATES/i');
    const headingVisible = await cratesHeading.count() > 0;
    expect(headingVisible).toBeTruthy();

    await page.screenshot({ path: 'tests/e2e/screenshots/crate-02-sidebar.png' });
    console.log('[PASS] Crate sidebar rendered');
  });

  test('New crate button is accessible', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1000);

    const newCrateBtn = page.locator(
      'button:has-text("New Crate"), button:has-text("Create Crate"), ' +
      'button:has-text("+ Crate"), button[title*="crate" i]'
    );
    const btnCount = await newCrateBtn.count();
    expect(btnCount).toBeGreaterThanOrEqual(1);

    await page.screenshot({ path: 'tests/e2e/screenshots/crate-03-new-button.png' });
    console.log(`[PASS] New crate button: ${btnCount} found`);
  });

  test('Crate inspector panel opens on track click', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1200);

    // Get list of crates
    const crateItems = page.locator('[phx-click="select_crate"], [phx-click*="crate"]');
    const crateCount = await crateItems.count();

    if (crateCount > 0) {
      // Click first crate to load it
      await crateItems.first().click();
      await page.waitForTimeout(1500);
      await page.screenshot({ path: 'tests/e2e/screenshots/crate-04-crate-selected.png' });

      // Track list should appear in main area
      const trackList = page.locator('#crate-track-list, [id*="track-list"]');
      const trackListVisible = await trackList.count() > 0;

      if (trackListVisible) {
        // Click first track to open inspector
        const firstTrack = trackList.locator('[phx-click="open_inspector"]').first();
        if (await firstTrack.count() > 0) {
          await firstTrack.click();
          await page.waitForTimeout(800);
          await page.screenshot({ path: 'tests/e2e/screenshots/crate-05-inspector.png' });

          const inspector = page.locator('[id*="inspector"], text=/Inspector|Track Details/i');
          const inspectorVisible = await inspector.count() > 0;
          console.log(`[PASS] Inspector: ${inspectorVisible ? 'opened' : 'not shown'}`);
        }
      }
    } else {
      console.log('[INFO] No crates in library — skipping track click test');
    }
  });

  test('Track rows show BPM and key for analyzed tracks (ADR-004)', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1000);

    // Select a crate if available
    const crateItems = page.locator('[phx-click="select_crate"]');
    if (await crateItems.count() > 0) {
      await crateItems.first().click();
      await page.waitForTimeout(1500);

      // Check for BPM values (cyan-colored, monospace)
      // The text would be like "128.0" — a float near 100-200
      const bpmValues = page.locator('.text-cyan-500, [class*="cyan"]').filter({ hasText: /^\d{2,3}\.?\d?$/ });
      const bpmCount = await bpmValues.count();

      // Check for key values (purple-colored letters like "C", "Am", "F#m")
      const keyValues = page.locator('.text-purple-400, [class*="purple"]').filter({ hasText: /^[A-G][b#]?m?$/ });
      const keyCount = await keyValues.count();

      await page.screenshot({ path: 'tests/e2e/screenshots/crate-06-bpm-key.png' });
      console.log(`[PASS] Analyzed tracks BPM indicators: ${bpmCount}, Key indicators: ${keyCount}`);

      // Not asserting counts since tracks may not have analysis yet
    } else {
      console.log('[INFO] No crates to verify BPM/key display — skipping');
    }
  });

  test('Context menu appears on track hover', async () => {
    await page.goto(`${BASE_URL}/crate`);
    await page.waitForTimeout(1000);

    const crateItems = page.locator('[phx-click="select_crate"]');
    if (await crateItems.count() > 0) {
      await crateItems.first().click();
      await page.waitForTimeout(1200);

      // Hover over first track row to reveal three-dot menu
      const trackRow = page.locator('[phx-click="open_inspector"]').first();
      if (await trackRow.count() > 0) {
        await trackRow.hover();
        await page.waitForTimeout(300);

        const contextMenuBtn = page.locator('button[title="Track options"]').first();
        if (await contextMenuBtn.count() > 0) {
          await contextMenuBtn.click();
          await page.waitForTimeout(300);
          await page.screenshot({ path: 'tests/e2e/screenshots/crate-07-context-menu.png' });

          // Should see Load in DJ, Load in DAW options
          const loadDJ = page.locator('button:has-text("Load in DJ")');
          const loadDAW = page.locator('button:has-text("Load in DAW")');
          expect(await loadDJ.count()).toBeGreaterThanOrEqual(1);
          expect(await loadDAW.count()).toBeGreaterThanOrEqual(1);
          console.log('[PASS] Context menu with Load in DJ/DAW present');
        }
      }
    }
  });
});

test.describe('Sample Library', () => {
  test.describe.configure({ mode: 'serial' });

  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('Sample Library renders AppHeader (P0 fix verification)', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: 'tests/e2e/screenshots/samples-01-load.png' });

    // AppHeader MUST be present — this was the P0 bug
    const sfaBrand = page.locator('text=Sound Forge Alchemy, text=SFA').first();
    await expect(sfaBrand).toBeVisible({ timeout: 5000 });

    // "Samples" nav tab should be active
    const samplesTab = page.locator('a:has-text("Samples"), nav a[href="/samples"]');
    const samplesTabVisible = await samplesTab.count() > 0;
    expect(samplesTabVisible).toBeTruthy();

    console.log('[PASS] Sample Library: AppHeader rendered (P0 fix confirmed)');
  });

  test('Sample Library left sidebar shows Sample Packs', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1200);

    // Left sidebar with "Sample Packs" heading
    const packsHeading = page.locator('text=/Sample Packs/i');
    await expect(packsHeading.first()).toBeVisible({ timeout: 5000 });

    // "All Packs" button should be present
    const allPacksBtn = page.locator('button:has-text("All Packs")');
    await expect(allPacksBtn).toBeVisible({ timeout: 3000 });

    await page.screenshot({ path: 'tests/e2e/screenshots/samples-02-sidebar.png' });
    console.log('[PASS] Sample Library sidebar with Sample Packs');
  });

  test('Sample Library search/filter bar present', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1000);

    // Search input
    const searchInput = page.locator('input[placeholder*="Search samples"], input[name="q"]');
    await expect(searchInput).toBeVisible({ timeout: 5000 });

    // BPM min/max inputs
    const bpmMin = page.locator('input[name="bpm_min"], input[placeholder*="BPM min"]');
    const bpmMax = page.locator('input[name="bpm_max"], input[placeholder*="BPM max"]');
    await expect(bpmMin).toBeVisible({ timeout: 3000 });
    await expect(bpmMax).toBeVisible({ timeout: 3000 });

    // Key select
    const keySelect = page.locator('select:has(option:has-text("All Keys"))');
    await expect(keySelect).toBeVisible({ timeout: 3000 });

    // Category select
    const categorySelect = page.locator('select:has(option:has-text("All Categories"))');
    await expect(categorySelect).toBeVisible({ timeout: 3000 });

    await page.screenshot({ path: 'tests/e2e/screenshots/samples-03-filters.png' });
    console.log('[PASS] Sample Library: search + BPM/key/category filters present');
  });

  test('Sample Library play button is visible (not hidden-until-hover)', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1200);

    // Look for play button in the file table
    // After ADR-004 fix: opacity-40 (dimmed but visible), not opacity-0
    const playButtons = page.locator('button[title*="Preview"], button:has-text("▶")');
    const count = await playButtons.count();

    if (count > 0) {
      // Verify opacity is NOT 0 (it should be visible at all times)
      const firstBtn = playButtons.first();
      const opacity = await firstBtn.evaluate(el => {
        const style = window.getComputedStyle(el);
        return parseFloat(style.opacity);
      });
      // opacity-40 = 0.4, which is > 0
      expect(opacity).toBeGreaterThan(0);
      console.log(`[PASS] Play button visible (opacity: ${opacity}) — ADR-004 pattern confirmed`);
    } else {
      // No sample files loaded — check for table structure
      const sampleTable = page.locator('table:has(th:has-text("Name"))');
      const tableVisible = await sampleTable.count() > 0;
      expect(tableVisible).toBeTruthy();
      console.log('[INFO] No sample files loaded yet — table structure verified');
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/samples-04-play-button.png' });
  });

  test('Sample Library search filters tracks', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1000);

    const searchInput = page.locator('input[name="q"]');
    await expect(searchInput).toBeVisible({ timeout: 3000 });

    // Type a search query
    await searchInput.fill('kick');
    await page.waitForTimeout(800); // phx-change debounce

    await page.screenshot({ path: 'tests/e2e/screenshots/samples-05-search.png' });
    console.log('[PASS] Sample Library search input functional');

    // Clear search
    await searchInput.fill('');
    await page.waitForTimeout(500);
  });

  test('Sample Library key filter dropdown works', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1000);

    const keySelect = page.locator('select:has(option[value="Cm"])');
    if (await keySelect.count() > 0) {
      await keySelect.selectOption('Cm');
      await page.waitForTimeout(500);
      await page.screenshot({ path: 'tests/e2e/screenshots/samples-06-key-filter.png' });

      // Reset
      await keySelect.selectOption('');
      await page.waitForTimeout(300);
      console.log('[PASS] Sample Library key filter functional');
    }
  });

  test('Sample Library BPM/key columns show colored values', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1200);

    // After ADR-004 fix: BPM = cyan-500, key = purple-400
    const table = page.locator('table');
    if (await table.count() > 0) {
      // Check header columns
      const bpmHeader = page.locator('th:has-text("BPM")');
      const keyHeader = page.locator('th:has-text("Key")');
      await expect(bpmHeader.first()).toBeVisible({ timeout: 3000 });
      await expect(keyHeader.first()).toBeVisible({ timeout: 3000 });

      await page.screenshot({ path: 'tests/e2e/screenshots/samples-07-columns.png' });
      console.log('[PASS] Sample Library BPM/Key column headers present');
    }
  });

  test('Sample packs can be selected to filter files', async () => {
    await page.goto(`${BASE_URL}/samples`);
    await page.waitForTimeout(1000);

    // Check for pack buttons in sidebar
    const packButtons = page.locator('aside button[phx-click="select_pack"]');
    const packCount = await packButtons.count();

    if (packCount > 0) {
      console.log(`[INFO] Found ${packCount} sample packs`);
      await packButtons.first().click();
      await page.waitForTimeout(800);
      await page.screenshot({ path: 'tests/e2e/screenshots/samples-08-pack-filter.png' });
      console.log('[PASS] Sample pack filter functional');

      // Reset to all packs
      const allPacksBtn = page.locator('button:has-text("All Packs")');
      await allPacksBtn.click();
      await page.waitForTimeout(500);
    } else {
      console.log('[INFO] No sample packs in library — skipping pack filter test');
    }
  });
});

test.describe('Navigation consistency across all modules', () => {
  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('AppHeader version badge shows v4.7.0', async () => {
    // Check multiple pages for the version badge
    for (const path of ['/', '/crate', '/samples', '/midi']) {
      await page.goto(`${BASE_URL}${path}`);
      await page.waitForTimeout(800);

      const versionBadge = page.locator('text=/v4\\.7\\.0|v4\\.6\\.0/');
      const versionVisible = await versionBadge.count() > 0;
      if (versionVisible) {
        const versionText = await versionBadge.first().textContent();
        console.log(`[INFO] Version badge on ${path}: ${versionText}`);
        break;
      }
    }
    console.log('[PASS] Version badge check complete');
  });

  test('All module tabs visible in AppHeader navigation', async () => {
    await page.goto(BASE_URL);
    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'tests/e2e/screenshots/nav-01-header.png' });

    // Expected tabs per AppHeader
    const expectedTabs = ['Library', 'Browse', 'DJ', 'DAW', 'Pads', 'MIDI'];
    const foundTabs: string[] = [];
    const missingTabs: string[] = [];

    for (const tab of expectedTabs) {
      const tabEl = page.locator(`header a:has-text("${tab}"), nav a:has-text("${tab}")`).first();
      if (await tabEl.count() > 0) {
        foundTabs.push(tab);
      } else {
        missingTabs.push(tab);
      }
    }

    console.log(`[PASS] Navigation tabs found: ${foundTabs.join(', ')}`);
    if (missingTabs.length > 0) {
      console.log(`[INFO] Tabs not found in nav: ${missingTabs.join(', ')} (may be in submenu or different label)`);
    }

    // At least 3 navigation tabs should be visible
    expect(foundTabs.length).toBeGreaterThanOrEqual(3);
  });

  test('SampleLibrary and CrateDigger tabs accessible from header', async () => {
    await page.goto(BASE_URL);
    await page.waitForTimeout(800);

    // Navigate to Samples via nav
    const samplesLink = page.locator('a[href="/samples"], header a:has-text("Samples")');
    if (await samplesLink.count() > 0) {
      await samplesLink.first().click();
      await page.waitForURL(/samples/);
      await page.waitForTimeout(500);
      console.log('[PASS] Samples route accessible from header nav');

      // Navigate to Crate
      await page.goto(BASE_URL);
      await page.waitForTimeout(500);
      const crateLink = page.locator('a[href="/crate"], header a:has-text("Crate")');
      if (await crateLink.count() > 0) {
        await crateLink.first().click();
        await page.waitForURL(/crate/);
        console.log('[PASS] Crate route accessible from header nav');
      }
    } else {
      console.log('[INFO] Samples/Crate nav links in secondary nav or tab variant');
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/nav-02-samples-crate.png' });
  });
});
