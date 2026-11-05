const fs=require('fs'),assert=require('assert/strict'),{JSDOM}=require('jsdom');
const dom=new JSDOM('<section id="staffJournalPanel"></section>',{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
w.setInterval=()=>1;w.setTimeout=()=>1;w.clearTimeout=()=>{};w.HTMLElement.prototype.scrollIntoView=function(){};
for(const f of ['journal-ink.js','journal-handover.js','staff-journal.js'])w.eval(fs.readFileSync(f,'utf8'));
const today=w.CheonglaStaffJournal.today(),add=n=>{let t=new Date(today+'T12:00:00Z');t.setUTCDate(t.getUTCDate()+n);return t.toISOString().slice(0,10)},clone=x=>JSON.parse(JSON.stringify(x));
let profile={id:'staff',full_name:'평일 실장',role:'manager',approval_status:'approved',membership_state:'active'},journals=new Map(),handover=null,notes=[],failNote=false,calls=[];
const journal=day=>{if(!journals.has(day))journals.set(day,{work_on:day,fields:{duty:'',special:'',handover:''},field_inks:{duty:[],special:[],handover:[]},revision:1,closed_by:[]});return journals.get(day)};
const client={rpc:async(name,a)=>{calls.push({name,a});let data;
 switch(name){
 case 'cheongla_daily_journal_get':data=journal(a.work_date);break;
 case 'cheongla_daily_journal_list':data=[];break;
 case 'cheongla_journal_upcoming':data=[...journals.values()].filter(j=>j.work_on>a.work_date&&j.fields.duty).map(j=>({work_on:j.work_on,preview:j.fields.duty}));break;
 case 'cheongla_daily_journal_save':data=Object.assign(journal(a.work_date),{fields:clone(a.document_fields),field_inks:clone(a.document_inks),revision:journal(a.work_date).revision+1});break;
 case 'cheongla_journal_handover_create':handover={id:'handover-one',source_date:a.work_date,source_field:a.source_field,excerpt:Array.from(journal(a.work_date).fields[a.source_field]).slice(a.selection_start,a.selection_end).join(''),excerpt_inks:[{text:'긴급 전달',ink:'red'}],author_name:'평일 실장',created_at:new Date().toISOString(),revision:1,checks:[],completed_at:null,note_count:0};data=handover.id;break;
 case 'cheongla_journal_handovers':data={items:handover&&handover.source_date<=a.work_date&&!!handover.completed_at===a.include_completed?[handover]:[],total:0};data.total=data.items.length;break;
 case 'cheongla_journal_handover_thread':data={items:notes,total:notes.length};break;
 case 'cheongla_journal_handover_note':if(failNote)return{error:{message:'네트워크 확인 필요'}};if(!notes.some(n=>n.id===a.submission_id))notes.push({id:a.submission_id,body:a.note_body,inks:clone(a.note_inks),author_name:'평일 실장',created_at:new Date().toISOString()});handover.revision++;data=handover;break;
 case 'cheongla_journal_handover_action':if(a.handover_action==='check')handover.checks=[{staff_id:profile.id,name:profile.full_name,checked_at:new Date().toISOString()}];else{handover.completed_at=a.handover_action==='complete'?new Date().toISOString():null;handover.completed_name=profile.full_name;handover.revision++;}data=handover;break;
 default:throw Error(name);
 }return{data:clone(data)};}};
const ui=w.CheonglaStaffJournal.mount({document:d,profile:()=>profile,principal:()=>false,confirm:async()=>true,readable:e=>e.message,client:async()=>client});
const btn=t=>[...d.querySelectorAll('button')].find(n=>n.textContent===t),field=()=>d.querySelector('[data-field=duty]'),tick=()=>new Promise(r=>setImmediate(r));
async function settle(){for(let i=0;i<6;i++)await tick()}
async function date(day){const n=d.querySelector('input[type=date]');n.value=day;n.dispatchEvent(new w.Event('change'));await settle()}
function selection(n,start,end){const r=d.createRange();r.setStart(n,start);r.setEnd(n,end);w.getSelection().removeAllRanges();w.getSelection().addRange(r);}
async function openCard(){const c=d.querySelector('[data-handover]');assert(c);c.open=true;c.dispatchEvent(new w.Event('toggle'));await settle();return c}
function reply(text){btn('이 내용 아래에 답변 쓰기').click();const e=d.querySelector('[aria-label="인계 답변"]');e.inkEditor.insert(text);return e;}
(async()=>{
 await ui.open();assert.equal(field().contentEditable,'true');btn('내일 일지').click();await settle();assert.equal(d.querySelector('input[type=date]').value,add(1));assert(d.querySelector('.lr-future-date'));assert(btn('업무마감 · 최종 저장').disabled);assert.equal(field().contentEditable,'true');field().inkEditor.insert('도시락 32개 · 문자 발송 완료');assert(await ui.leave());assert.equal(journal(add(1)).fields.duty,'도시락 32개 · 문자 발송 완료');
 await date(today);assert(d.querySelector('.lr-upcoming').textContent.includes('도시락 32개'));field().inkEditor.insert('긴급 전달');selection(field().firstChild.firstChild,0,5);field().inkEditor.capture();btn('선택 내용 인계 유지').click();await settle();assert.equal(handover.excerpt,'긴급 전달');assert.equal(handover.source_date,today);assert(!ui.dirty);
 await date(add(2));assert(d.querySelector('[data-handover]'));assert.equal(field().contentEditable,'true');await openCard();btn('확인했어요').click();await settle();assert.equal(handover.completed_at,null);assert(btn('확인함').disabled);assert(d.querySelector('[data-handover]'));
 await openCard();let editor=reply('토요일 확인 · 수량 맞습니다.');const color=d.querySelector('[aria-label="인계 답변 글씨색"]');selection(editor.firstChild.firstChild,0,3);editor.inkEditor.capture();color.value='purple';color.dispatchEvent(new w.Event('change'));assert(ui.dirty);
 editor.dispatchEvent(new w.Event('compositionstart'));assert.equal(await ui.leave(),false);assert.equal(notes.length,0);editor.dispatchEvent(new w.Event('compositionend'));failNote=true;await date(add(3));assert.equal(d.querySelector('input[type=date]').value,add(2),'failed save must block date navigation');assert(ui.dirty);assert(editor.value.includes('수량 맞습니다.'));
 failNote=false;await date(add(3));assert.equal(notes.length,1);assert.equal(notes[0].inks[0].ink,'purple');assert(!ui.dirty);assert.equal(journal(today).fields.duty,'긴급 전달');await openCard();assert(d.querySelector('.lr-handover-note').textContent.includes('수량 맞습니다.'));assert(d.querySelector('.lr-handover-note [data-ink=purple]'));
 btn('업무 완료').click();await settle();assert(!d.querySelector('[data-handover]'));btn('완료한 인계 보기').click();await settle();assert(d.querySelector('[data-handover]'));btn('완료 취소').click();await settle();btn('미완료 인계 보기').click();await settle();assert(d.querySelector('[data-handover]'));
 await openCard();btn('원래 일지 열기').click();await settle();assert.equal(d.querySelector('input[type=date]').value,today);assert.equal(w.getSelection().toString(),'긴급 전달');
 ui.reset();assert.equal(d.querySelectorAll('[data-handover]').length,0);assert(!ui.dirty);profile={...profile,role:'student'};await ui.open();assert.equal(d.querySelectorAll('[role=textbox]').length,0);
 console.log('PASS future date shortcut/write, upcoming preview, selection pin, weekend carry, ack separate from complete, coloured inline reply, IME block, failed save retention, leave autosave, source link, completion/history/reopen, logout reset, student denied');dom.window.close();
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
