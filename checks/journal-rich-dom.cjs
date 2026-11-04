process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JOURNAL_DOM_MODULE||'jsdom');
const dom=new JSDOM('<!doctype html><head></head><body><section id="staffJournalPanel"></section></body>',{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
let seq=0,journal=null,comments=[],calls=[],pending=new Map();
w.setInterval=()=>1;w.setTimeout=f=>{pending.set(++seq,f);return seq;};w.clearTimeout=id=>pending.delete(id);w.requestAnimationFrame=f=>f();
w.eval(fs.readFileSync('journal-ink.js','utf8'));w.eval(fs.readFileSync('staff-journal.js','utf8'));
const profile={id:'owner',full_name:'원장',role:'owner',approval_status:'approved',membership_state:'active'},day=w.CheonglaStaffJournal.today();
const ui=w.CheonglaStaffJournal.mount({document:d,profile:()=>profile,principal:()=>true,confirm:async()=>true,readable:e=>e.message,client:async()=>({rpc:async(name,a)=>{
 calls.push({name,a});
 if(name==='cheongla_staff_journal_list')return{data:{items:journal?[{...journal,comments}]:[],today_items:journal?[{...journal,comments}]:[],my_shift_closed:false}};
 if(name==='cheongla_save_staff_journal_v3'){journal={id:'j1',author_id:'owner',author_name:'원장',work_on:day,duty:a.duty_text,special:a.special_text,handover:a.handover_text,field_inks:a.field_inks,ink_color:a.ink_color,updated_at:'2026-11-04T08:00:'+String(++seq).padStart(2,'0')+'Z',comments};return{data:{...journal}};}
 if(name==='cheongla_save_journal_comment_v3'){const row={id:a.target_comment,journal_id:'j1',author_id:'owner',author_name:'원장',body:a.comment_body,ink_color:a.comment_ink,ink_runs:a.ink_runs,field_key:a.comment_field,created_at:'2026-11-04T08:00:00Z',updated_at:'2026-11-04T08:01:'+String(++seq).padStart(2,'0')+'Z'};comments=comments.filter(c=>c.id!==row.id).concat(row);return{data:row};}
 throw Error(name);
}})});
const button=text=>[...d.querySelectorAll('button')].find(n=>n.textContent===text),tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 await ui.open();let field=d.querySelector('[aria-label="근무 내용"]');assert.equal(field.closest('label'),null,'rich editor must not be nested in a label that activates the added-writing colour select');field.value='가나다라';field.dispatchEvent(new w.Event('input',{bubbles:true}));
 const leaf=field.firstChild.firstChild,r=d.createRange();r.setStart(leaf,1);r.setEnd(leaf,3);w.getSelection().removeAllRanges();w.getSelection().addRange(r);field.dispatchEvent(new w.MouseEvent('mouseup'));
 d.querySelector('[aria-label="선택한 글씨 파랑"]').click();await ui.leave();assert.equal(journal.duty,'가나다라');assert.deepEqual(JSON.parse(JSON.stringify(journal.field_inks.duty)),[{text:'가',ink:'red'},{text:'나다',ink:'blue'},{text:'라',ink:'red'}]);
 await ui.open();field=d.querySelector('[aria-label="근무 내용"]');assert.equal(field.value,'가나다라');assert.equal(field.querySelectorAll('span').length,3);
 let line=d.querySelector('[aria-label="근무 내용 같은 칸에 추가 작성"]');line.dispatchEvent(new w.Event('focus'));await tick();line=d.querySelector('.lr-active-writing .lr-writing-line');assert(line);line.value='추가 내용';line.dispatchEvent(new w.Event('input',{bubbles:true}));button('글 저장').click();await tick();await tick();assert.equal(comments[0].body,'추가 내용');
 button('글 수정').click();await tick();line=d.querySelector('.lr-active-writing .lr-writing-line');line.value='추가 내용 정정';line.dispatchEvent(new w.Event('input',{bubbles:true}));const own=d.querySelector('[aria-label="근무 내용"]'),ownRange=d.createRange();ownRange.setStart(own.firstChild.firstChild,0);ownRange.setEnd(own.firstChild.firstChild,1);w.getSelection().removeAllRanges();w.getSelection().addRange(ownRange);own.dispatchEvent(new w.MouseEvent('mouseup'));d.querySelector('.lr-editor > .lr-ink-palette [aria-label="선택한 글씨 녹색"]').click();assert.equal(own.inkEditor.runs()[0].ink,'green');assert.equal(line.value,'추가 내용 정정');button('수정 내용 저장').click();await tick();await tick();assert.equal(comments[0].body,'추가 내용 정정');assert(calls.some(c=>c.name==='cheongla_save_journal_comment_v3'&&c.a.comment_action==='edit'&&c.a.expected_updated_at));
 button('글 수정').click();await tick();line=d.querySelector('.lr-active-writing .lr-writing-line');line.value='자동 수정';line.dispatchEvent(new w.Event('input',{bubbles:true}));for(const f of [...pending.values()])f();await tick();await tick();assert.equal(comments[0].body,'자동 수정');assert(line.isConnected,'autosave replaced the active editor');await ui.leave();
 const K=w.CheonglaJournalInk,fixture=d.createElement('div');K.render(fixture,'<img onerror=x>',[{text:'<img onerror=x>',ink:'blue'}],'red');assert.equal(fixture.querySelector('img'),null);assert.equal(fixture.textContent,'<img onerror=x>');
 ui.reset();dom.window.close();console.log('PASS DOM: selected Korean text only recoloured; remaining text unchanged; rich save/reload; additional-writing create/edit and version; no HTML interpretation');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1);});
