(function(root){
'use strict';
// Device identity, rather than window width: a resized desktop retains the original UI.
const navInfo=root.navigator;
const mobile=navInfo.userAgentData?.mobile===true||/Android|iPhone|iPad|iPod/i.test(navInfo.userAgent)||(/Mac/i.test(navInfo.platform||'')&&navInfo.maxTouchPoints>1);
if(!mobile){root.CheonglaSwipe={enabled:false};return;}
root.document.documentElement.setAttribute('data-cheongla-swipe','mobile');
const doc=root.document,nav=doc.getElementById('siteNavigation'),home=doc.getElementById('homePanel');if(!nav||!home)return;
const el=(t,text)=>{const n=doc.createElement(t);if(text!==undefined)n.textContent=text;return n;};
const btn=(label,fn)=>{const n=el('button',label);n.type='button';n.className='secondary';n.addEventListener('click',fn);return n;};
const visible=n=>!!n&&!n.closest('[hidden],.account-section-inactive')&&!n.closest('details:not([open])');
const reduced=()=>root.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
let dirtyForms=new WeakSet(),gesture=null,direction=0,frame=0,navigating=false,restoring=false,restoreToken=0;
const positions=new Map();
let pendingOrigin=null;
let activeEntry=root.history.state?.cheonglaView||{view:'home',key:'',index:0},furthest=activeEntry.index||0;
root.history.scrollRestoration='manual';
const entryKey=s=>[s.index||0,s.view,s.key||''].join(':');
function snapshot(){return {left:root.scrollX||0,top:root.scrollY||0,
 railLeft:doc.getElementById('homeSpotlightRail')?.scrollLeft||0,
 homeDetails:[...home.querySelectorAll('details')].map(n=>n.open),
 menuDetails:[...doc.querySelectorAll('#mobileAllMenus,#siteNavigation details')].map(n=>n.open)};}
function remember(){if(!restoring)positions.set(entryKey(activeEntry),pendingOrigin?.key===entryKey(activeEntry)?pendingOrigin.position:snapshot());}
function restoreHome(position){
 if(state().view!=='home')return;
 home.querySelectorAll('details').forEach((n,i)=>{n.open=!!position.homeDetails?.[i];});
 doc.querySelectorAll('#mobileAllMenus,#siteNavigation details').forEach((n,i)=>{n.open=!!position.menuDetails?.[i];});
 const rail=doc.getElementById('homeSpotlightRail');if(rail){rail.scrollLeft=position.railLeft||0;rails.get(rail)?.update();}
}
function restorePosition(){const token=++restoreToken;activeEntry=state();const position=positions.get(entryKey(activeEntry));restoring=false;navigating=false;resetDrag();
 if(position)root.requestAnimationFrame(()=>root.requestAnimationFrame(()=>{if(token===restoreToken){restoreHome(position);root.scrollTo({left:position.left,top:position.top,behavior:'instant'});}}));schedule();
}
function activePanel(){if(!doc.getElementById('accountPanel').hidden){const p=[...doc.querySelectorAll('#accountPanel>section')].find(visible);if(p)return p;}return ['publicContentPanel','informationPanel','newInquiryPanel','homeDictionary','homePanel'].map(id=>doc.getElementById(id)).find(visible);}
function dirtyVisible(){return [...doc.querySelectorAll('form')].some(f=>visible(f)&&dirtyForms.has(f));}
function editable(n){return n?.closest?.('input,textarea,select,[contenteditable="true"]');}
function blocked(start){return doc.querySelector('dialog[open]')||navigating||restoring||start?.closest?.('input,textarea,select,video,audio,canvas,[contenteditable="true"],#siteBackControls,#siteNavigation,.rules-image-expanded');}
function state(){return root.history.state?.cheonglaView||{view:'home',key:''};}
function allowedButton(button){
 if(button.disabled||button.hidden)return false;const key=button.dataset.publicPage||button.dataset.memberPage||button.dataset.swipeRoute||'';
 if(button.dataset.publicPage){if(key.startsWith('director_'))return currentProfile?.approval_status==='approved'&&currentProfile.membership_state==='active';return true;}
 if(['admissions_news','resources'].includes(key))return true;
 if(currentProfile?.approval_status!=='approved'||currentProfile.membership_state!=='active')return false;
 if(key.startsWith('account_'))return allowedAccountSection(key.slice(8));
 if(key.startsWith('mbti_'))return canUseMBTIStudy();
 if(key==='my_contact'||key==='question_board'||key==='schedule'||['all','student','parent'].includes(key))return true;
 if(key.startsWith('desk_'))return ['owner','english_director','math_director','manager'].includes(currentProfile.role);
 if(key==='meal_forms')return canUseMealForms();if(key==='exam_apply')return canUseExams();
 return false;
}
function groups(){return [...nav.children].filter(n=>!n.hidden).map(n=>{const all=n.matches('button')?[n]:[...n.querySelectorAll('button[data-public-page],button[data-member-page],button[data-swipe-route],#officeSmsMenu')];
 const buttons=all.filter(allowedButton);return {label:n.querySelector(':scope>summary .menu-summary-label')?.textContent.trim()||n.querySelector(':scope>summary')?.textContent.trim()||n.textContent.trim(),buttons,keys:all.map(b=>b.dataset.publicPage||b.dataset.memberPage||b.dataset.swipeRoute)};}).filter(g=>g.buttons.length);}
const pager=el('section');pager.className='cheongla-menu-pager';pager.setAttribute('aria-label','이전·다음 화면 이동');
const previous=btn('← 이전 화면',()=>navigate(-1)),next=btn('다음 화면 →',()=>navigate(1)),label=el('p'),help=el('p');label.setAttribute('role','status');label.setAttribute('aria-live','polite');help.className='swipe-help';pager.append(previous,next,label,help);nav.after(pager);
function sync(){frame=0;const s=state(),index=s.index||0;previous.disabled=index<=0||navigating;next.disabled=index>=furthest||navigating;
 label.textContent='화면 이동';help.textContent='오른쪽으로 쓸면 이전 화면 · 왼쪽으로 쓸면 다음 화면';
 if(direction&&!navigating&&!restoring){const panel=activePanel();if(panel&&!reduced()){panel.classList.remove('cheongla-slide-left','cheongla-slide-right');void panel.offsetWidth;panel.classList.add(direction>0?'cheongla-slide-left':'cheongla-slide-right');root.setTimeout(()=>panel.classList.remove('cheongla-slide-left','cheongla-slide-right'),220);}direction=0;}
}
function schedule(){if(!frame)frame=root.requestAnimationFrame(sync);}
async function canLeave(){
 const owned=[['officeSmsPanel',root.CheonglaOfficeSMS],['staffJournalPanel',root.CheonglaStaffJournalUI],['scoreCoachingPanel',root.CheonglaScoreCoachingUI],['learningPanel',root.CheonglaLearningUI],['registrationPanel',root.CheonglaLearningUI],['externalPanel',root.CheonglaLearningUI]].find(([id])=>visible(doc.getElementById(id)));
 if(owned?.[1]?.leave)return await owned[1].leave();
 if(!dirtyVisible())return true;
 const confirm=root.appConfirm||root.confirm;return !!(await confirm('저장하지 않은 내용을 버리고 이전·다음 화면으로 이동할까요?'));
}
async function navigate(step){
 const index=state().index||0;if(navigating||restoring||doc.querySelector('dialog[open]')||(step<0?index<=0:index>=furthest))return false;
 navigating=true;schedule();
 try{if(!await canLeave()){navigating=false;resetDrag(true);schedule();return false;}}
 catch(error){navigating=false;resetDrag(true);schedule();return false;}
 editable(doc.activeElement)&&doc.activeElement.blur();remember();direction=step;root.history.go(step<0?-1:1);return true;
}
const rails=new Map();
function attachRail(rail,name){
 if(rails.has(rail))return;const controls=el('div');controls.className='cheongla-swipe-controls';controls.setAttribute('aria-label',name+' 넘기기');controls.setAttribute('role','group');rail.after(controls);
 let cards=[],index=0,timer;const status=el('p');status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 function update(){if(!cards.length)return;const origin=rail.getBoundingClientRect().left;index=cards.reduce((best,card,i)=>Math.abs(card.getBoundingClientRect().left-origin)<Math.abs(cards[best].getBoundingClientRect().left-origin)?i:best,0);status.textContent=(index+1)+' / '+cards.length;controls.querySelectorAll('[data-slide]').forEach((b,i)=>b.setAttribute('aria-current',String(i===index)));controls.firstChild.disabled=index===0;controls.lastChild.disabled=index===cards.length-1;}
 function go(i){i=Math.max(0,Math.min(cards.length-1,i));if(!cards[i])return;const left=cards[i].offsetLeft-cards[0].offsetLeft;if(rail.scrollTo)rail.scrollTo({left,behavior:reduced()?'instant':'smooth'});else rail.scrollLeft=left;index=i;status.textContent=(i+1)+' / '+cards.length;controls.firstChild.disabled=i===0;controls.lastChild.disabled=i===cards.length-1;controls.querySelectorAll('[data-slide]').forEach((b,j)=>b.setAttribute('aria-current',String(j===i)));}
 function rebuild(){cards=[...rail.children].filter(n=>!n.hidden);rail.classList.toggle('swipe-rail',cards.length>1);controls.hidden=cards.length<=1;controls.replaceChildren();if(cards.length<=1)return;
 rail.setAttribute('aria-label',name+' · 좌우로 넘기기');controls.append(btn('← 이전',()=>go(index-1)),status);cards.forEach((card,i)=>{const dot=btn('●',()=>go(i));dot.className='swipe-dot';dot.dataset.slide=String(i);dot.setAttribute('aria-label',name+' '+(i+1)+'번째 보기');controls.append(dot);card.querySelectorAll('img').forEach(img=>img.draggable=false);});controls.append(btn('다음 →',()=>go(index+1)));controls.firstChild.setAttribute('aria-label',name+' 이전');controls.lastChild.setAttribute('aria-label',name+' 다음');update();}
 const observer=new MutationObserver(rebuild);observer.observe(rail,{childList:true});rail.addEventListener('scroll',()=>{root.clearTimeout(timer);timer=root.setTimeout(update,70);},{passive:true});root.addEventListener('resize',update,{passive:true});rails.set(rail,{observer,controls,update});rebuild();
}
function scan(){for(const [node,x]of rails)if(!node.isConnected){x.observer.disconnect();root.removeEventListener('resize',x.update);x.controls.remove();rails.delete(node);}for(const id of ['homeSpotlightRail','homeTourSection','homeDailyCountdown']){const n=doc.getElementById(id);if(n)attachRail(n,id==='homeDailyCountdown'?'주요 일정':id==='homeTourSection'?'학원 동영상':'청라 주요 안내');}for(const gallery of doc.querySelectorAll('#publicContentBody .public-gallery'))if(gallery.children.length>1)attachRail(gallery,'청라 사진');schedule();}
const spotlight=el('section');spotlight.className='cheongla-swipe-home';spotlight.append(el('h2','청라 한눈에 보기'),el('p','← 카드를 좌우로 밀어보세요 →'));const homeRail=el('div');homeRail.id='homeSpotlightRail';homeRail.className='cheongla-swipe-rail';spotlight.append(homeRail);
// Reuse the real menu controls so permission checks and destination history stay intact.
const highlights=[
 ['청라소개','청라의 소개, 모습, 생활 규칙을 확인하세요.','[data-public-page="greeting"]'],
 ['청라소식','공지와 월간일정, 입시 뉴스와 자료를 확인하세요.','[data-member-page="admissions_news"]'],
 ['청라 Q&A','학생·학부모 상담과 신규 상담 문의를 남겨 주세요.','[data-public-page="new_inquiry"]'],
 ['청라생활','생활·학습 기록과 청라의 운영 업무를 확인하세요.','#deskMenu'],
 ['청라비용안내','학원비, 모의고사비, 도시락비 안내를 확인하세요.','#feeNoticeMenu'],
 ['청라에게 묻기','계정 복구, 연락처와 문의 답변을 확인하세요.','#askMenu'],
 ['청재의 서재','원장님의 글과 사진, 칼럼을 만나보세요.','#directorLibrary'],
 ['나의 MBTI학습법','나의 학습성향과 유형별 공부 방법을 살펴보세요.','[data-member-page="mbti_intro"]'],
 ['청라찾아오시는 길','청라의 위치와 방문 방법을 확인하세요.','[data-public-page="visit"]']
].map(([title,body,selector])=>{
 const card=el('article');card.className='cheongla-swipe-card';card.dataset.spotlightMenu=title;
 const content=el('div');content.className='spotlight-menu-content';card.append(el('small','CHEONGLA'),el('h3',title),el('p',body),content);homeRail.append(card);return {selector,content};
});
function menuCopy(source){
 if(source.hidden)return null;
 if(source.matches('button')){const copy=btn(source.textContent.trim(),()=>{if(source.isConnected&&!source.hidden&&!source.disabled)source.click();});copy.disabled=source.disabled;return copy;}
 if(source.matches('a')){const copy=source.cloneNode(true);copy.removeAttribute('id');return copy;}
 if(!source.matches('details,div'))return null;
 const copy=el(source.localName);if(source.matches('details'))copy.append(el('summary',source.querySelector(':scope>summary')?.textContent.trim()||'메뉴 보기'));
 for(const child of source.children){const item=menuCopy(child);if(item)copy.append(item);}return copy;
}
function syncHighlights(){for(const {selector,content}of highlights){
 const node=nav.querySelector(selector),source=node?.closest('.site-menu'),opened=[...content.querySelectorAll('details')].map(n=>n.open);content.replaceChildren();
 if(!source||source.hidden){content.append(el('p','로그인과 이용 권한에 따라 사용할 수 있는 메뉴입니다.'));continue;}
 if(source.matches('button')){content.append(menuCopy(source));continue;}
 const menu=el('details');menu.className='spotlight-submenu';menu.append(el('summary','하위 메뉴 보기'));
 for(const child of source.children){const item=menuCopy(child);if(item)menu.append(item);}content.append(menu);content.querySelectorAll('details').forEach((n,i)=>{n.open=!!opened[i];});
}}
home.prepend(spotlight);syncHighlights();
new MutationObserver(syncHighlights).observe(nav,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled']});
function mbtiStep(step){const tabs=[...doc.querySelectorAll('#mbtiStudyTabs button')].filter(b=>!b.hidden&&!b.disabled),i=tabs.findIndex(b=>b.getAttribute('aria-pressed')==='true');if(i<0||!tabs[i+step])return false;tabs[i+step].click();if(!reduced()){const panel=doc.getElementById('mbtiStudyCards');panel.classList.remove('cheongla-slide-left','cheongla-slide-right');void panel.offsetWidth;panel.classList.add(step>0?'cheongla-slide-left':'cheongla-slide-right');}return true;}
function horizontalArea(node){for(let n=node;n&&n!==doc.body;n=n.parentElement){if(n.classList.contains('swipe-rail'))return true;if(n.scrollWidth>n.clientWidth+8&&['auto','scroll'].includes(root.getComputedStyle(n).overflowX))return true;}return false;}
let dragPanel=null,dragFrame=0,dragX=0,clickUntil=0,clickNode=null;
function resetDrag(animate=false){
 if(dragFrame){root.cancelAnimationFrame(dragFrame);dragFrame=0;}
 if(dragPanel){const panel=dragPanel;dragPanel=null;panel.classList.remove('cheongla-dragging');
  if(animate&&!reduced()){panel.classList.add('cheongla-drag-return');root.setTimeout(()=>panel.classList.remove('cheongla-drag-return'),180);}
  panel.style.removeProperty('--cheongla-drag-x');
 }
}
function preview(dx,node){
 if(reduced())return;if(!dragPanel){dragPanel=node.closest('#accountPanel,#publicContentPanel,#informationPanel,#newInquiryPanel,#homeDictionary,#homePanel');if(!dragPanel)return;dragPanel.classList.remove('cheongla-slide-left','cheongla-slide-right','cheongla-drag-return');dragPanel.classList.add('cheongla-dragging');}
 dragX=Math.sign(dx)*Math.min(Math.abs(dx)*.75,root.innerWidth*.4);
 if(!dragFrame)dragFrame=root.requestAnimationFrame(()=>{dragFrame=0;dragPanel?.style.setProperty('--cheongla-drag-x',dragX+'px');});
}
function available(step){const index=state().index||0;return step<0?index>0:index<furthest;}
function start(event){gesture=null;if(navigating||restoring)return;resetDrag();if(event.touches.length!==1||blocked(event.target))return;const p=event.touches[0],width=root.visualViewport?.width||root.innerWidth;
 // Leave the outermost edge to Safari's native back gesture.
 if(p.clientX<16||p.clientX>width-16||horizontalArea(event.target))return;
 gesture={x:p.clientX,y:p.clientY,time:Date.now(),node:event.target,locked:false};
}
function move(event){if(!gesture)return;if(event.touches.length!==1){gesture=null;resetDrag(true);return;}
 const p=event.touches[0],dx=p.clientX-gesture.x,dy=p.clientY-gesture.y;
 if(!gesture.locked&&Math.abs(dy)>8&&Math.abs(dy)>Math.abs(dx)*1.15){gesture=null;resetDrag(true);return;}
 if(!gesture.locked&&Math.abs(dx)>5&&Math.abs(dx)>Math.abs(dy)*1.1){if(!available(dx>0?-1:1)){gesture=null;return;}gesture.locked=true;}
 if(gesture.locked){if(event.cancelable)event.preventDefault();preview(dx,gesture.node);}
}
function end(event){const g=gesture;gesture=null;if(!g||event.changedTouches.length!==1){resetDrag(true);return;}
 const p=event.changedTouches[0],dx=p.clientX-g.x,dy=p.clientY-g.y,elapsed=Date.now()-g.time;
 if(g.locked){clickUntil=Date.now()+450;clickNode=g.node.closest('button,a,summary');}
 const threshold=Math.min(56,(root.visualViewport?.width||root.innerWidth)*.14);
 const committed=Math.abs(dx)>=threshold||(Math.abs(dx)>=30&&elapsed<240);
 if(blocked(g.node)||elapsed>2000||!committed||Math.abs(dx)<Math.abs(dy)*1.2||!available(dx>0?-1:1)){resetDrag(true);return;}
 void navigate(dx>0?-1:1);
}
doc.addEventListener('touchstart',start,{capture:true,passive:true});doc.addEventListener('touchmove',move,{capture:true,passive:false});doc.addEventListener('touchend',end,{capture:true,passive:true});doc.addEventListener('touchcancel',()=>{gesture=null;resetDrag(true);},{capture:true,passive:true});
// A drag that starts on a large menu/action button must not also activate it.
root.addEventListener('click',event=>{if(Date.now()<clickUntil&&event.isTrusted&&clickNode&&event.target.closest('button,a,summary')===clickNode){event.preventDefault();event.stopImmediatePropagation();}},true);
// Save menu expansion and card offset before the destination closes the original menu.
doc.addEventListener('click',event=>{if(restoring||!event.target.closest('#siteNavigation button,[data-home-route],#homeSpotlightRail button'))return;pendingOrigin={key:entryKey(activeEntry),position:snapshot()};},true);
for(const name of ['input','change'])doc.addEventListener(name,e=>{const f=e.target.form;if(f&&f.id!=='mbtiStudyForm'&&!e.target.matches('[type=search]'))dirtyForms.add(f);schedule();},true);
doc.addEventListener('reset',e=>{dirtyForms.delete(e.target);schedule();},true);
const record=recordSiteView;root.recordSiteView=function(...args){remember();const previous=entryKey(state()),r=record(...args);if(previous!==entryKey(state())){restoreToken++;activeEntry=state();furthest=activeEntry.index||0;pendingOrigin=null;}schedule();return r;};
const menu=configureDeskMenu;root.configureDeskMenu=function(...args){const r=menu(...args);schedule();return r;};
const clear=clearAccount;root.clearAccount=function(...args){dirtyForms=new WeakSet();gesture=null;positions.clear();pendingOrigin=null;restoreToken++;return clear(...args);};
new MutationObserver(scan).observe(doc.getElementById('publicContentBody'),{childList:true,subtree:true});
root.addEventListener('cheongla:view-restoring',()=>{remember();pendingOrigin=null;restoring=true;restoreToken++;});
root.addEventListener('cheongla:view-restored',restorePosition);
root.addEventListener('popstate',schedule);root.addEventListener('resize',schedule,{passive:true});
const tabs=doc.getElementById('mbtiStudyTabs');if(tabs){tabs.classList.add('cheongla-swipe-tabs');const hint=el('p','과목은 위의 탭으로 선택 · 오른쪽으로 쓸면 이전 화면');hint.className='cheongla-swipe-hint';tabs.after(hint);}
root.CheonglaSwipe={enabled:true,groups,navigate,scan,mbtiStep};scan();
})(globalThis);
