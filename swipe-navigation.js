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
let dirtyForms=new WeakSet(),gesture=null,direction=0,frame=0;
function activePanel(){if(!doc.getElementById('accountPanel').hidden){const p=[...doc.querySelectorAll('#accountPanel>section')].find(visible);if(p)return p;}return ['publicContentPanel','informationPanel','newInquiryPanel','homeDictionary','homePanel'].map(id=>doc.getElementById(id)).find(visible);}
function dirtyVisible(){return [...doc.querySelectorAll('form')].some(f=>visible(f)&&dirtyForms.has(f));}
function editable(n){return n?.closest?.('input,textarea,select,[contenteditable="true"]');}
function protectedScreen(){return ['staffJournalPanel','officeSmsPanel','registrationPanel','scoreCoachingPanel','learningPanel'].some(id=>visible(doc.getElementById(id)));}
function blocked(start){return doc.querySelector('dialog[open]')||editable(doc.activeElement)||dirtyVisible()||protectedScreen()||start?.closest?.('input,textarea,select,button,a,summary,video,audio,[contenteditable="true"],#siteBackControls,#siteNavigation,.rules-image-expanded');}
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
const pager=el('section');pager.className='cheongla-menu-pager';pager.setAttribute('aria-label','좌우 메뉴 이동');
const previous=btn('← 이전 메뉴',()=>navigate(-1)),next=btn('다음 메뉴 →',()=>navigate(1)),label=el('p'),help=el('p','본문을 좌우로 밀어 메뉴를 이동할 수 있습니다.');label.setAttribute('role','status');label.setAttribute('aria-live','polite');help.className='swipe-help';pager.append(previous,next,label,help);nav.after(pager);
function sync(){frame=0;const list=groups(),s=state();const index=s.view==='home'?-1:list.findIndex(g=>g.keys.includes(s.key));previous.disabled=index<=0;next.disabled=index>=list.length-1||!list.length;
 label.textContent=index>=0?list[index].label+' · '+(index+1)+' / '+list.length:'청라 첫 화면';previous.textContent=index>0?'← '+list[index-1].label:'← 이전 메뉴';next.textContent=index<list.length-1?(list[index+1]?.label||list[0]?.label)+' →':'다음 메뉴 →';
 help.textContent=protectedScreen()||dirtyVisible()?'작성 화면에서는 스와이프 이동을 잠시 멈춥니다.':'본문 좌우 스와이프 · 카드와 사진은 해당 영역만 넘깁니다.';
 if(direction){const panel=activePanel();if(panel&&!reduced()){panel.classList.remove('cheongla-slide-left','cheongla-slide-right');void panel.offsetWidth;panel.classList.add(direction>0?'cheongla-slide-left':'cheongla-slide-right');root.setTimeout(()=>panel.classList.remove('cheongla-slide-left','cheongla-slide-right'),220);}direction=0;}
}
function schedule(){if(!frame)frame=root.requestAnimationFrame(sync);}
function navigate(step){if(doc.querySelector('dialog[open]')||dirtyVisible()){help.textContent='작성 중인 내용을 먼저 저장하거나 취소해 주세요.';return false;}const list=groups(),s=state(),i=s.view==='home'?-1:list.findIndex(g=>g.keys.includes(s.key)),target=list[i+step];if(!target)return false;direction=step;target.buttons[0].click();root.setTimeout(()=>{direction=0;schedule();},400);return true;}
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
function highlight(title,body,selector){const card=el('article');card.className='cheongla-swipe-card';card.append(el('small','CHEONGLA'),el('h3',title),el('p',body),btn('자세히 보기',()=>{const b=doc.querySelector(selector);b?.click();}));homeRail.append(card);return card;}
highlight('학원 소개','공부에 집중하는 하루, 청라의 생활 관리와 학습 지원을 만나보세요.','#siteNavigation [data-public-page="greeting"]');
highlight('청라 모습','학습 공간을 사진으로 둘러보세요. 사진도 좌우로 넘길 수 있습니다.','#siteNavigation [data-public-page="photos"]');
highlight('청라 소식','주요 입시 소식과 학원에서 전하는 자료를 확인하세요.','#siteNavigation [data-member-page="admissions_news"]');
const winterCard=highlight('윈터스쿨','자기주도학습을 준비하는 청라 윈터스쿨 안내를 확인하세요.','#winterPromotion a[href]');winterCard.hidden=true;home.prepend(spotlight);
const winter=doc.getElementById('winterPromotion');if(winter)new MutationObserver(()=>{const hidden=winter.hidden||!winter.querySelector('a[href]');if(winterCard.hidden!==hidden){winterCard.hidden=hidden;const instance=rails.get(homeRail);if(instance){instance.observer.disconnect();root.removeEventListener('resize',instance.update);rails.delete(homeRail);instance.controls.remove();attachRail(homeRail,'청라 주요 안내');}}}).observe(winter,{attributes:true,attributeFilter:['hidden'],childList:true});
function mbtiStep(step){const tabs=[...doc.querySelectorAll('#mbtiStudyTabs button')].filter(b=>!b.hidden&&!b.disabled),i=tabs.findIndex(b=>b.getAttribute('aria-pressed')==='true');if(i<0||!tabs[i+step])return false;tabs[i+step].click();if(!reduced()){const panel=doc.getElementById('mbtiStudyCards');panel.classList.remove('cheongla-slide-left','cheongla-slide-right');void panel.offsetWidth;panel.classList.add(step>0?'cheongla-slide-left':'cheongla-slide-right');}return true;}
function horizontalArea(node){for(let n=node;n&&n!==doc.body;n=n.parentElement){if(n.classList.contains('swipe-rail'))return true;if(n.scrollWidth>n.clientWidth+8&&['auto','scroll'].includes(root.getComputedStyle(n).overflowX))return true;}return false;}
function start(event){gesture=null;if(event.touches.length!==1||blocked(event.target))return;const p=event.touches[0],width=root.visualViewport?.width||root.innerWidth;if(p.clientX<28||p.clientX>width-28)return;if(horizontalArea(event.target))return;gesture={x:p.clientX,y:p.clientY,time:Date.now(),local:!!event.target.closest('#mbtiStudyCards,#mbtiStudySummary'),node:event.target};}
function move(event){if(!gesture)return;if(event.touches.length!==1){gesture=null;return;}const p=event.touches[0],dx=p.clientX-gesture.x,dy=p.clientY-gesture.y;if(Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx)){gesture=null;return;}if(Math.abs(dx)>18&&Math.abs(dx)>Math.abs(dy)*1.6&&event.cancelable)event.preventDefault();}
function end(event){const g=gesture;gesture=null;if(!g||event.changedTouches.length!==1||blocked(g.node)||Date.now()-g.time>1200)return;const p=event.changedTouches[0],dx=p.clientX-g.x,dy=p.clientY-g.y;if(Math.abs(dx)<70||Math.abs(dx)<Math.abs(dy)*1.8)return;const step=dx<0?1:-1;if(g.local){mbtiStep(step);return;}navigate(step);}
doc.addEventListener('touchstart',start,{passive:true});doc.addEventListener('touchmove',move,{passive:false});doc.addEventListener('touchend',end,{passive:true});doc.addEventListener('touchcancel',()=>gesture=null,{passive:true});
for(const name of ['input','change'])doc.addEventListener(name,e=>{const f=e.target.form;if(f&&f.id!=='mbtiStudyForm'&&!e.target.matches('[type=search]'))dirtyForms.add(f);schedule();},true);
doc.addEventListener('reset',e=>{dirtyForms.delete(e.target);schedule();},true);
const record=recordSiteView;root.recordSiteView=function(...args){const r=record(...args);schedule();return r;};
const menu=configureDeskMenu;root.configureDeskMenu=function(...args){const r=menu(...args);schedule();return r;};
const clear=clearAccount;root.clearAccount=function(...args){dirtyForms=new WeakSet();gesture=null;return clear(...args);};
new MutationObserver(scan).observe(doc.getElementById('publicContentBody'),{childList:true,subtree:true});
root.addEventListener('popstate',schedule);root.addEventListener('resize',schedule,{passive:true});
const tabs=doc.getElementById('mbtiStudyTabs');if(tabs){tabs.classList.add('cheongla-swipe-tabs');const hint=el('p','← 학습법 본문을 좌우로 밀면 과목이 바뀝니다 →');hint.className='cheongla-swipe-hint';tabs.after(hint);}
root.CheonglaSwipe={enabled:true,groups,navigate,scan,mbtiStep};scan();
})(globalThis);
