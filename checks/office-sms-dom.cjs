process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
w.HTMLElement.prototype.scrollIntoView=function(){};w.HTMLFormElement.prototype.reportValidity=function(){return [...this.elements].every(x=>!x.required||!!x.value);};d.getElementById('accountPanel').hidden=false;
let templates=JSON.parse(fs.readFileSync('scripts/office-sms-seeds.json','utf8')).map((x,i)=>({...x,id:String(i+1),revision:1,deleted_at:null})),roster=[{student_id:'s',student_name:'홍길동',monthly_fee:620000,enrolled_on:'2026-12-28',recipients:[{id:'s',name:'홍길동',role:'student',phone:'01000000001'},{id:'p',name:'보호자',role:'parent',phone:'01000000002'}]}],calls=[],seq=100;
const client={rpc:async(name)=>{calls.push(name);return {data:name==='cheongla_office_sms_students'?structuredClone(roster):{bank_name:'검증은행',account_number:'123-456',account_holder:'검증예금주'}};},from:()=>{
 let action='read',payload,filters=[];const q={select:()=>q,order:()=>q,eq:(k,v)=>(filters.push(x=>x[k]===v),q),is:(k,v)=>(filters.push(x=>x[k]===v),q),not:(k,_op,v)=>(filters.push(x=>x[k]!==v),q),insert:p=>(action='insert',payload=p,q),update:p=>(action='update',payload=p,q),delete:()=>(action='delete',q),then(resolve,reject){try{let matched=templates.filter(x=>filters.every(f=>f(x)));if(action==='insert'){matched=[{...payload,id:String(seq++),revision:1,deleted_at:null}];templates.push(...matched);}if(action==='update')for(const x of matched)Object.assign(x,payload,{revision:x.revision+1});if(action==='delete')templates=templates.filter(x=>!matched.includes(x));resolve({data:structuredClone(matched)});}catch(e){reject(e);}}};return q;
}};
w.getClient=async()=>client;
w.eval(`var currentProfile={id:'owner',role:'owner',approval_status:'approved',membership_state:'active'},accountSectionLabels={};
var allowedAccountSection=()=>true,configureDeskMenu=()=>{},configureAccountSections=()=>{},clearAccount=()=>{};
var openSiteDestination=async()=>{},appConfirm=async()=>true,readable=e=>e.message;
var normalizeContactPhone=v=>/^01[016789][0-9]{7,8}$/.test(String(v||'').replace(/[^0-9]/g,''))?String(v).replace(/[^0-9]/g,''):'';
var copyFeeMessage=async()=>{},examFeeSMSURL=(p,t)=>'sms:'+p+'?body='+encodeURIComponent(t);`);
w.eval(fs.readFileSync('office-sms.js','utf8'));
const tick=()=>new Promise(setImmediate),input=(label)=>d.querySelector('#officeSmsPanel [aria-label="'+label+'"]'),btn=(text,scope=d)=>[...scope.querySelectorAll('button')].find(x=>x.textContent===text);
async function pick(title){const chooser=input('안내문 선택');chooser.value=templates.find(x=>x.title===title).id;chooser.dispatchEvent(new w.Event('change'));await tick();}
(async()=>{
 for(const role of ['owner','english_director','math_director','manager','student','parent']){w.currentProfile={id:role,role,approval_status:'approved',membership_state:'active'};w.configureDeskMenu();assert.equal(!!d.getElementById('officeSmsMenu'),!['student','parent'].includes(role));assert.equal(w.allowedAccountSection('officeSmsPanel'),!['student','parent'].includes(role));}
 w.currentProfile={id:'manager',role:'manager',approval_status:'approved',membership_state:'active'};await w.openSiteDestination('account_officeSmsPanel');assert(!d.getElementById('officeSmsPanel').hidden);assert(!input('안내문 선택').disabled);
 await pick('등원 전 교육비 · 윈터');input('학생 선택').value='s';input('학생 선택').dispatchEvent(new w.Event('change'));
 assert.equal(input('학생이름').value,'홍길동');assert.equal(input('교육비').value,'620000');assert.equal(input('은행명').value,'검증은행');
 for(const label of ['청구시작일','청구종료일','납부기한'])input(label).value=label==='청구시작일'?'2026-12-28':'2027-01-26';input('청구금액').value='620000';
 btn('선택값으로 문구 만들기').click();await tick();assert(input('최종 문자 내용 · 직접 수정 가능').value.includes('620,000원'));assert(!input('최종 문자 내용 · 직접 수정 가능').value.includes('{{'));
 const sends=[...d.querySelectorAll('.office-sms-recipients button')].map(n=>n.textContent);assert(sends.some(x=>x.includes('보호자')));assert(!sends.some(x=>x.includes('홍길동')));
 input('청구금액').value='630000';input('청구금액').dispatchEvent(new w.Event('input'));assert(!d.querySelector('.office-sms-recipients button'));
 btn('선택값으로 문구 만들기').click();await tick();const preview=input('최종 문자 내용 · 직접 수정 가능');preview.value+='\n이번 발송만 추가';preview.dispatchEvent(new w.Event('input'));assert(!templates.find(x=>x.title==='등원 전 교육비 · 윈터').body.includes('이번 발송만 추가'));
 roster[0].recipients[1].phone='01000000003';btn('보호자 학부모 · 01000000002 문자 앱 열기').click();await tick();await tick();assert(d.querySelector('#officeSmsPanel [role=status]').textContent.includes('번호가 변경'));
 await pick('첫 등원 안내 · 학생·학부모');input('학생 선택').value='s';input('학생 선택').dispatchEvent(new w.Event('change'));btn('선택값으로 문구 만들기').click();await tick();assert(input('최종 문자 내용 · 직접 수정 가능').value.includes('2026년 12월 28일'));
 assert([...d.querySelectorAll('.office-sms-recipients button')].some(x=>x.textContent.includes('홍길동 학생')));
 const sms=w.CheonglaOfficeSMS;assert(sms.dateRangeError({운영시작일:'2026-12-30',운영종료일:'2026-12-20'}));
 btn('새 안내문 만들기').click();await tick();input('안내문 제목').value='새로운 상담';input('안내문 원본 · {{학생이름}}처럼 입력').value='안녕하세요 {{학생이름}}';
 input('안내문 제목').dispatchEvent(new w.Event('input',{bubbles:true}));const form=input('안내문 제목').form;form.dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));await tick();await tick();assert(templates.some(x=>x.title==='새로운 상담'));
 assert.equal(html.match(/<datalist id="cheonglaExamNames">([\s\S]*?)<\/datalist>/)[1].match(/<option/g).length,4);
 w.currentProfile=null;w.clearAccount();assert(d.getElementById('officeSmsPanel').hidden);assert(!d.getElementById('officeSmsPanel').textContent.includes('홍길동'));
 console.log('PASS office SMS UI: role menu/access, visible composer, student/bank autofill, date/fee interpolation, parent-only tuition, both attendance recipients, stale-field blocking, manual draft isolation, fresh recipient checks, saved templates, logout cleanup, four exam defaults');dom.window.close();
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
