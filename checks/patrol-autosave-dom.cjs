process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JOURNAL_DOM_MODULE||'jsdom'),dom=new JSDOM('<head></head><body><section id="englishPanel"></section><section id="patrolPanel"></section></body>',{runScripts:'outside-only'}),w=dom.window,d=w.document;
let timers=new Map(),seq=0,row=null,calls=[],fail=false;w.setTimeout=f=>{timers.set(++seq,f);return seq;};w.clearTimeout=id=>timers.delete(id);
w.eval(fs.readFileSync('english-patrol.js','utf8'));
const p={id:'manager',full_name:'실장',role:'manager',approval_status:'approved',membership_state:'active'};
const ui=w.CheonglaEnglishPatrol.mount({document:d,profile:()=>p,principal:()=>false,readable:e=>e.message,confirm:async()=>true,client:async()=>({rpc:async(n,a)=>{
 if(n==='cheongla_patrol_day')return{data:row&&row.work_on===a.target_day?[row]:[]};
 if(n==='cheongla_save_patrol'){calls.push(a);if(fail)return{error:Error('연결 끊김')};row={id:'p1',author_id:p.id,author_name:p.full_name,work_on:a.work_date,checks:a.check_texts,special:a.special_text,updated_at:'2026-11-04T09:00:'+String(++seq).padStart(2,'0')+'Z'};return{data:row};}throw Error(n);
}})}),tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 await ui.openPatrol('2026-11-04');const inputs=d.querySelectorAll('textarea');inputs[0].value='08:15 학습 태도 확인';inputs[0].dispatchEvent(new w.Event('input'));assert(ui.dirty);for(const f of [...timers.values()])f();await tick();assert.equal(row.checks['08:15'],'08:15 학습 태도 확인');assert(!ui.dirty);
 fail=true;inputs[26].value='특이 사항';inputs[26].dispatchEvent(new w.Event('input'));inputs[26].dispatchEvent(new w.Event('blur'));await tick();assert(ui.dirty);assert(d.body.textContent.includes('저장되지 않았습니다'));
 fail=false;w.dispatchEvent(new w.Event('online'));await tick();assert.equal(row.special,'특이 사항');assert(!ui.dirty);
 inputs[1].value='수정된 기록';inputs[1].dispatchEvent(new w.Event('compositionend'));await ui.leave();assert.equal(row.checks['08:40'],'수정된 기록');assert(calls.at(-1).expected_updated_at);
 await ui.openPatrol('2026-11-04');assert.equal(d.querySelectorAll('textarea')[1].value,'수정된 기록');ui.reset();w.close();console.log('PASS patrol debounce, blur save, failed save retains dirty text, online retry, composition end, navigation flush, versioned reload');
})().catch(e=>{console.error(e);w.close();process.exit(1);});
