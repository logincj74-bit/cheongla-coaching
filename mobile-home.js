/* Mobile shortcuts use the existing permission checks and navigation handlers. */
(function(root){
'use strict';
if(!root.CheonglaSwipe?.enabled)return;
const doc=root.document,home=doc.getElementById('homePanel'),nav=doc.getElementById('siteNavigation');if(!home||!nav)return;
const el=(tag,text)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
const section=el('section');section.id='mobileRoleHome';section.className='mobile-role-home';section.setAttribute('aria-label','자주 쓰는 청라 기능');
const title=el('h2'),help=el('p'),journalSlot=el('div'),shortcuts=el('div');journalSlot.className='mobile-journal-slot';shortcuts.className='mobile-home-shortcuts';help.className='muted';section.append(title,help,journalSlot,shortcuts);
const allMenus=el('details');allMenus.id='mobileAllMenus';allMenus.className='mobile-all-menus';const summary=el('summary','전체 메뉴 열기');allMenus.append(summary);nav.before(section,allMenus);allMenus.append(nav);
allMenus.addEventListener('toggle',()=>{summary.textContent=allMenus.open?'전체 메뉴 접기':'전체 메뉴 열기';});
const plans={
 principal:{title:'원장 업무',help:'오늘 근무일지와 학습·운영 업무를 먼저 확인하세요.',items:[['오늘 근무일지','account_staffJournalPanel'],['학생·학부모 승인','account_approvalPanel'],['성적 변화 · 학습코칭','account_scoreCoachingPanel'],['문자 발송 안내문','account_officeSmsPanel'],['MBTI 학습법','mbti_study'],['학생·학부모 문의','question_board']]},
 manager:{title:'실장 업무',help:'근무일지 → 문자 안내 → 비용 안내 순으로 빠르게 처리하세요.',items:[['오늘 근무일지','account_staffJournalPanel'],['문자 발송 안내문','account_officeSmsPanel'],['학원비 안내','account_tuitionPanel'],['모의고사비 안내','account_examFeePanel'],['도시락비 안내','account_mealFeePanel'],['상담 · 신규 등록카드','account_registrationPanel']]},
 student:{title:'나의 오늘',help:'오늘의 계획을 기록하고 공지와 질문을 확인하세요.',items:[['일일 학습계획표','account_learningPanel'],['학생 공지','student'],['질문 · 상담','question_board'],['월간일정','schedule']]},
 parent:{title:'자녀 소식',help:'자녀의 학습 기록과 학원 안내를 확인하세요.',items:[['자녀 생활 · 학습기록','account_learningPanel'],['학부모 공지','parent'],['상담 문의','question_board'],['학원비 안내','account_tuitionPanel']]},
 teacher:{title:'청라 업무',help:'담당 업무와 상담을 확인하세요.',items:[['학생·학부모 문의','question_board'],['월간일정','schedule']]},
 guest:{title:'청라에 오신 것을 환영합니다',help:'학원 소개와 상담 안내를 먼저 확인해 보세요.',items:[['학원 소개','public:greeting'],['상담 문의','public:new_inquiry']]},
 pending:{title:'내 계정 확인',help:'학원 이용 승인 상태와 연락처를 확인해 주세요.',items:[['내 계정','my_membership'],['내 전화번호','my_contact']]}
};
function role(){const p=currentProfile;if(!p)return 'guest';if(p.approval_status!=='approved'||p.membership_state!=='active')return 'pending';if(['owner','english_director','math_director'].includes(p.role))return 'principal';return ['manager','student','parent'].includes(p.role)?p.role:'teacher';}
function permitted(key){if(key.startsWith('public:'))return true;const p=currentProfile;if(!p)return false;if(key==='my_membership'||key==='my_contact')return true;if(p.approval_status!=='approved'||p.membership_state!=='active')return false;if(key.startsWith('account_'))return allowedAccountSection(key.slice(8));if(key.startsWith('mbti_'))return canUseMBTIStudy();if(key==='schedule')return canUseSchedule();if(key==='question_board')return canUseBoard();return ['student','parent'].includes(key)&&key===p.role;}
let fingerprint='';
function sync(){
 const kind=role(),plan=plans[kind],p=currentProfile;section.hidden=home.hidden;const pager=doc.querySelector('.cheongla-menu-pager');if(pager)pager.hidden=!home.hidden;
 const journal=doc.getElementById('journalHomeCard'),staff=['principal','manager'].includes(kind);journalSlot.hidden=!staff;
 if(staff&&journal&&journal.parentElement!==journalSlot)journalSlot.append(journal);
 const signature=[p?.id,p?.role,p?.approval_status,p?.membership_state,p?.is_app_admin,kind,!!journal,...plan.items.map(([,key])=>permitted(key))].join(':');if(signature===fingerprint)return;fingerprint=signature;
 title.textContent=plan.title;help.textContent=plan.help;shortcuts.replaceChildren();
 for(const [label,key]of plan.items){if(!permitted(key)||key==='account_staffJournalPanel'&&journal&&staff)continue;const b=el('button',label);b.type='button';b.className='mobile-home-shortcut';b.dataset.homeRoute=key;b.addEventListener('click',()=>{if(!permitted(key))return;if(key.startsWith('public:'))showPublicPage(key.slice(7));else void openSiteDestination(key);});shortcuts.append(b);}
}
const update=updateHomeAccount;root.updateHomeAccount=function(...args){const r=update(...args);sync();return r;};
const menu=configureDeskMenu;root.configureDeskMenu=function(...args){const r=menu(...args);sync();return r;};
const record=recordSiteView;root.recordSiteView=function(...args){const before=root.history.state?.cheonglaView;const r=record(...args),after=root.history.state?.cheonglaView;if(before!==after)allMenus.open=false;sync();return r;};
const clear=clearAccount;root.clearAccount=function(...args){const r=clear(...args);fingerprint='';allMenus.open=false;sync();return r;};
new MutationObserver(sync).observe(home,{attributes:true,attributeFilter:['hidden']});
root.addEventListener('popstate',()=>{allMenus.open=false;sync();});root.CheonglaMobileHome={sync,role};sync();
})(globalThis);
