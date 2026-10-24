const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const source=html.slice(html.indexOf('async function deleteMealSubmission('),html.indexOf('async function restoreMealSubmission('));
async function run(scenario='success'){
 const s={student_id:'student',student_name:'검증학생',month:'2099-11-01',lunch:['2099-11-02'],dinner:[],updated_at:'s1'};
 const bill={id:'bill',student_id:'student',status:'published',updated_at:'b1'};
 const calls=[],messages=[],status={},nodes={mealStatus:{scrollIntoView(){}}};let confirmText='';
 const context=vm.createContext({mealBusy:false,currentProfile:{id:'owner'},mealData:{bills:[bill]},isPrincipal:()=>true,setMealControls(){},$:id=>nodes[id],appConfirm:async text=>{confirmText=text;return true},readable:e=>e.message,loadMealForm:async text=>messages.push(text),getClient:async()=>({rpc:async(name,args)=>{
  calls.push({name,args});
  if(name==='cheongla_fee_collection_states')return {data:[{notice_id:'bill',paid_at:scenario==='paid'?'paid':null,payment_updated_at:null,report:null}]};
  if(name==='cheongla_publish_meal_bill')return scenario==='withdraw_error'?{error:new Error('동시 변경')}:{};
  if(name==='cheongla_read_meal_form')return {data:{bills:[{...bill,status:'draft',updated_at:'b2'}],submissions:[{...s,updated_at:scenario==='stale'?'s2':'s1'}]}};
  if(name==='cheongla_trash_meal_submission')return scenario==='history'?{error:new Error('수납 이력 보호')}:{data:'trash-id'};
  throw Error('Unexpected RPC');
 }})});vm.runInContext(source,context);await context.deleteMealSubmission(s,status);
 assert(confirmText.includes('먼저 게시 취소'));
 return {calls,messages,status};
}
(async()=>{
 let r=await run();assert.deepEqual(r.calls.map(c=>c.name),['cheongla_fee_collection_states','cheongla_publish_meal_bill','cheongla_read_meal_form','cheongla_trash_meal_submission']);assert.equal(r.calls[1].args.notice_action,'withdraw');assert.equal(r.calls[1].args.expected_updated_at,'b1');assert.equal(r.calls[3].args.expected_bill_updated_at,'b2');assert.equal(r.calls[3].args.expected_submission_updated_at,'s1');assert(r.messages[0].includes('삭제했습니다'));
 r=await run('paid');assert.equal(r.calls.length,1);assert(r.status.textContent.includes('입금'));
 r=await run('withdraw_error');assert.equal(r.calls.length,2);assert.equal(r.status.textContent,'동시 변경');
 r=await run('stale');assert.equal(r.calls.length,3);assert(r.status.textContent.includes('신청서는 유지'));assert(r.messages[0].includes('게시 취소된 상태'));
 r=await run('history');assert(r.status.textContent.includes('수납 이력 보호'));assert(r.messages[0].includes('신청서는 유지'));
 console.log('PASS published meal deletion: payment precheck, withdrawal, fresh version, trash, conflict/error visible, partial-state reload');
})().catch(e=>{console.error(e);process.exit(1)});
