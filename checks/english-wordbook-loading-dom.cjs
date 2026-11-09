process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const dom=new JSDOM('<section id="englishPanel"></section>',{runScripts:'outside-only'}),w=dom.window,d=w.document;
w.eval(fs.readFileSync('english-patrol.js','utf8'));
let branded=0;
w.CheonglaDocumentBrand={coverPdf:async(bytes,title)=>{assert.equal(title,'청라 수능 기출 단어장');branded++;return new w.Blob([bytes],{type:'application/pdf'});}};
let profile={id:'staff',approval_status:'approved',membership_state:'active'},request,fail=true,urls=0,revoked=[];
w.URL.createObjectURL=()=>`blob:book-${++urls}`;w.URL.revokeObjectURL=url=>revoked.push(url);
const ui=w.CheonglaEnglishPatrol.mount({document:d,profile:()=>profile,navigate(){},readable:e=>e.message,client:async()=>({rpc:async()=>request?await request:fail?{error:Error('연결 오류')}:{data:w.btoa('%PDF-test')}})});
const settle=async()=>{for(let i=0;i<5;i++)await new Promise(setImmediate)};
(async()=>{
 await ui.open('book');assert(d.body.textContent.includes('불러오지 못했습니다'));const retry=[...d.querySelectorAll('button')].find(b=>b.textContent==='단어장 다시 불러오기');assert(!retry.disabled);fail=false;retry.click();await settle();assert.equal(d.querySelectorAll('iframe').length,1);assert(d.querySelector('a[download]'));assert(d.querySelector('a[target="_blank"]').rel.includes('noopener'));
 retry.click();await settle();assert.equal(d.querySelectorAll('iframe').length,1);assert(revoked.includes('blob:book-1'));
 let resolve;request=new Promise(r=>resolve=r);const pending=ui.open('book');await settle();assert(d.body.textContent.includes('불러오는 중'));ui.reset();resolve({data:w.btoa('%PDF-stale')});await pending;assert.equal(d.querySelectorAll('iframe,a').length,0);assert.equal(urls,2);
 request=new Promise(r=>resolve=r);const switched=ui.open('book');await settle();profile={id:'other',approval_status:'approved',membership_state:'active'};resolve({data:w.btoa('%PDF-other')});await switched;assert.equal(d.querySelectorAll('iframe,a[download]').length,0);assert.equal(urls,2);assert.equal(branded,2);
 dom.window.close();console.log('PASS wordbook automatic loading, visible failure/retry, replacement URL cleanup, one preview, external-view link, reset/account-change stale response protection');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
