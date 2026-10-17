const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');const h=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
class N{constructor(){this.handlers={};this.value='';this.textContent='';this.dataset={};this.attrs={};}addEventListener(t,f){this.handlers[t]=f}setAttribute(k,v){this.attrs[k]=v}removeAttribute(k){delete this.attrs[k]}focus(){this.focused=true}scrollIntoView(){this.scrolled=true}}
const nodes={},$=id=>nodes[id]??=new N();let calls=[],manager=true,failure=false;
const c=vm.createContext({$,Date,Number,Error,editingExam:null,currentProfile:{id:'manager'},examBusy:false,examReady:true,canManageExams:()=>manager,resetExamForm:()=>{c.clearExamValidation();$('examTitle').value='대성 더 프리미엄 모의고사';$('examDate').value='';$('examDeadline').value='';},mutateExams:async(fn,success)=>{try{await fn({rpc:async(n,a)=>{calls.push({n,a});return failure?{error:Error('서버 저장 실패')}:{data:'test-exam'}}});$('examStatus').textContent=success;}catch(e){$('examStatus').textContent=e.message;}}});
vm.runInContext(h.slice(h.indexOf('function clearExamValidation()'),h.indexOf('\nlet examFeeRequest=')),c);
const event={preventDefault(){}};function input({title='대성 더 프리미엄 모의고사',date='2099-01-02',deadline='2099-01-01T22:00',status='open'}={}){$('examTitle').value=title;$('examDate').value=date;$('examDeadline').value=deadline;$('examBody').value='안내';$('examKind').value='daesung';$('examPublishState').value=status;}
(async()=>{
 assert(h.includes('<form id="examForm" novalidate>'));assert(h.includes('id="examFormStatus"'));assert(h.includes('id="examTitle" value="대성 더 프리미엄 모의고사"'));
 input({title:''});await $('examForm').handlers.submit(event);assert.equal(calls.length,0);assert($('examTitle').focused);assert($('examFormStatus').textContent.includes('시험명을'));
 input({date:''});await $('examForm').handlers.submit(event);assert.equal(calls.length,0);assert($('examDate').focused);assert($('examFormStatus').textContent.includes('시험일'));
 input({deadline:''});await $('examForm').handlers.submit(event);assert.equal(calls.length,0);assert($('examDeadline').focused);
 input({deadline:'2099-01-03T00:00'});await $('examForm').handlers.submit(event);assert.equal(calls.length,0);assert($('examFormStatus').textContent.includes('시험일이 끝나기 전'));
 input({date:'2000-01-02',deadline:'2000-01-01T22:00'});await $('examForm').handlers.submit(event);assert.equal(calls.length,0);assert($('examFormStatus').textContent.includes('현재보다 뒤'));
 input();await $('examForm').handlers.submit(event);assert.equal(calls.length,1);assert.equal(calls[0].n,'cheongla_save_exam_v2');assert.equal(calls[0].a.application_deadline,'2099-01-01T22:00:00+09:00');assert($('examFormStatus').textContent.includes('저장했습니다'));
 input({deadline:'2099-01-01T22:00:30'});await $('examForm').handlers.submit(event);assert.equal(calls[1].a.application_deadline,'2099-01-01T22:00:30+09:00');
 input();failure=true;await $('examForm').handlers.submit(event);assert.equal($('examTitle').value,'대성 더 프리미엄 모의고사');assert.equal($('examDate').value,'2099-01-02');assert.equal($('examFormStatus').dataset.state,'error');assert($('examFormStatus').textContent.includes('서버 저장 실패'));
 failure=false;c.examReady=false;await $('examForm').handlers.submit(event);assert($('examFormStatus').textContent.includes('새로고침'));c.examReady=true;manager=false;await $('examForm').handlers.submit(event);assert($('examFormStatus').textContent.includes('원장·실장'));
 console.log('PASS exam save: blank fields visibly identified/focused, native validation cannot swallow submit, Korean time with/without seconds, date/deadline checks, success feedback, server error preserves inputs, permission/readiness feedback');
})().catch(e=>{console.error(e);process.exit(1)});
