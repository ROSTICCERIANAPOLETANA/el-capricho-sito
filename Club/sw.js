const CACHE='el-capricho-club-v7';
const SHELL=['./','./index.html','./manifest.webmanifest','../logo.png'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)));self.skipWaiting()});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('el-capricho-club-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',event=>{const req=event.request;if(req.method!=='GET')return;const url=new URL(req.url);if(req.mode==='navigate'){
  event.respondWith(fetch(req,{cache:'no-store'}).then(res=>{if(res.ok&&url.origin===location.origin){const copy=res.clone();caches.open(CACHE).then(cache=>cache.put(req,copy))}return res}).catch(async()=>{const exact=await caches.match(req);if(exact)return exact;if(url.pathname==='/Club/'||url.pathname==='/Club/index.html')return caches.match('./index.html');return new Response('Offline',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}})}));return}
if(url.origin===location.origin){event.respondWith(fetch(req,{cache:'no-store'}).then(res=>{if(res.ok){const copy=res.clone();caches.open(CACHE).then(cache=>cache.put(req,copy))}return res}).catch(()=>caches.match(req)));}
});