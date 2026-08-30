/* LodiStudios service worker.
   v1 listed /mediaplayer/css/player.css and /mediaplayer/js/player.js, which
   never existed at those paths. cache.addAll() is all-or-nothing, so a single
   404 aborted the install and the worker never activated. Paths corrected and
   the precache is now fault-tolerant. */

const VERSION = 'v3';
const SHELL_CACHE = `lodistudios-shell-${VERSION}`;
const MEDIA_CACHE = `lodistudios-media-${VERSION}`;

const SHELL = [
  '/mediaplayer/',
  '/mediaplayer/player.html',
  '/mediaplayer/player.css',
  '/mediaplayer/player.js',
  '/mediaplayer/manifest.json',
  '/mediaplayer/favicon.ico',
  '/mediaplayer/favicon-32x32.png',
  '/mediaplayer/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // Add individually so one bad URL can't sink the whole install.
    await Promise.all(SHELL.map((url) =>
      cache.add(new Request(url, { cache: 'reload' })).catch(() => {})
    ));
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter((k) => k !== SHELL_CACHE && k !== MEDIA_CACHE).map((k) => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Audio uses range requests; let the network handle it untouched.
  if (url.pathname.startsWith('/mediaplayer/songs/')) return;

  // Catalogue: network first so new uploads appear, cache as the fallback.
  if (url.pathname.endsWith('/meta/index.json')) {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(request);
        const cache = await caches.open(SHELL_CACHE);
        cache.put(request, fresh.clone());
        return fresh;
      } catch {
        return (await caches.match(request)) || Response.error();
      }
    })());
    return;
  }

  // Album art: cache first, it never changes under the same name.
  if (url.pathname.startsWith('/mediaplayer/albumart/')) {
    event.respondWith((async () => {
      const hit = await caches.match(request);
      if (hit) return hit;
      const res = await fetch(request);
      if (res.ok) (await caches.open(MEDIA_CACHE)).put(request, res.clone());
      return res;
    })());
    return;
  }

  // Everything else: cache first, refresh in the background.
  event.respondWith((async () => {
    const hit = await caches.match(request);
    const network = fetch(request).then((res) => {
      if (res.ok) caches.open(SHELL_CACHE).then((c) => c.put(request, res.clone()));
      return res;
    }).catch(() => hit);
    return hit || network;
  })());
});
