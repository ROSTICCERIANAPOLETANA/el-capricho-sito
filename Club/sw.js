const CACHE='el-capricho-club-v2';
const ASSETS=['./','./index.html','./manifest.webmanifest','../logo.png'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET') return;
  if(req.mode==='navigate'){
    event.respondWith(fetch(req).then(res=>{
      const copy=res.clone();
      caches.open(CACHE).then(cache=>cache.put('./index.html',copy));
      return res;
    }).catch(()=>caches.match('./index.html')));
    return;
  }
  event.respondWith(caches.match(req).then(cached=>cached||fetch(req)));
});
