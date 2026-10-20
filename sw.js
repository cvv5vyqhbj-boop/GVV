/* ADVEC — Service Worker
   Objetivo: o app abre mesmo sem internet (culto no salão com Wi-Fi ruim).
   Estratégia:
   • index.html  → network-first (pega atualização quando dá, cai pro cache se não)
   • CDNs/ícones → cache-first (bibliotecas são estáveis)
   • Supabase    → nunca cacheia (dado precisa ser fresco); offline vira erro
                   tratado pela fila do app.
*/
const VERSION = "gvv-v17";
const SHELL = `${VERSION}-shell`;
const ASSETS = `${VERSION}-assets`;

// Dependências externas que o app precisa para abrir
const CDN = [
  "https://cdn.tailwindcss.com",
  "https://unpkg.com/react@18/umd/react.production.min.js",
  "https://unpkg.com/react-dom@18/umd/react-dom.production.min.js",
  "https://unpkg.com/@babel/standalone/babel.min.js",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",
  "https://cdn.jsdelivr.net/npm/chart.js@4",
  "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js",
  "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css",
  "https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js",
  "https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css",
  "https://unpkg.com/@maplibre/maplibre-gl-leaflet@0.1.1/leaflet-maplibre-gl.js",
];
const LOCAL = ["/", "/index.html", "/manifest.webmanifest", "/icon-192.png", "/icon-512.png", "/map-style.json"];

self.addEventListener("install", (e) => {
  e.waitUntil((async () => {
    const shell = await caches.open(SHELL);
    await shell.addAll(LOCAL).catch(() => {});
    const assets = await caches.open(ASSETS);
    /* Tenta CORS primeiro: React/ReactDOM são carregados com `crossorigin`,
       e uma resposta opaca não passaria na checagem quando servida offline.
       Se o CDN não permitir CORS, cai para no-cors (resposta opaca serve
       para os scripts sem `crossorigin`). */
    await Promise.all(CDN.map(async (url) => {
      try {
        const r = await fetch(url, { mode: "cors", cache: "reload" });
        if (r && r.ok) { await assets.put(url, r); return; }
      } catch (_) {}
      try {
        const r2 = await fetch(url, { mode: "no-cors", cache: "reload" });
        await assets.put(url, r2);
      } catch (_) {}
    }));
    self.skipWaiting();
  })());
});

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener("message", (e) => {
  if (e.data === "skipWaiting") self.skipWaiting();
});

const isSupabase = (u) => u.hostname.endsWith(".supabase.co");
const isMapTile = (u) => (u.hostname === "tile.openstreetmap.org" || u.hostname.endsWith(".tile.openstreetmap.org"));

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;                 // POST/PATCH nunca passam por aqui
  const url = new URL(req.url);

  if (isSupabase(url)) return;                      // dado sempre da rede
  if (isMapTile(url) || url.hostname === "tiles.openfreemap.org") return;                       // tiles: deixa o navegador cuidar

  // Navegação (abrir o app): network-first com fallback pro cache
  if (req.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        const c = await caches.open(SHELL);
        c.put("/index.html", fresh.clone());
        return fresh;
      } catch (_) {
        const c = await caches.open(SHELL);
        return (await c.match("/index.html")) || (await c.match("/")) || Response.error();
      }
    })());
    return;
  }

  const sameOrigin = url.origin === self.location.origin;

  /* Recursos EXTERNOS (CDNs, fontes): network-first.
     Servir script de terceiro a partir do cache pode quebrar a execução
     (respostas cors/opaque replayadas). Online usa sempre a rede; o cache
     existe só para o app abrir sem internet. */
  if (!sameOrigin) {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        if (fresh && (fresh.ok || fresh.type === "opaque")) {
          const c = await caches.open(ASSETS);
          c.put(req, fresh.clone()).catch(() => {});
        }
        return fresh;
      } catch (_) {
        const hit = await caches.match(req, { ignoreVary: true });
        return hit || Response.error();
      }
    })());
    return;
  }

  // Arquivos do próprio site: cache-first (são estáveis e seguros de replayar)
  event.respondWith((async () => {
    const cached = await caches.match(req);
    if (cached) return cached;
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.ok) {
        const c = await caches.open(SHELL);
        c.put(req, fresh.clone()).catch(() => {});
      }
      return fresh;
    } catch (_) {
      return Response.error();
    }
  })());
});
