import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const code=html.slice(html.indexOf('let pushRequest=0,pushConfig=null,pushBusy=false,'),html.indexOf('async function detachDevicePush'));
function fixture({permission='granted',owned=false,sub=true,role='student',approved=true,ios=false,installed=true,subscribeFails=false,stale=false}={}){
 const nodes=new Map(),memory=new Map(),calls={prompt:0,subscribe:0,save:0,config:0,unsubscribe:0};
 let currentSub=sub?subscription():null,currentOwned=owned;
 function subscription(){return{endpoint:'https://push.example.invalid/test',options:{applicationServerKey:Uint8Array.of(1,2,3).buffer},toJSON:()=>({endpoint:'https://push.example.invalid/test',keys:{p256dh:'test-public',auth:'test-auth'}}),unsubscribe:async()=>{calls.unsubscribe++;currentSub=null;}};}
 const registration={pushManager:{getSubscription:async()=>currentSub,subscribe:async()=>{calls.subscribe++;if(subscribeFails)throw Error('Gesture required');currentSub=subscription();return currentSub;}}};
 const client={rpc:async(name)=>{if(name==='cheongla_push_config'){calls.config++;if(stale)ctx.currentProfile={id:'other',approval_status:'approved'};return{data:{enabled:true,public_key:'AQID'}};}if(name==='cheongla_push_device_status')return{data:currentOwned};if(name==='cheongla_save_push_subscription'){calls.save++;currentOwned=true;return{data:true};}throw Error(name);}};
 const ctx={currentProfile:{id:'member',role,approval_status:approved?'approved':'pending'},$:id=>{if(!nodes.has(id))nodes.set(id,{hidden:false,disabled:false,textContent:'',addEventListener(){}});return nodes.get(id);},canUseInbox:()=>ctx.currentProfile?.approval_status==='approved',isAppAdmin:()=>false,getClient:async()=>client,readable:e=>e.message,atob:v=>Buffer.from(v,'base64').toString('binary'),setInterval(){},localStorage:{getItem:k=>memory.get(k),setItem:(k,v)=>memory.set(k,v),removeItem:k=>memory.delete(k)},Notification:{permission,requestPermission:async()=>{calls.prompt++;ctx.Notification.permission='granted';return'granted';}},navigator:{userAgent:ios?'iPhone':'Chrome',platform:'test',maxTouchPoints:0,serviceWorker:{getRegistration:async()=>registration,register:async()=>registration,ready:Promise.resolve(registration)}},window:{PushManager(){},Notification:{},matchMedia:()=>({matches:installed}),addEventListener(){}},document:{hidden:false,addEventListener(){}},Date};
 vm.createContext(ctx);vm.runInContext(code,ctx);return{ctx,calls,nodes};
}
for(const role of ['student','parent','owner','english_director','math_director','manager','korean_teacher']){
 const f=fixture({role});await f.ctx.loadPushSettings();assert.equal(f.calls.save,1,role);assert.equal(f.calls.prompt,0);assert.equal(f.calls.subscribe,0);assert.equal(f.nodes.get('pushSetupBanner').hidden,true);
 await f.ctx.loadPushSettings();assert.equal(f.calls.save,1,'healthy subscription should not re-register');
}
for(const permission of ['default','denied']){const f=fixture({permission,sub:false});await f.ctx.loadPushSettings();assert.equal(f.calls.prompt,0);assert.equal(f.calls.subscribe,0);assert.equal(f.nodes.get('pushSetupBanner').hidden,false);if(permission==='denied')assert.equal(f.nodes.get('pushSetupEnable').hidden,true);}
{const f=fixture({permission:'default',sub:false});await f.ctx.loadPushSettings();await f.ctx.enableDevicePush();assert.equal(f.calls.prompt,1);assert.equal(f.calls.subscribe,1);assert.equal(f.calls.save,1);}
{const f=fixture({sub:false});await f.ctx.loadPushSettings();assert.equal(f.calls.subscribe,1);assert.equal(f.calls.save,1);assert.equal(f.calls.prompt,0);}
{const f=fixture({sub:false});f.ctx.setPushOptOut(true);await f.ctx.loadPushSettings();assert.equal(f.calls.save,0);assert.equal(f.calls.subscribe,0);await f.ctx.enableDevicePush();assert.equal(f.calls.save,1);assert.equal(f.ctx.pushOptedOut(),false);}
{const f=fixture({ios:true,installed:false,sub:false});await f.ctx.loadPushSettings();assert.equal(f.calls.subscribe,0);assert.match(f.nodes.get('pushSetupStatus').textContent,/홈 화면/);}
{const f=fixture({approved:false});await f.ctx.loadPushSettings();assert.equal(f.calls.config,0);}
{const f=fixture({stale:true});await f.ctx.loadPushSettings();assert.equal(f.calls.save,0);assert.equal(f.calls.subscribe,0);}
{const f=fixture({sub:false,subscribeFails:true});await f.ctx.loadPushSettings();assert.equal(f.calls.save,0);assert.equal(f.nodes.get('pushSetupBanner').hidden,false);assert.equal(f.nodes.get('pushSetupEnable').disabled,false);}
{const f=fixture();await Promise.all([f.ctx.loadPushSettings(),f.ctx.loadPushSettings()]);assert.equal(f.calls.config,1);assert.equal(f.calls.save,1);}
assert.match(html,/appConfirm\('이 기기의 푸시 알림을 끄시겠습니까/);
console.log('PASS push maintenance: all approved roles, no unsolicited permission prompts, reuse/repair, user opt-out, initial permission, iOS install guidance, pending/stale-session guards, gesture fallback, concurrent check dedupe. No live pushes sent.');
