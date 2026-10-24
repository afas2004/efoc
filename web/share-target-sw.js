// Efoc — share target worker.
//
// Android Chrome posts the shared file to /share (see share_target in
// manifest.json). A service worker is the only thing that can hold that POST:
// the app is a static page, so without this the request 404s or is dropped.
//
// It stores the file in the Cache API, then bounces the browser to
// /?shared=1. The app reads the cache entry on boot, imports it, and deletes
// it. Scope is /share, so this never intercepts the app's own requests.

const CACHE = 'efoc-share-v1';
const KEY = '/__efoc_share__';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'POST') return;
  if (url.origin !== self.location.origin) return;
  if (url.pathname !== '/share' && url.pathname !== '/share/') return;

  event.respondWith(handleShare(event.request));
});

async function handleShare(request) {
  try {
    const form = await request.formData();
    const file = form.get('media');

    if (file && typeof file === 'object') {
      const buf = await file.arrayBuffer();
      const payload = JSON.stringify({
        name: file.name || 'shared',
        type: file.type || '',
        b64: toBase64(new Uint8Array(buf)),
      });
      const cache = await caches.open(CACHE);
      await cache.put(
        KEY,
        new Response(payload, {
          headers: { 'content-type': 'application/json' },
        })
      );
    }
  } catch (e) {
    // Still send the user into the app; it will simply find nothing waiting.
  }

  // 303 turns the POST into a GET on the app.
  return Response.redirect('/?shared=1', 303);
}

function toBase64(bytes) {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(
      null,
      bytes.subarray(i, Math.min(i + chunk, bytes.length))
    );
  }
  return btoa(binary);
}
