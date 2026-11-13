process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
let calls=[],journalOpens=0;const journal=d.createElement('section');journal.id='journalHomeCard';const today=d.createElement('button');today.textContent='오늘 일지 열기';today.onclick=()=>journalOpens++;journal.append(today);d.querySelector('.home-today').after(journal);
const pager=d.createElement('section');pager.className='cheongla-menu-pager';d.getElementById('siteNavigation').after(pager);
w.eval(`var currentProfile=null;window.CheonglaSwipe={enabled:true};var updateHomeAccount=()=>{},configureDeskMenu=()=>{};var clearAccount=()=>{currentProfile=null};var recordSiteView=(view,key)=>history.replaceState({cheonglaView:{view,key}},'');var canUseMBTIStudy=()=>['owner','english_director','math_director','manager'].includes(currentProfile?.role);var canUseSchedule=()=>true,canUseBoard=()=>true;var allowedAccountSection=id=>id==='approvalPanel'?currentProfile?.role==='owner':id==='staffJournalPanel'?['owner','english_director','math_director','manager'].includes(currentProfile?.role):id==='officeSmsPanel'?['owner','english_director','math_director','manager'].includes(currentProfile?.role):true;`);
w.openSiteDestination=async key=>calls.push(key);w.showPublicPage=key=>calls.push('public:'+key);
w.eval(fs.readFileSync('mobile-home.js','utf8'));
const panel=d.getElementById('mobileRoleHome'),all=d.getElementById('mobileAllMenus'),list=()=>[...panel.querySelectorAll('[data-home-route]')];
(async()=>{
 assert.equal(d.getElementById('siteNavigation').parentElement,all);assert(!all.open);assert(pager.hidden);assert.equal(w.CheonglaMobileHome.role(),'guest');assert(list().some(b=>b.textContent==='상담 문의'));
 for(const [role,title]of [['owner','원장 업무'],['english_director','원장 업무'],['math_director','원장 업무'],['manager','실장 업무'],['student','나의 오늘'],['parent','자녀 소식']]){
  w.currentProfile={id:role,role,approval_status:'approved',membership_state:'active'};w.updateHomeAccount();assert.equal(panel.querySelector('h2').textContent,title);assert(list().length<=6);assert(!panel.hidden);
  for(const b of list()){const n=calls.length;b.click();assert.equal(calls.length,n+1);assert.equal(calls.at(-1),b.dataset.homeRoute);}
  if(role==='manager'){assert(list().some(b=>b.dataset.homeRoute==='account_officeSmsPanel'));assert(list().some(b=>b.textContent==='도시락비 안내'));assert.equal(journal.parentElement,panel.querySelector('.mobile-journal-slot'));assert(!panel.querySelector('.mobile-journal-slot').hidden);today.click();assert(journalOpens>0);}
  if(['student','parent'].includes(role)){assert(panel.querySelector('.mobile-journal-slot').hidden);assert(!list().some(b=>/officeSmsPanel|staffJournalPanel|approvalPanel/.test(b.dataset.homeRoute)));}
 }
 w.currentProfile={id:'pending',role:'student',approval_status:'pending',membership_state:'active'};w.configureDeskMenu();assert.equal(w.CheonglaMobileHome.role(),'pending');assert.deepEqual(list().map(b=>b.dataset.homeRoute),['my_membership','my_contact']);
 all.open=true;w.recordSiteView('public','greeting');assert(!all.open);d.getElementById('homePanel').hidden=true;await new Promise(setImmediate);assert(panel.hidden);assert(!pager.hidden);d.getElementById('homePanel').hidden=false;await new Promise(setImmediate);assert(!panel.hidden);assert(pager.hidden);
 const menu=d.querySelector('#siteNavigation [data-public-page="photos"]');let originalClick=false;menu.onclick=()=>originalClick=true;all.open=true;menu.click();assert(originalClick,'existing menu listener lost');
 w.clearAccount();assert.equal(w.CheonglaMobileHome.role(),'guest');assert(!list().some(b=>b.dataset.homeRoute==='account_officeSmsPanel'));
 const desktop=new JSDOM(html,{runScripts:'outside-only'}),before=desktop.window.document.body.innerHTML;desktop.window.eval('window.CheonglaSwipe={enabled:false}');desktop.window.eval(fs.readFileSync('mobile-home.js','utf8'));assert.equal(desktop.window.document.body.innerHTML,before);desktop.window.close();dom.window.close();
 console.log('PASS mobile home: four role priorities, permission filtering, existing journal/listener preservation, full menu access, pending/logout clearing, page visibility and unchanged desktop DOM');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
