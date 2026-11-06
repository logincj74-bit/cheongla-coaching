const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8'),nid='12345678-1234-1234-1234-123456789012',eid='abcdefab-1234-1234-1234-123456789012';
function setup(mode='normal'){
 const calls=[],routes=[],nodes={},$=id=>nodes[id]??={textContent:''};let ctx;
 ctx=vm.createContext({console,$,currentProfile:{id:'actor',approval_status:'approved',role:'manager'},requestAnimationFrame(){},readable:e=>e.message,loadInbox(){},
  CheonglaStaffJournalUI:{allowed:()=>mode!=='student',dirty:mode==='dirty',leave:async()=>false},
  openSiteDestination:async(...args)=>routes.push(args),
  getClient:async()=>({from:()=>({select(){return this},eq(){return this},maybeSingle:async()=>({data:{id:nid,source_kind:'staff_journal',source_id:eid,route:'account_staffJournalPanel',inbox_until:'2099-01-01T00:00:00Z'}})}),rpc:async(name,args)=>{calls.push({name,args});if(name==='cheongla_journal_notification_context'){
   if(mode==='switched')ctx.currentProfile={id:'other',approval_status:'approved',role:'manager'};
   if(mode==='failure')return{error:Error('이 알림에 접근할 수 없습니다.')};
   return{data:{work_on:mode==='invalid'?'bad-date':'2026-11-12',archived:mode==='archived',purged:mode==='purged'}};
  }return{data:1};}})});
 vm.runInContext(html.slice(html.indexOf("let pendingNotificationId='';"),html.indexOf('function renderInbox(')),ctx);
 return{ctx,calls,routes,$};
}
(async()=>{
 for(const mode of ['normal','archived','purged']){const t=setup(mode);await t.ctx.navigateNotification(nid);assert.equal(t.routes[0][0],'account_staffJournalPanel');assert.equal(t.routes[0][1].work_date,'2026-11-12');assert.equal(t.calls.at(-1).name,'cheongla_read_notification');}
 for(const mode of ['student','invalid','failure']){const t=setup(mode);await t.ctx.navigateNotification(nid);assert.equal(t.routes[0][0],'notifications');assert(!t.calls.some(x=>x.name==='cheongla_read_notification'));assert(t.$('notificationStatus').textContent);}
 for(const mode of ['dirty','switched']){const t=setup(mode);await t.ctx.navigateNotification(nid);assert.equal(t.routes.length,0);assert(!t.calls.some(x=>x.name==='cheongla_read_notification'));}
 console.log('PASS journal alert exact-date routing, trash/tombstone dates, denied/missing context, dirty editor retention, account switch, read only after successful navigation');
})().catch(e=>{console.error(e);process.exit(1)});
