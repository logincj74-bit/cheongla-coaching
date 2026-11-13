process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
let lastScroll='',lastFocus='',deferred=null,listError=false;w.HTMLElement.prototype.scrollIntoView=function(){lastScroll=this.id;};w.HTMLElement.prototype.focus=function(){lastFocus=this.id;};
w.eval(`var $=id=>document.getElementById(id),currentProfile={id:'owner',role:'owner',approval_status:'approved',membership_state:'active'},activeAccountSection=null,siteDestination=null,informationBusy=false,pendingLearningContext=null;
var accountSectionLabels=${html.match(/const accountSectionLabels=(\{[^\n]+\});/)[1]};
var financeEnabled=()=>false,feeNoticesEnabled=()=>true,isPrincipal=()=>currentProfile.role==='owner',isAppAdmin=()=>false,canManageLife=isPrincipal,canManageMealForms=isPrincipal,canManageAccountRecovery=isPrincipal,canManageExams=isPrincipal,canManageContacts=isPrincipal,canAdministerMembers=isPrincipal,canCoachAll=isPrincipal;
var canUseTuition=isPrincipal,canUseExamFees=isPrincipal,canUseBilling=()=>false,canUseMealForms=()=>false,canUseExams=()=>false,canUseSchedule=()=>true,canUseBoard=()=>true,canUseInbox=()=>true,canUseMBTIStudy=()=>true;
var clearAccount=()=>{},showSiteHome=()=>{},appConfirm=async()=>true,readable=e=>e.message,renderMealCancelContacts=()=>{},configureStaffWorkspace=()=>{},feeDepositInstructions=()=>'',allowedAccountSection=()=>true,accountSectionGroup=()=> '내 계정',useAccountSections=()=>true,updateHomeAccount=()=>{};
var tuitionText=(parent,text,tag='p')=>{const n=document.createElement(tag);n.textContent=text;parent.append(n);return n;};
var recordSiteView=(view,key)=>history.replaceState({cheonglaView:{view,key,index:1}},'');
window.CheonglaStaffJournalUI={reset(){}};window.CheonglaJournalMute={mount:()=>({reset(){},refresh(){}})};window.CheonglaSwipe={enabled:true};
`);
let people=[{id:'student-a',name:'학생 가'},{id:'student-b',name:'학생 나'}];
w.getClient=async()=>({rpc:async name=>name==='cheongla_score_coaching_list'?(listError?{error:Error('목록 연결 오류')}:(deferred?await deferred:{data:{students:people,items:[]}})):{data:[]}});
function original(name){const start=html.indexOf('function '+name+'('),end=html.indexOf('\nfunction',start+12);return html.slice(start,end);}
w.eval(original('configureAccountSections'));w.eval(original('applyAccountSection'));w.eval(original('openSiteAccount'));
const routeStart=html.indexOf('async function openSiteDestination('),routeEnd=html.indexOf('\nfunction',routeStart+20);w.eval(html.slice(routeStart,routeEnd));
w.eval(html.match(/^function closeSiteMenus\(\).*$/m)[0]);
w.eval(html.slice(html.indexOf('function configureDeskMenu(){'),html.indexOf('async function loadApplicationStudents')));
for(const [id,items]of [['feeNoticeMenu','feeNoticeMenuItems'],['askMenu','askMenuItems']]){const menu=d.createElement('details');menu.id=id;menu.innerHTML='<summary>'+id+'</summary><div id="'+items+'"></div>';d.getElementById('siteNavigation').append(menu);}
w.eval(fs.readFileSync('feature-flags.js','utf8'));w.eval(fs.readFileSync('score-coaching.js','utf8'));w.eval(fs.readFileSync('role-coaching.js','utf8'));w.eval(fs.readFileSync('mobile-home.js','utf8'));
const tick=()=>new Promise(r=>setTimeout(r,30));
(async()=>{
 const shortcut=d.querySelector('[data-home-route="account_scoreCoachingPanel"]');assert(shortcut,'owner home shortcut missing');assert(d.getElementById('scoreCoachingPanel').hidden);shortcut.click();await tick();
 const panel=d.getElementById('scoreCoachingPanel');assert(!d.getElementById('accountPanel').hidden);assert(d.getElementById('homePanel').hidden);assert(!panel.hidden);assert(!panel.classList.contains('account-section-inactive'));assert.equal(lastScroll,panel.id);assert.equal(lastFocus,panel.id);
 const select=panel.querySelector('#scoreCoachingStudentSelect');assert(select);assert.equal(panel.querySelector('label[for="scoreCoachingStudentSelect"]').textContent,'학생 선택');assert.equal(select.options.length,2);assert.equal(select.value,'student-a');select.value='student-b';select.dispatchEvent(new w.Event('change'));await tick();assert.equal(panel.querySelector('select').value,'student-b');assert(panel.querySelector('input[type="file"]')&&!panel.querySelector('input[type="file"]').disabled);assert([...panel.querySelectorAll('button')].some(b=>b.textContent==='사진 다시 읽기'));
 // Navigation via the account drawer opens the same visible screen after a reset.
 w.CheonglaScoreCoachingUI.reset();d.querySelector('#accountSectionButtons [data-section="scoreCoachingPanel"]').click();await tick();assert(!panel.hidden&&!panel.classList.contains('account-section-inactive'));assert(panel.querySelector('#scoreCoachingStudentSelect'));
 // A delayed score list must not pull focus back after the user leaves the screen.
 let resolve;deferred=new Promise(r=>resolve=r);const loading=w.openSiteDestination('account_scoreCoachingPanel');await tick();assert(!panel.hidden&&panel.textContent.includes('학생 목록과 성적·코칭 확인 중'));await w.openSiteDestination('account_membershipPanel');const focusBefore=lastFocus;resolve({data:{students:people,items:[]}});await loading;assert.equal(w.activeAccountSection,'membershipPanel');assert(panel.classList.contains('account-section-inactive'));assert.equal(lastFocus,focusBefore);
 deferred=null;people=[];await w.openSiteDestination('account_scoreCoachingPanel');assert(!panel.hidden);assert(panel.querySelector('#scoreCoachingStudentSelect').disabled);assert(panel.textContent.includes('승인 재원생이 없습니다'));listError=true;await w.openSiteDestination('account_scoreCoachingPanel');assert(!panel.hidden);assert(panel.textContent.includes('목록 연결 오류'));assert([...panel.querySelectorAll('button')].some(b=>b.textContent==='다시 불러오기'));
 dom.window.close();console.log('PASS real owner home/account route -> visible score panel -> labeled student selection -> enabled photo reader; late response cannot steal focus');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
