const CACHE_NAME = 'sfa-shell-v2';
// Only cache resources we know exist; use individual try-catch to be resilient
const SHELL_URLS = [
  '/'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      // Add shell URLs — addAll fails the whole batch on any 404, so add individually
      for (const url of SHELL_URLS) {
        try {
          await cache.add(url);
        } catch (e) {
          // Non-fatal: individual resource failed, continue with rest
          console.warn('[SW] Failed to cache:', url, e.message);
        }
      }
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Network-first for HTML (LiveView needs fresh content)
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).catch(() => caches.match('/'))
    );
    return;
  }

  // Cache-first for static assets (css, js, images)
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request).then((response) => {
        if (response.ok && (
          event.request.url.includes('/assets/css/') ||
          event.request.url.includes('/assets/js/') ||
          event.request.url.includes('/images/')
        )) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      });
    })
  );
});
