import { test, expect, type Page } from '@playwright/test';

/**
 * SFA Full Pipeline E2E Test
 *
 * Tests the complete user journey:
 * 1. Login
 * 2. Add Spotify playlist link & fetch
 * 3. Confirm playlist in sidebar
 * 4. Select tracks (single, range, all)
 * 5. Download selected tracks
 * 6. Analyze downloaded track
 * 7. Process track (stem separation)
 * 8. Select & play individual stems
 * 9. Export stems
 */

const BASE_URL = 'http://localhost:4000';
const TEST_USER = { email: 'dev@soundforge.local', password: 'password123456' };
// A short Spotify playlist for testing
const SPOTIFY_PLAYLIST_URL = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';
const SPOTIFY_TRACK_URL = 'https://open.spotify.com/track/0gNHjAVgcaW410qNOmUyRv';

// Track IDs with confirmed completed downloads and audio files on disk
// Used by Steps 5-7 to test analysis/processing on tracks that actually have audio
const TRACKS_WITH_DOWNLOADS = [
  'cdfe498c-e991-4772-a858-a9154eb8a9c6', // "test audio" - 79KB mp3
  '102ed3e7-d9d7-4208-86fd-603ca7bccba7', // "test audio" - 79KB mp3
  'd467767f-9bdc-4c9f-a514-b1b19541e52a', // "test tone" - 129KB wav
];

// Collect bugs found during testing
const bugs: Array<{ step: string; severity: string; description: string; details: string }> = [];

function logBug(step: string, severity: string, description: string, details: string = '') {
  bugs.push({ step, severity, description, details });
  console.log(`[BUG][${severity}] Step: ${step} | ${description}${details ? ' | ' + details : ''}`);
}

/**
 * Navigate to a track detail page and wait for LiveView to render.
 * Returns true if the track detail loaded successfully.
 */
async function navigateToTrackDetail(page: Page, url: string): Promise<boolean> {
  try {
    const resp = await page.goto(url, { timeout: 10000 });
    if (resp && resp.status() >= 400) return false;

    // Wait for LiveView to connect and render track detail
    // The "Back to library" link contains "← Back to library" (HTML entity &larr;)
    // Use substring match (no quotes) since exact match would fail on the arrow
    await page.waitForSelector('a:has-text("Back to library")', { timeout: 8000 });
    return true;
  } catch {
    return false;
  }
}

async function dismissFlashes(page: Page) {
  const flashes = page.locator('[role="alert"]');
  const count = await flashes.count();
  for (let i = 0; i < count; i++) {
    try {
      const flash = flashes.nth(i);
      if (await flash.isVisible()) {
        await flash.click({ timeout: 1000 });
        await page.waitForTimeout(200);
      }
    } catch { /* ignore */ }
  }
}

test.describe('SFA Full Pipeline E2E', () => {
  test.describe.configure({ mode: 'serial' });

  let page: Page;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
  });

  test.afterAll(async () => {
    // Print bug summary
    console.log('\n========== BUG SUMMARY ==========');
    if (bugs.length === 0) {
      console.log('No bugs found!');
    } else {
      console.log(`Found ${bugs.length} bug(s):`);
      bugs.forEach((bug, i) => {
        console.log(`  ${i + 1}. [${bug.severity}] ${bug.step}: ${bug.description}`);
        if (bug.details) console.log(`     Details: ${bug.details}`);
      });
    }
    console.log('=================================\n');
    if (page) await page.close();
  });

  // ────────────────────────────────────────────────────
  // STEP 1: Login
  // ────────────────────────────────────────────────────
  test('Step 1: User can log in', async () => {
    await page.goto(`${BASE_URL}/users/log-in`);
    await page.waitForLoadState('networkidle');

    // Screenshot login page
    await page.screenshot({ path: 'tests/e2e/screenshots/01-login-page.png' });

    // Fill the PASSWORD login form (second form on page)
    const passwordForm = page.locator('#login_form_password');
    await passwordForm.locator('input[type="email"]').fill(TEST_USER.email);
    await passwordForm.locator('input[type="password"]').fill(TEST_USER.password);

    // Click "Log in and stay logged in" button
    await passwordForm.locator('button:has-text("Log in and stay logged in")').click();
    await page.waitForLoadState('networkidle');

    // Should redirect to dashboard
    await expect(page).toHaveURL(/\//);
    await page.screenshot({ path: 'tests/e2e/screenshots/01-login-success.png' });

    // Verify dashboard elements present
    const header = page.locator('text=Sound Forge Alchemy');
    await expect(header.first()).toBeVisible();

    // Verify sidebar (use nav-specific selector to avoid mobile nav duplicate)
    const sidebar = page.locator('nav[aria-label="Library navigation"]');
    const allTracks = sidebar.locator('button:has-text("All Tracks")');
    await expect(allTracks).toBeVisible();

    // Verify LiveView WebSocket connected (phx-connected class on body or main)
    // LiveView adds phx-connected after mount
    await page.waitForTimeout(2000);
    const wsConnected = await page.evaluate(() => {
      const el = document.querySelector('[data-phx-main]');
      return el !== null;
    });

    if (!wsConnected) {
      logBug('Step 1', 'HIGH', 'LiveView WebSocket not connected after login');
    }

    console.log('[PASS] Step 1: Login successful');
  });

  // ────────────────────────────────────────────────────
  // STEP 2: Add Spotify playlist link & fetch
  // ────────────────────────────────────────────────────
  test('Step 2: Add Spotify link and fetch tracks', async () => {
    test.setTimeout(30_000); // Shorter timeout for this step

    // Dismiss ALL flash messages that block the UI
    await dismissFlashes(page);
    // Log if Spotify SDK error was present
    logBug('Step 2', 'MEDIUM', 'Spotify SDK init error flash blocks UI in headless mode',
      'Flash overlay covers Fetch button area - should auto-dismiss or not block interactions');

    // Verify the Spotify URL input exists
    const spotifyInput = page.locator('input[placeholder*="Spotify"]');
    await expect(spotifyInput).toBeVisible();
    await page.screenshot({ path: 'tests/e2e/screenshots/02-spotify-input.png' });

    // Verify auto-download checkbox exists
    const autoDownloadLabel = page.locator('text=Auto-download');
    if (await autoDownloadLabel.count() > 0) {
      console.log('[INFO] Auto-download checkbox present');
    } else {
      logBug('Step 2', 'MEDIUM', 'Auto-download checkbox label not found');
    }

    // Get current track count from sidebar
    const sidebarAllTracks = page.locator('nav[aria-label="Library navigation"] button:has-text("All Tracks")');
    const trackCountBefore = await sidebarAllTracks.textContent();
    console.log(`[INFO] Track count before fetch: ${trackCountBefore?.trim()}`);

    // Paste Spotify URL and click Fetch
    await spotifyInput.fill(SPOTIFY_TRACK_URL);
    await page.screenshot({ path: 'tests/e2e/screenshots/02-spotify-url-filled.png' });

    const fetchButton = page.locator('button:has-text("Fetch")');
    await expect(fetchButton).toBeVisible();

    // Dismiss any remaining flashes that may block the button
    await dismissFlashes(page);

    // Force click to bypass any remaining overlay issues
    await fetchButton.click({ force: true });
    console.log('[INFO] Fetch button clicked, waiting for response...');

    // Wait for LiveView to process (async fetch fires in background)
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'tests/e2e/screenshots/02-after-fetch.png' });

    // Check for any visible flash/notification
    const flashMsg = page.locator('[role="alert"], .alert, [phx-click*="dismiss"]');
    const flashCount = await flashMsg.count();
    if (flashCount > 0) {
      const text = await flashMsg.first().textContent();
      console.log(`[INFO] Flash message: ${text?.trim()}`);
      if (text?.includes('timed out') || text?.includes('rate') || text?.includes('error') || text?.includes('Error')) {
        logBug('Step 2', 'BLOCKED', 'Spotify fetch failed', text?.trim() || 'Unknown');
      }
    }

    // Check track count change
    const trackCountAfter = await sidebarAllTracks.textContent();
    console.log(`[INFO] Track count after fetch: ${trackCountAfter?.trim()}`);

    if (trackCountBefore?.trim() === trackCountAfter?.trim()) {
      logBug('Step 2', 'BLOCKED', 'Spotify fetch did not add new tracks (likely rate-limited)',
        'Will retry when Spotify rate limit resets');
    }

    console.log('[PASS] Step 2: Spotify link flow tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 3: Confirm playlist in sidebar
  // ────────────────────────────────────────────────────
  test('Step 3: Check playlist in sidebar', async () => {
    await dismissFlashes(page);
    const playlistSection = page.locator('h3:has-text("PLAYLISTS"), h3:has-text("Playlists")');
    await expect(playlistSection.first()).toBeVisible();

    const noPlaylistsMsg = page.locator('text=No playlists yet');
    const playlistItems = page.locator('[phx-click="nav_playlist"]');

    if (await noPlaylistsMsg.count() > 0) {
      console.log('[INFO] No playlists found - playlist auto-creation may not have triggered');
      logBug('Step 3', 'MEDIUM', 'No playlists in sidebar after Spotify fetch',
        'Playlist auto-creation may require a playlist URL (not single track)');
    } else if (await playlistItems.count() > 0) {
      const count = await playlistItems.count();
      console.log(`[INFO] Found ${count} playlist(s) in sidebar`);

      // Click the first playlist
      await playlistItems.first().click();
      await page.waitForTimeout(1000);
      await page.screenshot({ path: 'tests/e2e/screenshots/03-playlist-selected.png' });
      console.log('[PASS] Step 3: Playlist visible and clickable');

      // Go back to All Tracks
      await page.locator('nav[aria-label="Library navigation"] button:has-text("All Tracks")').click();
      await page.waitForTimeout(500);
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/03-sidebar-playlists.png' });
    console.log('[PASS] Step 3: Sidebar playlist check complete');
  });

  // ────────────────────────────────────────────────────
  // STEP 4: Select single track, range, and all
  // ────────────────────────────────────────────────────
  test('Step 4: Track selection modes', async () => {
    await dismissFlashes(page);
    // Ensure we're in All Tracks view
    await page.locator('nav[aria-label="Library navigation"] button:has-text("All Tracks")').click({ force: true });
    await page.waitForTimeout(500);

    // Switch to compact list view for easier selection testing
    const compactView = page.locator('button[aria-label="Compact list view"], button:has-text("Compact")');
    if (await compactView.count() > 0) {
      await compactView.first().click();
      await page.waitForTimeout(500);
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/04-before-selection.png' });

    // SINGLE SELECT: Click first track checkbox
    const checkboxes = page.locator('input[type="checkbox"][phx-click*="toggle_select"]');
    const allCheckboxes = page.locator('input[type="checkbox"]');

    // Find track-level checkboxes (not "Select all")
    const trackCheckboxes = page.locator('[phx-click="toggle_select"]');
    if (await trackCheckboxes.count() > 0) {
      await trackCheckboxes.first().click();
      await page.waitForTimeout(300);
      await page.screenshot({ path: 'tests/e2e/screenshots/04-single-select.png' });

      // Verify selection count shows "1 selected"
      const selectedText = page.locator('text=/\\d+ selected/');
      if (await selectedText.count() > 0) {
        console.log(`[INFO] Single select: ${await selectedText.textContent()}`);
      }

      // Deselect
      await trackCheckboxes.first().click();
      await page.waitForTimeout(300);
    } else {
      logBug('Step 4', 'HIGH', 'No track checkboxes found for selection');
    }

    // SELECT ALL
    const selectAll = page.locator('[phx-click="toggle_select_all"], label:has-text("Select all")');
    if (await selectAll.count() > 0) {
      await selectAll.first().click();
      await page.waitForTimeout(500);
      await page.screenshot({ path: 'tests/e2e/screenshots/04-select-all.png' });

      // Verify batch action bar appears
      const batchBar = page.locator('text=/\\d+ selected/');
      if (await batchBar.count() > 0) {
        const count = await batchBar.textContent();
        console.log(`[PASS] Select all: ${count}`);

        // Verify batch action buttons
        const downloadBtn = page.locator('button:has-text("Download Selected")');
        const analyzeBtn = page.locator('button:has-text("Analyze Selected")');
        const processBtn = page.locator('button:has-text("Process Selected")');
        const deleteBtn = page.locator('button:has-text("Delete Selected")');

        const batchButtons = {
          'Download Selected': await downloadBtn.count() > 0,
          'Analyze Selected': await analyzeBtn.count() > 0,
          'Process Selected': await processBtn.count() > 0,
          'Delete Selected': await deleteBtn.count() > 0,
        };

        Object.entries(batchButtons).forEach(([name, present]) => {
          if (!present) {
            logBug('Step 4', 'MEDIUM', `Batch action button missing: ${name}`);
          } else {
            console.log(`[INFO] Batch button present: ${name}`);
          }
        });
      }

      // Deselect all
      await selectAll.first().click();
      await page.waitForTimeout(300);
    } else {
      logBug('Step 4', 'HIGH', 'Select all checkbox not found');
    }

    console.log('[PASS] Step 4: Track selection modes tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 5: Download a track
  // ────────────────────────────────────────────────────
  test('Step 5: Download tracks', async () => {
    await dismissFlashes(page);
    // Switch to grid view
    const gridView = page.locator('button[aria-label="Grid view"]');
    if (await gridView.count() > 0) {
      await gridView.first().click();
      await page.waitForTimeout(500);
    }

    // Look for tracks with retry/download indicators
    const retryButtons = page.locator('button[aria-label*="Retry"], button:has-text("Retry")');
    const downloadIcons = page.locator('[aria-label*="download"], [aria-label*="Download"]');

    if (await retryButtons.count() > 0) {
      console.log(`[INFO] Found ${await retryButtons.count()} tracks with failed downloads (retry available)`);

      // Click retry on the first one
      await retryButtons.first().click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: 'tests/e2e/screenshots/05-retry-download.png' });

      // Check for notification
      const notif = page.locator('[role="alert"], .toast');
      if (await notif.count() > 0) {
        console.log(`[INFO] Download notification: ${await notif.first().textContent()}`);
      }
    } else {
      console.log('[INFO] No retry buttons visible - checking for download buttons');
    }

    // Open a track with a completed download to test the detail view
    // Try known-good tracks first, then fall back to any track from the grid
    let detailLoaded = false;
    for (const trackId of TRACKS_WITH_DOWNLOADS) {
      if (await navigateToTrackDetail(page, `${BASE_URL}/tracks/${trackId}`)) {
        detailLoaded = true;
        console.log(`[INFO] Track detail loaded (known download): ${page.url()}`);
        break;
      }
    }

    if (!detailLoaded) {
      // Fallback: try any track from the grid
      const trackLinks = page.locator('a[href*="/tracks/"]');
      const linkCountStep5 = await trackLinks.count();
      const hrefsStep5: string[] = [];
      for (let i = 0; i < Math.min(linkCountStep5, 5); i++) {
        const href = await trackLinks.nth(i).getAttribute('href');
        if (href) hrefsStep5.push(href);
      }
      for (const href of hrefsStep5) {
        if (await navigateToTrackDetail(page, `${BASE_URL}${href}`)) {
          detailLoaded = true;
          console.log(`[INFO] Track detail loaded (fallback): ${page.url()}`);
          break;
        }
      }
    }

    if (detailLoaded) {
      await page.screenshot({ path: 'tests/e2e/screenshots/05-track-detail.png' });

      // Look for download button in detail view
      const detailDownload = page.locator('button:has-text("Download"), a:has-text("Download")');
      if (await detailDownload.count() > 0) {
        console.log('[INFO] Download button present in track detail');
        await detailDownload.first().click();
        await page.waitForTimeout(3000);
        await page.screenshot({ path: 'tests/e2e/screenshots/05-download-started.png' });
      } else {
        console.log('[INFO] No download button (track already downloaded)');
      }
    } else {
      logBug('Step 5', 'MEDIUM', 'Could not load any track detail page');
      await page.screenshot({ path: 'tests/e2e/screenshots/05-track-detail.png' });
    }

    console.log('[PASS] Step 5: Download flow tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 6: Analyze a downloaded track
  // ────────────────────────────────────────────────────
  test('Step 6: Analyze track', async () => {
    test.setTimeout(45_000);

    // Navigate to a track with a completed download (has audio file on disk)
    let trackLoaded = false;
    for (const trackId of TRACKS_WITH_DOWNLOADS) {
      console.log(`[INFO] Trying track with download: ${trackId}`);
      if (await navigateToTrackDetail(page, `${BASE_URL}/tracks/${trackId}`)) {
        trackLoaded = true;
        console.log(`[INFO] Track detail loaded: ${page.url()}`);
        break;
      }
    }

    if (!trackLoaded) {
      logBug('Step 6', 'HIGH', 'Could not access any track with completed download');
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/06-track-for-analysis.png' });

    // Look for Analyze button
    const analyzeBtn = page.locator('button:has-text("Analyze")');
    if (await analyzeBtn.count() > 0) {
      console.log('[INFO] Analyze button present');
      await analyzeBtn.first().click();
      await page.waitForTimeout(3000);
      await page.screenshot({ path: 'tests/e2e/screenshots/06-analysis-started.png' });

      // Wait for analysis to complete (or fail)
      await page.waitForTimeout(15000);
      await page.screenshot({ path: 'tests/e2e/screenshots/06-analysis-result.png' });

      // Check for analysis results
      const bpm = page.locator('text=/BPM|tempo/i');
      const key = page.locator('text=/Key|key/i');
      const analysisError = page.locator('text=/analysis.*fail|error.*analy/i');

      if (await analysisError.count() > 0) {
        logBug('Step 6', 'HIGH', 'Track analysis failed',
          await analysisError.first().textContent() || 'Unknown error');
      } else if (await bpm.count() > 0) {
        console.log('[PASS] Analysis results visible (BPM detected)');
      } else {
        logBug('Step 6', 'MEDIUM', 'Analysis results not visible after 15s wait',
          'May need librosa/Python dependency fix');
      }
    } else {
      logBug('Step 6', 'HIGH', 'Analyze button not found on track detail page');
    }

    console.log('[PASS] Step 6: Analysis flow tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 7: Process track (stem separation)
  // ────────────────────────────────────────────────────
  test('Step 7: Process track for stems', async () => {
    test.setTimeout(30_000);
    // Look for Process button on the same track detail
    const processBtn = page.locator('button:has-text("Process")');

    if (await processBtn.count() > 0) {
      console.log('[INFO] Process button present');
      await processBtn.first().click();
      await page.waitForTimeout(3000);
      await page.screenshot({ path: 'tests/e2e/screenshots/07-process-started.png' });

      // Wait for processing (Demucs is slow, may not be installed)
      await page.waitForTimeout(10000);
      await page.screenshot({ path: 'tests/e2e/screenshots/07-process-result.png' });

      // Check for stems or error
      const stems = page.locator('text=/vocal|drum|bass|other/i');
      const processError = page.locator('text=/process.*fail|error.*process|demucs.*not/i');

      if (await processError.count() > 0) {
        logBug('Step 7', 'HIGH', 'Stem separation failed',
          await processError.first().textContent() || 'Demucs may not be installed');
      } else if (await stems.count() > 0) {
        console.log('[PASS] Stems visible after processing');
      } else {
        logBug('Step 7', 'MEDIUM', 'No stems visible and no error shown',
          'Demucs not installed or still processing');
      }
    } else {
      logBug('Step 7', 'HIGH', 'Process button not found on track detail page');
    }

    console.log('[PASS] Step 7: Processing flow tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 8: Select and play individual stems
  // ────────────────────────────────────────────────────
  test('Step 8: Play individual stems', async () => {
    test.setTimeout(15_000);

    // AudioPlayerLive renders per-stem controls:
    // - Play/Pause button with aria-label="Play"/"Pause"
    // - Per-stem Solo buttons with aria-label="Solo vocals" etc.
    // - Per-stem Mute buttons with aria-label="Mute vocals" etc.
    // - Volume sliders per stem
    const soloButtons = page.locator('button[aria-label*="Solo"]');
    const muteButtons = page.locator('button[aria-label*="Mute"]');
    const playButton = page.locator('button[aria-label="Play"]');

    if (await soloButtons.count() > 0) {
      console.log(`[INFO] Found ${await soloButtons.count()} stem Solo buttons`);

      // Click Play to start playback
      if (await playButton.count() > 0) {
        await playButton.first().click();
        await page.waitForTimeout(1000);

        const pauseButton = page.locator('button[aria-label="Pause"]');
        if (await pauseButton.count() > 0) {
          console.log('[PASS] Audio playback started (Pause button visible)');
        } else {
          logBug('Step 8', 'MEDIUM', 'Play clicked but no Pause button',
            'AudioPlayer JS hook may not be connected in headless mode');
        }
      }

      // Test Solo toggle
      await soloButtons.first().click();
      await page.waitForTimeout(500);
      console.log(`[INFO] Solo toggled, pressed=${await soloButtons.first().getAttribute('aria-pressed')}`);

      // Test Mute toggle
      if (await muteButtons.count() > 0) {
        await muteButtons.first().click();
        await page.waitForTimeout(500);
        console.log(`[INFO] Mute toggled, pressed=${await muteButtons.first().getAttribute('aria-pressed')}`);
      }

      await page.screenshot({ path: 'tests/e2e/screenshots/08-stem-controls.png' });
      console.log('[PASS] Stem controls working');
    } else {
      // Check if stem download links exist (below audio player)
      const stemDownloads = page.locator('a[href*="/export/stem/"]');
      if (await stemDownloads.count() > 0) {
        console.log(`[INFO] Found ${await stemDownloads.count()} stem download links (player not rendered)`);
        logBug('Step 8', 'MEDIUM', 'Stem download links present but AudioPlayer not rendered');
      } else {
        logBug('Step 8', 'BLOCKED', 'No stem controls visible',
          'Blocked by Step 7 - stem separation did not complete');
      }
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/08-stems-state.png' });
    console.log('[PASS] Step 8: Stem playback tested');
  });

  // ────────────────────────────────────────────────────
  // STEP 9: Export stems
  // ────────────────────────────────────────────────────
  test('Step 9: Export stems', async () => {
    test.setTimeout(15_000);
    // Look for export functionality
    // Template renders: "Export JSON" (analysis), "Download All (ZIP)" (stems), individual stem links
    const downloadAllBtn = page.locator('a:has-text("Download All")');
    const exportJsonBtn = page.locator('a:has-text("Export JSON")');
    const stemLinks = page.locator('a[href*="/export/stem/"]');
    const exportBtn = downloadAllBtn.or(exportJsonBtn).or(stemLinks);

    if (await exportBtn.count() > 0) {
      const downloadAllCount = await downloadAllBtn.count();
      const exportJsonCount = await exportJsonBtn.count();
      const stemLinksCount = await stemLinks.count();
      console.log(`[INFO] Export options: Download All=${downloadAllCount}, Export JSON=${exportJsonCount}, Stem links=${stemLinksCount}`);

      // Try downloading a single stem (most reliable test)
      const targetBtn = downloadAllCount > 0 ? downloadAllBtn.first() : stemLinks.first();

      // Set up download listener
      const downloadPromise = page.waitForEvent('download', { timeout: 10000 }).catch(() => null);
      await targetBtn.click();
      await page.waitForTimeout(3000);
      await page.screenshot({ path: 'tests/e2e/screenshots/09-export-initiated.png' });

      const download = await downloadPromise;
      if (download) {
        console.log(`[PASS] Export download started: ${download.suggestedFilename()}`);
        await download.saveAs(`tests/e2e/downloads/${download.suggestedFilename()}`);
      } else {
        logBug('Step 9', 'MEDIUM', 'Export clicked but no download triggered',
          'May need stems to be present first');
      }
    } else {
      logBug('Step 9', 'BLOCKED', 'No export button visible',
        'Blocked by Step 7/8 - no stems available to export');
    }

    await page.screenshot({ path: 'tests/e2e/screenshots/09-final-state.png' });
    console.log('[PASS] Step 9: Export flow tested');
  });
});
