// Ubah angka versi ini setiap kali ada pembaruan besar (opsional; update otomatis tetap jalan tanpa ini).
const CACHE_NAME = 'keuangan-app-shell-v4';
const SHELL_FILES = ['./index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.all(SHELL_FILES.map((f) => fetch(new Request(f, { cache: 'reload' })).then((r) => r.ok && cache.put(f, r)).catch(() => {})))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Network-first: selalu ambil versi terbaru dari server; cache hanya dipakai kalau offline.
// Data keuangan tetap langsung ke Supabase (tidak lewat sini).
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const isShell = req.mode === 'navigate' || SHELL_FILES.some((f) => url.pathname.endsWith(f.replace('./', ''))) || url.pathname.endsWith('/');
  if (!isShell) return;
  event.respondWith(
    fetch(req, { cache: 'no-cache' }).then((res) => {
      if (res && res.ok) { const copy = res.clone(); caches.open(CACHE_NAME).then((c) => c.put(req.mode === 'navigate' ? './index.html' : req, copy)).catch(() => {}); }
      return res;
    }).catch(() => caches.match(req).then((c) => c || caches.match('./index.html')))
  );
});
