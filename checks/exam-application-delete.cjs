const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');const h=fs.readFileSync(require('path').join(__dirname,'../index.html'),'utf8');
class N{constructor(tag='div'){this.tag=tag;this.children=[];this.handlers={};this.value='';this.disabled=false;}append(...x){this.children.push(...x)}replaceChildren(){this.children=[]}addEventListener(k,f){this.handlers[k]=f}}
const nodes={},$=id=>nodes[id]??=new N();let confirm=false,fail=false,reloaded=0,calls=[],switchExam=false;
const row={student_id:'test-student',student_name:'검증학생',approval_status:'suspended',application_status:'registered',registered_at:'date',updated_at:'version'};
const c=vm.createContext({$,currentProfile:{id:'owner',role:'owner'},examBusy:false,examReady:true,examRows:[{id:'exam',title:'검증 시험'}],examRosterRows:[row],examApplications:[{exam_id:'exam',student_id:row.student_id}],isPrincipal:()=>c.currentProfile?.role==='owner',canManageLife:()=>['owner','manager'].includes(c.currentProfile?.role),canManageExams:()=>['owner','manager'].includes(c.currentProfile?.role),setExamControls:()=>{},readable:e=>e.message,appConfirm:async()=>{if(switchExam)$('examRosterSelect').value='other';return confirm},getClient:async()=>({rpc:async(n,a)=>{calls.push({n,a});return fail?{error:{message:'응시료 연결 보호'}}:{data:row.student_id}}}),loadExamRoster:async()=>{reloaded++;return true},document:{createElement:t=>new N(t)},tuitionText:(p,t,tag)=>{const n=new N(tag);n.textContent=t;p.append(n);return n},examDateText:x=>x,statuses:{suspended:'이용 중지'}});
vm.runInContext(h.slice(h.indexOf('async function deleteExamApplication('),h.indexOf("$('reloadExams').addEventListener")),c);
function findButtons(n){return n.children.flatMap(x=>[...(x.tag==='button'?[x]:[]),...findButtons(x)])}
(async()=>{
 $('examRosterSelect').value='exam';$('examRosterFilter').value='registered';c.renderExamRoster();assert.equal(findButtons($('examRosterBody'))[0].textContent,'신청 삭제');assert.equal($('examRosterActionsHead').hidden,false);
 c.currentProfile={role:'manager'};c.renderExamRoster();assert.equal(findButtons($('examRosterBody')).length,1);await c.deleteExamApplication(row);assert.equal(calls.length,0);
 c.currentProfile={id:'owner',role:'owner'};confirm=false;await c.deleteExamApplication(row);assert.equal(calls.length,0);
 confirm=true;switchExam=true;await c.deleteExamApplication(row);assert.equal(calls.length,0);switchExam=false;$('examRosterSelect').value='exam';
 await c.deleteExamApplication(row);assert.equal(calls.at(-1).n,'cheongla_delete_exam_application');assert.equal(calls.at(-1).a.expected_updated_at,'version');assert.equal(c.examApplications.length,0);assert.equal(reloaded,1);assert.equal(c.examBusy,false);
 fail=true;await c.deleteExamApplication(row);assert.equal($('examRosterStatus').textContent,'응시료 연결 보호');assert.equal(c.examBusy,false);
 console.log('PASS: director/manager row deletion, canceled confirmation, stale selected exam guard, version payload, verified response, roster reload, billing error and busy-state recovery');
})().catch(e=>{console.error(e);process.exit(1)});
