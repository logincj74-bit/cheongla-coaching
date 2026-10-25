const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');const h=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
class N{constructor(tag='div'){this.tag=tag;this.children=[];this.handlers={};this.value='';this.dataset={};this.disabled=false;this.hidden=false;}append(...ns){this.children.push(...ns)}replaceChildren(){this.children=[]}addEventListener(k,f){this.handlers[k]=f}querySelectorAll(tag){return this.children.flatMap(x=>[...(x.tag===tag?[x]:[]),...x.querySelectorAll(tag)])}scrollIntoView(){}setAttribute(){} }
const nodes={},$=id=>nodes[id]??=new N();let calls=[],apps=[],confirmed=true;const actor={id:'self',role:'student',full_name:'검증학생',approval_status:'approved',membership_state:'active'};
const c=vm.createContext({$,document:{createElement:t=>new N(t)},currentProfile:actor,applicationStudents:[],Date,Intl,Object,isAppAdmin:()=>false,readable:e=>e.message,appConfirm:async()=>confirmed,getClient:async()=>({rpc:async(n,a)=>{calls.push({n,a});const status=a.application_action==='cancel'?'canceled':'registered';apps=[...apps.filter(x=>x.exam_id!==a.target_exam),{exam_id:a.target_exam,student_id:a.target_student,status}];return{data:a.target_exam}}}),tuitionText:(p,t,tag='p')=>{const n=new N(tag);n.textContent=t;p.append(n);return n;}});
vm.runInContext(h.slice(h.indexOf('let examApplications=[]'),h.indexOf('function renderDeletedExams()')),c);
vm.runInContext(h.slice(h.indexOf('const examKinds='),h.indexOf('function syncExamFeeExams()')),c);
vm.runInContext(h.slice(h.indexOf('async function loadApplicationStudents()'),h.indexOf('\n',h.indexOf('async function loadApplicationStudents()'))),c);
vm.runInContext(h.slice(h.indexOf('async function mutateExams('),h.indexOf('async function loadExamRoster(')),c);
c.loadExams=async()=>{vm.runInContext('examReady=true;',c);c.renderExamCards(apps)};
const text=n=>[n.textContent||'',...n.children.map(text)].join(' '),buttons=()=> $('examList').querySelectorAll('button');
(async()=>{
 // A student always applies for their own verified profile, even without a parent-link lookup.
 let oldGet=c.getClient;c.getClient=async()=>{throw Error('student must not need applicant RPC')};await c.loadApplicationStudents();assert.equal(c.applicationStudents[0].id,'self');c.getClient=oldGet;
 const kinds=['daesung','survival','kice_june','kice_september'];vm.runInContext('examRows='+JSON.stringify(kinds.map((kind,i)=>({id:'exam'+i,exam_kind:kind,title:'검증 시험 '+i,status:'open',deadline:'2099-01-01T00:00:00Z',exam_on:'2099-01-02'})))+';examReady=true;',c);
 for(let i=0;i<4;i++){
  $('examApplicationKind').value=kinds[i];c.renderExamCards(apps);assert(text($('examList')).includes('검증 시험 '+i));assert.equal(buttons().length,1);assert.equal(buttons()[0].textContent,'모의고사 신청');
  confirmed=false;await buttons()[0].handlers.click();assert.equal(calls.length,i*3);confirmed=true;
  await buttons()[0].handlers.click();assert.equal(calls.at(-1).n,'cheongla_apply_student_exam');assert.equal(calls.at(-1).a.target_student,'self');assert(text($('examList')).includes('신청완료'));assert.equal(buttons()[0].textContent,'신청 취소');
  await buttons()[0].handlers.click();assert.equal(buttons()[0].textContent,'다시 신청');await buttons()[0].handlers.click();assert(text($('examList')).includes('신청완료'));
 }
 vm.runInContext('examRows=[];',c);$('examApplicationKind').value='all';c.renderExamCards([]);for(const label of ['대성 더 프리미엄','시대인재 서프','한국교육과정평가원 6월','한국교육과정평가원 9월'])assert(text($('examList')).includes(label));assert.equal(buttons().length,0);assert(text($('examList')).includes('게시된 시험이 없습니다'));
 c.currentProfile={...actor,role:'parent'};c.getClient=async()=>({rpc:async n=>{assert.equal(n,'cheongla_application_students');return{data:[{id:'linked',full_name:'연결학생'}]}}});await c.loadApplicationStudents();assert.equal(c.applicationStudents.length,0);assert(!c.canUseExams());
 console.log('PASS student self applicant without child-link RPC; 4 visible categories, confirmed register/cancel/re-register, status readback rendering, no fake application for unpublished exams, parent application access denied');
})().catch(e=>{console.error(e);process.exit(1)});
