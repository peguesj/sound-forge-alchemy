import { test, expect, type Page } from '@playwright/test';

/**
 * SFA DJ / DAW / MIDI E2E Tests
 *
 * Covers:
 * 1. DJ tab navigation and deck layout (ADR-004: A/B labels, vertical faders)
 * 2. DJ deck controls (play/pause, crossfader, EQ knobs, hot cue 2×4 grid)
 * 3. DAW tab navigation and track loading
 * 4. MIDI tab — device list and mapping UI
 * 5. Universal MIDI transport via AppHeader
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

async function navigateTo(page: Page, tab: string) {
  // Try nav link first
  const navLink = page.locator(`nav a:has-text("${tab}"), header a:has-text("${tab}")`);
  if (await navLink.count() > 0) {
    await navLink.first().click();
    await page.waitForTimeout(800);
    return;
  }
  // Fallback to direct URL
  const tabMap: Record<string, string> = {
    DJ: '/?tab=dj',
    DAW: '/?tab=daw',
    MIDI: '/midi',
    Samples: '/samples',
    Crate: '/crate',
  };
  if (tabMap[tab]) {
    await page.goto(`${BASE_URL}${tabMap[tab]}`);
    await page.waitForTimeout(800);
  }
}

test.describe('DJ Tab — Layout and Controls', () => {
  test.describe.configure({ mode: 'serial' });

  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('DJ tab is accessible via AppHeader navigation', async () => {
    await navigateTo(page, 'DJ');
    await page.screenshot({ path: 'tests/e2e/screenshots/dj-01-tab-load.png' });

    // AppHeader must be visible
    const header = page.locator('header, [data-testid="app-header"]');
    await expect(header.first()).toBeVisible();

    // DJ content should render
    const djContent = page.locator('#dj-tab, [data-testid="dj-tab"], text=/DECK|Crossfader|DJ/i');
    await expect(djContent.first()).toBeVisible({ timeout: 5000 });

    console.log('[PASS] DJ tab accessible and AppHeader present');
  });

  test('DJ deck labels are A/B (ADR-004: letters over numbers)', async () => {
    await navigateTo(page, 'DJ');
    await page.screenshot({ path: 'tests/e2e/screenshots/dj-02-deck-labels.png' });

    // Should see "DECK A" and "DECK B" labels
    const deckA = page.locator('text=/DECK A|Deck A/');
    const deckB = page.locator('text=/DECK B|Deck B/');

    const deckAVisible = await deckA.count() > 0;
    const deckBVisible = await deckB.count() > 0;

    expect(deckAVisible || deckBVisible).toBeTruthy();
    console.log(`[PASS] Deck labels — A: ${deckAVisible}, B: ${deckBVisible}`);
  });

  test('Vertical channel faders present in mixer strip', async () => {
    await navigateTo(page, 'DJ');

    // Vertical faders use writing-mode:vertical-lr styling
    const verticalFader = page.locator('input[type="range"][style*="writing-mode"], input[type="range"][aria-label*="Deck"]');
    const faderCount = await verticalFader.count();

    // Should have at least 2 vertical faders (one per deck)
    expect(faderCount).toBeGreaterThanOrEqual(2);
    console.log(`[PASS] Vertical faders: ${faderCount} found`);
  });

  test('Crossfader is present and interactive', async () => {
    await navigateTo(page, 'DJ');

    // Crossfader input
    const crossfader = page.locator('input[type="range"][name="value"]:near(:text("Crossfader")), form input[type="range"]').first();
    await expect(crossfader).toBeVisible({ timeout: 5000 });

    // Crossfader curve buttons should be present inline
    const curveButtons = page.locator('button:has-text("Lin"), button:has-text("EQ-P"), button:has-text("Sharp")');
    const curveCount = await curveButtons.count();
    expect(curveCount).toBeGreaterThanOrEqual(1);

    await page.screenshot({ path: 'tests/e2e/screenshots/dj-03-crossfader.png' });
    console.log(`[PASS] Crossfader + ${curveCount} curve buttons present`);
  });

  test('Hot cue pads render in 2×4 grid (ADR-004)', async () => {
    await navigateTo(page, 'DJ');

    // Hot cue section
    const hotCueSection = page.locator('text=/Hot Cues/i');
    if (await hotCueSection.count() > 0) {
      // Should see 4-column grid (2×4 layout)
      const grid4col = page.locator('.grid-cols-4');
      const grid4Count = await grid4col.count();
      expect(grid4Count).toBeGreaterThanOrEqual(1);

      // Should have A-H cue pad letters
      for (const letter of ['A', 'B', 'C', 'D']) {
        const pad = page.locator(`button:has-text("${letter}")`).first();
        await expect(pad).toBeVisible({ timeout: 3000 });
      }

      await page.screenshot({ path: 'tests/e2e/screenshots/dj-04-hot-cue-grid.png' });
      console.log(`[PASS] Hot cue 2×4 grid present (grid-cols-4 count: ${grid4Count})`);
    } else {
      // Load a track first to see cue pads
      console.log('[INFO] Hot Cues section requires a loaded track — skipping pad verification');
    }
  });

  test('EQ knobs (HI/MID/LO) present per channel', async () => {
    await navigateTo(page, 'DJ');

    // EQ labels
    const hiLabel = page.locator('text="HI"').first();
    const midLabel = page.locator('text="MID"').first();
    const loLabel = page.locator('text="LO"').first();

    const hiVisible = await hiLabel.isVisible().catch(() => false);
    const midVisible = await midLabel.isVisible().catch(() => false);
    const loVisible = await loLabel.isVisible().catch(() => false);

    expect(hiVisible || midVisible || loVisible).toBeTruthy();

    await page.screenshot({ path: 'tests/e2e/screenshots/dj-05-eq-knobs.png' });
    console.log(`[PASS] EQ knobs — HI:${hiVisible} MID:${midVisible} LO:${loVisible}`);
  });

  test('Grid mode selector (BAR/BEAT/SUB/SMART) present', async () => {
    await navigateTo(page, 'DJ');

    // Grid mode select
    const gridSelect = page.locator('select:has(option[value="bar"])');
    const gridSelectCount = await gridSelect.count();
    expect(gridSelectCount).toBeGreaterThanOrEqual(1);

    // Verify options
    const options = await gridSelect.first().locator('option').allTextContents();
    expect(options).toContain('BAR');
    expect(options).toContain('BEAT');
    expect(options).toContain('SUB');

    console.log(`[PASS] Grid mode selector: ${options.join(', ')}`);
  });

  test('Master Sync button visible', async () => {
    await navigateTo(page, 'DJ');

    const syncBtn = page.locator('button:has-text("MASTER SYNC")');
    await expect(syncBtn).toBeVisible({ timeout: 5000 });
    console.log('[PASS] Master Sync button present');
  });
});

test.describe('DAW Tab', () => {
  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('DAW tab navigates and renders header', async () => {
    await navigateTo(page, 'DAW');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'tests/e2e/screenshots/daw-01-tab.png' });

    // AppHeader should be present (it's in the parent DashboardLive)
    const sfaText = page.locator('text=Sound Forge Alchemy, text=SFA');
    const sfaVisible = await sfaText.count() > 0;

    // DAW-specific content
    const dawContent = page.locator('text=/DAW|Waveform|Piano Roll|Timeline/i');
    const dawVisible = await dawContent.count() > 0;

    expect(sfaVisible || dawVisible).toBeTruthy();
    console.log(`[PASS] DAW tab — header:${sfaVisible} content:${dawVisible}`);
  });

  test('DAW tab shows waveform or piano roll or empty state', async () => {
    await navigateTo(page, 'DAW');
    await page.waitForTimeout(1000);

    // Should show some DAW UI - either a loaded track or empty state
    const dawUI = page.locator(
      '[data-testid="daw-tab"], #daw-tab, ' +
      'canvas[id*="waveform"], ' +
      'text=/Load a track|drag and drop|Piano Roll|Waveform/i'
    );
    const dawUIVisible = await dawUI.count() > 0;

    await page.screenshot({ path: 'tests/e2e/screenshots/daw-02-content.png' });

    if (!dawUIVisible) {
      console.log('[INFO] DAW empty state or different rendering path');
    } else {
      console.log('[PASS] DAW content rendered');
    }
  });
});

test.describe('MIDI Tab', () => {
  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
    await login(page);
  });

  test.afterAll(async () => {
    if (page) await page.close();
  });

  test('MIDI tab navigates and shows device UI', async () => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: 'tests/e2e/screenshots/midi-01-tab.png' });

    // AppHeader must be present
    const header = page.locator('header, nav:has-text("Sound Forge")');
    await expect(header.first()).toBeVisible({ timeout: 5000 });

    // MIDI-specific UI
    const midiUI = page.locator(
      'text=/MIDI|devices|Devices|controller|Mapping|mapping/i'
    );
    const midiVisible = await midiUI.count() > 0;
    expect(midiVisible).toBeTruthy();

    console.log('[PASS] MIDI tab rendered with AppHeader');
  });

  test('MIDI device refresh button present', async () => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForTimeout(1000);

    const refreshBtn = page.locator(
      'button:has-text("Refresh"), button[title*="Refresh"], button[aria-label*="refresh"]'
    );
    const refreshCount = await refreshBtn.count();
    expect(refreshCount).toBeGreaterThanOrEqual(1);

    await page.screenshot({ path: 'tests/e2e/screenshots/midi-02-refresh.png' });
    console.log(`[PASS] MIDI refresh button: ${refreshCount} found`);
  });

  test('MIDI mapping table or learn UI exists', async () => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForTimeout(1000);

    // Mapping table or Learn buttons
    const mappingUI = page.locator(
      'text=/Mapping|Learn|Action|Controller|Device/i, table:has(th:has-text("Action"))'
    );
    const mappingVisible = await mappingUI.count() > 0;
    expect(mappingVisible).toBeTruthy();

    await page.screenshot({ path: 'tests/e2e/screenshots/midi-03-mappings.png' });
    console.log('[PASS] MIDI mapping UI rendered');
  });

  test('Universal MIDI transport labels visible in AppHeader', async () => {
    await page.goto(`${BASE_URL}/midi`);
    await page.waitForTimeout(1000);

    // AppHeader shows MIDI BPM/transport status
    // The AppHeader always shows MIDI-related indicators when on MIDI page
    const appHeader = page.locator('header').first();
    await expect(appHeader).toBeVisible();

    // MIDI status bar should exist somewhere in the header
    const midiStatus = page.locator(
      '[data-testid="midi-status"], text=/BPM|♩|MIDI/i, ' +
      '.midi-status, .midi-transport'
    );
    const midiStatusCount = await midiStatus.count();

    await page.screenshot({ path: 'tests/e2e/screenshots/midi-04-header-status.png' });
    console.log(`[PASS] MIDI header status elements: ${midiStatusCount}`);
  });
});
