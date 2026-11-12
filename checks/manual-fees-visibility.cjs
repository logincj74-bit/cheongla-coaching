process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const dom=new JSDOM(fs.readFileSync('index.html','utf8'),{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
w.HTMLElement.prototype.scrollIntoView=function(){};
d.getElementById('accountPanel').hidden=false;
let calls=[],fail=false;
const client={rpc:async(name,args)=>{calls.push({name,args});return {data:name==='cheongla_tuition_students_v2'?[{student_name:'검증 학생',student_id:'s'}]:{}};},from:table=>{const query={select:()=>query,single:async()=>fail?{error:{message:'연결 오류'}}:{data:{meal_price:7500,updated_at:'v1'}},eq:()=>query,order:async()=>({data:[]})};return query;}};
w.getClient=async()=>client;
w.eval(`var currentProfile={id:'owner',role:'owner',approval_status:'approved',membership_state:'active'};
var canManageTuition=()=>['owner','manager'].includes(currentProfile?.role);
var allowedAccountSection=()=>currentProfile?.approval_status==='approved'&&currentProfile.membership_state==='active'&&['owner','manager','parent'].includes(currentProfile.role);
var tuitionMonthNow=()=> '2026-11',readable=e=>e.message,appConfirm=async()=>true;
var loadMealFeeNotices=async()=>{},loadExamFees=async()=>{},clearAccount=()=>{};`);
w.eval(fs.readFileSync('manual-fees.js','utf8'));
const label=text=>[...d.querySelectorAll('#manualFee_meal label')].find(n=>n.firstChild?.textContent===text)?.querySelector('input');
(async()=>{
 for(const role of ['owner','manager','parent']){
  w.currentProfile={id:role,role,approval_status:'approved',membership_state:'active'};
  const panel=d.getElementById('mealFeePanel');panel.hidden=true;
  await w.loadMealFeeNotices();
  assert.equal(panel.hidden,false,role+' parent panel remains hidden');
  const host=d.getElementById('manualFee_meal');assert(!host.hidden);assert.equal(host.closest('[hidden]'),null,role+' content has a hidden ancestor');
  assert(host.textContent.includes('도시락비 직접 안내'));
  assert.equal(!!host.querySelector('form'),role!=='parent');
  if(role!=='parent'){
   label('점심 개수').value='10';label('저녁 개수').value='2';label('점심 개수').dispatchEvent(new w.Event('input'));
   assert.equal(label('안내 금액 (원)').value,'90,000');
   label('식사 단가 (원)').value='8000';label('식사 단가 (원)').dispatchEvent(new w.Event('input'));
   assert.equal(label('안내 금액 (원)').value,'96,000');
  }
 }
 w.currentProfile={id:'owner',role:'owner',approval_status:'approved',membership_state:'active'};fail=true;d.getElementById('mealFeePanel').hidden=true;
 await w.loadMealFeeNotices();assert(!d.getElementById('mealFeePanel').hidden);assert(d.querySelector('#manualFee_meal [role=status]').textContent.includes('연결 오류'));
 w.currentProfile={id:'student',role:'student',approval_status:'approved',membership_state:'active'};d.getElementById('mealFeePanel').hidden=true;
 await w.loadMealFeeNotices();assert(d.getElementById('mealFeePanel').hidden);
 console.log('PASS initially hidden meal panel opens for owner/manager/parent; manager form and totals visible; parent read-only; errors visible; student denied');dom.window.close();
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
