const CACHE_NAME = "lodistudios-mediaplayer-v1";
const urlsToCache = [
  "/mediaplayer/",
  "/mediaplayer/index.html",
  "/mediaplayer/meta/index.json",
  "/mediaplayer/css/player.css",
  "/mediaplayer/js/player.js",
  "/mediaplayer/favicon.ico"
];

// Install event – cache essential files
self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(urlsToCache);
    })
  );
});

// Fetch event – try cache, fallback to network
self.addEventListener("fetch", event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => response || fetch(event.request))
  );
});

// Activate event – clean old caches if needed
self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keyList => {
      return Promise.all(
        keyList.map(key => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );
});
