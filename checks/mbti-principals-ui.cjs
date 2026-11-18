const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8');
async function verify(mobile){
 const dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
 if(mobile)Object.defineProperty(w.navigator,'userAgent',{value:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X)'});
 w.matchMedia=()=>({matches:true});w.requestAnimationFrame=fn=>w.setTimeout(fn,0);w.cancelAnimationFrame=w.clearTimeout;
 w.HTMLElement.prototype.scrollIntoView=function(){};w.HTMLElement.prototype.scrollTo=function(o){this.scrollLeft=o.left;};
 w.eval(`var currentProfile=null,contentOwnerProfile='bound-owner',$=id=>document.getElementById(id),resets=0,opens=0;
 var canAdministerMembers=()=>false,canManageExams=()=>false,canManageLife=()=>false,canUseTuition=()=>false,canUseExamFees=()=>false,canUseBilling=()=>false,canManageTuition=()=>false,canManageContacts=()=>false,canCoachAll=()=>false,canUseInbox=()=>false;
 var financeEnabled=()=>false,canUseMealForms=()=>false,canUseExams=()=>false,canUseSchedule=()=>true,canUseBoard=()=>true;
 var resetMBTIStudy=()=>{resets++;document.getElementById('mbtiStudyPanel').hidden=true;};
 window.CheonglaMBTILibraryUI={open:()=>opens++};
 var recordSiteView=(view,key)=>history.replaceState({cheonglaView:{view,key,index:0}},'');
 var openSiteDestination=()=>{},showPublicPage=()=>{};
 var configureDeskMenu=()=>configureMBTIParentMenu();
 var updateHomeAccount=()=>{configureMBTIParentMenu();configureMBTIStudy();};
 var clearAccount=()=>{currentProfile=null;configureMBTIParentMenu();configureMBTIStudy();};`);
 function original(name){const start=html.indexOf('function '+name+'('),end=html.indexOf('\nfunction ',start+12);assert(start>=0&&end>start);return html.slice(start,end);}
 for(const name of ['isContentOwner','canUseMBTIStudy','canReadMBTIParentGuide','configureMBTIParentMenu','canEditMBTIStudy','canManageMBTIOperations','configureMBTIStudy','allowedAccountSection'])w.eval(original(name));
 w.eval(fs.readFileSync('detail-navigation.js','utf8'));w.eval(fs.readFileSync('swipe-navigation.js','utf8'));w.eval(fs.readFileSync('mobile-home.js','utf8'));
 const tick=()=>new Promise(r=>setTimeout(r,25));
 const cases=[null,{id:'bound-owner',role:'english_director',approval_status:'approved',membership_state:'active'},...['owner','english_director','math_director','manager','student','parent','korean_teacher'].map(role=>({id:role,role,approval_status:'approved',membership_state:'active'})),{id:'admin-manager',role:'manager',is_app_admin:true,approval_status:'approved',membership_state:'active'},{id:'pending',role:'owner',approval_status:'pending',membership_state:'active'},{id:'suspended',role:'owner',approval_status:'approved',membership_state:'suspended'}];
 for(const profile of cases){
  w.currentProfile=profile;w.updateHomeAccount();await tick();
  const principal=!!profile&&profile.id==='bound-owner'&&profile.approval_status==='approved'&&profile.membership_state==='active';
  assert.equal(w.canUseMBTIStudy(),principal);assert.equal(w.canEditMBTIStudy(),principal);assert.equal(w.canReadMBTIParentGuide(),principal);assert.equal(w.canManageMBTIOperations(),principal);assert.equal(w.allowedAccountSection('mbtiStudyPanel'),principal);
  assert.equal(d.getElementById('mbtiMainMenu').hidden,!principal);assert.equal(!!d.getElementById('mbtiParentsMenu'),principal);assert.equal(d.getElementById('mbtiStudyPanel').hidden,!principal);
  if(mobile){assert.equal(d.querySelector('[data-spotlight-menu="나의 MBTI학습법"]').hidden,!principal);assert.equal(w.CheonglaSwipe.groups().some(g=>g.label.includes('MBTI')),principal);assert.equal(!!d.querySelector('[data-home-route="mbti_study"]'),principal);const controls=d.querySelector('#homeSpotlightRail+.cheongla-swipe-controls');assert.equal(controls.querySelectorAll('[data-slide]').length,principal?9:8,'hidden MBTI card remained in pager');}
 }
 assert(w.resets>0&&w.opens>0);w.clearAccount();await tick();assert(d.getElementById('mbtiMainMenu').hidden);if(mobile)assert(d.querySelector('[data-spotlight-menu="나의 MBTI학습법"]').hidden);
 dom.window.close();
}
(async()=>{await verify(true);await verify(false);console.log('PASS principal-only MBTI on mobile and desktop: bound personal owner allowed; other principal accounts denied; manager/admin-flag-manager/student/parent/teacher/guest/pending/suspended have no main menu, parent submenu, spotlight card, swipe group, home shortcut, account panel or edit access; logout and downgrade reset preserved');})().catch(e=>{console.error(e);process.exit(1)});
