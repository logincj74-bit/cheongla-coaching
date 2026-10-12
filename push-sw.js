// Push only: never cache authenticated pages, API responses or private files.
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{};}catch{}
 const id=typeof data.notificationId==='string'&&/^[0-9a-f-]{36}$/i.test(data.notificationId)?data.notificationId:'';
 const body=typeof data.body==='string'?data.body.slice(0,200):'새 알림이 도착했습니다. 앱에서 확인해 주세요.';
 event.waitUntil(self.registration.showNotification('청라 알림',{body,tag:id?'cheongla-'+id:'cheongla-alert',icon:new URL('assets/cheongla-ci-korean.webp',self.registration.scope).href,data:{notificationId:id}}));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const id=event.notification.data?.notificationId||'';
 const destination=new URL('./',self.registration.scope);
 if(/^[0-9a-f-]{36}$/i.test(id))destination.searchParams.set('push',id);
 event.waitUntil((async()=>{
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  for(const client of windows){if(client.url.startsWith(self.registration.scope)){await client.navigate(destination.href);return client.focus();}}
  return self.clients.openWindow(destination.href);
 })());
});
