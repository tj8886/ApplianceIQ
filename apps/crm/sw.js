// IQ CRM Service Worker — Offline PWA support
// Caches app shell + Supabase JS. Queues mutations offline, syncs on reconnect.
const CACHE_NAME = 'iq-crm-v1';
const APP_SHELL = [
  './',
  './index.html',
  'https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600;700;800&display=swap',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js',
  'https://ai-iq-coach.netlify.app/widget.js'
];

// Install: cache app shell
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
  );
});

// Activate: clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

// Fetch: network-first for API calls, cache-first for app shell
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // API calls (Supabase REST/functions): network-first
  if (url.hostname.includes('supabase') || url.pathname.includes('/functions/')) {
    event.respondWith(
      fetch(event.request).catch(() => {
        // Offline: if it's a mutation (POST/PATCH/DELETE), queue it
        if (event.request.method !== 'GET') {
          return event.request.clone().text().then(body => {
            return queueMutation({
              url: event.request.url,
              method: event.request.method,
              headers: Object.fromEntries(event.request.headers.entries()),
              body: body,
              timestamp: Date.now()
            });
          }).then(() => new Response(JSON.stringify({ queued: true, offline: true }), {
            status: 202,
            headers: { 'Content-Type': 'application/json' }
          }));
        }
        // GET requests: try cache
        return caches.match(event.request);
      })
    );
    return;
  }

  // App shell + static assets: cache-first, network fallback
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        // Cache successful responses for future offline use
        if (response.ok && (url.protocol === 'https:' || url.hostname === 'localhost')) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => {
        // Last resort: return cached index for navigation requests
        if (event.request.mode === 'navigate') {
          return caches.match('./index.html');
        }
      });
    })
  );
});

// Offline mutation queue using IndexedDB
const DB_NAME = 'iq-crm-offline';
const STORE_NAME = 'mutations';

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE_NAME, { autoIncrement: true });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function queueMutation(mutation) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).add(mutation);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
}

async function syncMutations() {
  const db = await openDB();
  const tx = db.transaction(STORE_NAME, 'readonly');
  const store = tx.objectStore(STORE_NAME);
  const keys = await new Promise(r => { const req = store.getAllKeys(); req.onsuccess = () => r(req.result); });
  const mutations = await new Promise(r => { const req = store.getAll(); req.onsuccess = () => r(req.result); });

  let synced = 0;
  for (let i = 0; i < mutations.length; i++) {
    const m = mutations[i];
    try {
      await fetch(m.url, {
        method: m.method,
        headers: m.headers,
        body: m.body
      });
      // Delete synced mutation
      const delTx = db.transaction(STORE_NAME, 'readwrite');
      delTx.objectStore(STORE_NAME).delete(keys[i]);
      synced++;
    } catch (e) {
      // Still offline, stop trying
      break;
    }
  }

  // Notify clients about sync
  if (synced > 0) {
    const clients = await self.clients.matchAll();
    clients.forEach(client => client.postMessage({ type: 'sync-complete', count: synced }));
  }
}

// Listen for online event to sync
self.addEventListener('message', event => {
  if (event.data === 'sync') syncMutations();
});

// Background sync (where supported)
self.addEventListener('sync', event => {
  if (event.tag === 'crm-sync') {
    event.waitUntil(syncMutations());
  }
});
