/* Staff journal inbox and principal-only acknowledgement view. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,tabs=doc.getElementById('journalInboxTabs'),box=doc.getElementById('journalAlertsBox'),all=doc.getElementById('allNotificationContents');
 const staff=()=>{const p=api.profile();return p?.approval_status==='approved'&&p.membership_state==='active'&&['owner','english_director','math_director','manager','korean_teacher'].includes(p.role);};
 let mode='all',epoch=0,request=0,busy=false,limit=20,actorRef=null,monitorRequest=0,monitorBusy=false,monitorLimit=20;
 const el=(tag,text,cls)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 const button=(text,fn,cls='secondary')=>{const b=el('button',text,cls);b.type='button';b.addEventListener('click',()=>void fn());return b;};
 const stamp=t=>t?api.date(t):'미확인';
 const allTab=button('전체 알림 · 푸시 설정',()=>select('all')),journalTab=button('근무일지 알림',()=>select('journal'));
 tabs.append(allTab,journalTab);tabs.setAttribute('aria-label','알림 보기 선택');
 box.append(el('h3','근무일지 알림'),el('p','본인에게 온 근무일지 알림만 표시합니다. 읽음 시각은 원장이 확인할 수 있습니다.','muted'));
 const reload=button('근무일지 알림 새로고침',()=>refresh()),status=el('p',undefined,'muted');status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const list=el('div'),more=button('근무일지 알림 더 보기',()=>{limit=Math.min(limit+20,200);return refresh();},'text-button');more.hidden=true;box.append(reload,status,list,more);
 const monitor=el('details'),summary=el('summary','근무일지 알림 읽음 현황 · 원장 전용');monitor.append(summary,el('p','알림 열기 또는 ‘모두 읽음’ 처리 기준입니다. 연속 저장 묶음은 처음 읽은 시각을 표시합니다. 알림을 삭제해도 읽음 기록은 유지됩니다.','muted'));
 const monitorReload=button('읽음 현황 새로고침',()=>loadMonitor()),monitorStatus=el('p',undefined,'muted'),monitorList=el('div'),monitorMore=button('이전 읽음 현황 더 보기',()=>{monitorLimit=Math.min(monitorLimit+20,100);return loadMonitor();},'text-button');monitorMore.hidden=true;monitorStatus.setAttribute('role','status');monitor.append(monitorReload,monitorStatus,monitorList,monitorMore);monitor.hidden=true;box.append(monitor);
 function paint(){all.hidden=mode==='journal';box.hidden=mode!=='journal';allTab.setAttribute('aria-pressed',String(mode==='all'));journalTab.setAttribute('aria-pressed',String(mode==='journal'));monitor.hidden=!staff()||!api.principal();}
 function reset(){epoch++;request++;monitorRequest++;busy=monitorBusy=false;mode='all';limit=monitorLimit=20;actorRef=null;list.replaceChildren();monitorList.replaceChildren();status.textContent=monitorStatus.textContent='';more.hidden=monitorMore.hidden=true;reload.disabled=monitorReload.disabled=false;monitor.open=false;tabs.hidden=true;paint();monitor.hidden=true;}
 function sync(){const p=api.profile();if(p!==actorRef){reset();actorRef=p;}tabs.hidden=!staff();if(!staff())mode='all';paint();}
 async function select(next){sync();if(next==='journal'&&!staff())return;mode=next;paint();if(mode==='journal')await refresh();else await api.refreshAll();}
 async function rpc(name,args){const client=await api.client();const r=await client.rpc(name,args);if(r.error)throw r.error;return r.data;}
 async function refresh(){
  if(mode!=='journal'||!staff()||busy)return;const actor=api.profile(),e=epoch,r=++request;busy=true;reload.disabled=true;status.textContent='근무일지 알림 확인 중…';
  try{const data=await rpc('cheongla_my_journal_notifications',{page_limit:limit});if(actor!==api.profile()||e!==epoch||r!==request||mode!=='journal'||!staff())return;
   list.replaceChildren();for(const n of data?.items||[]){const card=el('article',undefined,'qa-item'+(!n.read_at?' notification-unread':''));const title=button(n.title,()=>api.navigate(n.id),'notification-title-link');card.append(title,el('p',(n.read_at?'읽음 · '+stamp(n.read_at):'새 알림')+' · 받은 시각 '+stamp(n.created_at),'muted'),button('해당 날짜 근무일지 열기',()=>api.navigate(n.id)),button('삭제 · 휴지통으로',async()=>{request++;busy=false;await api.archive(n.id,card.lastElementChild);if(actor===api.profile()&&e===epoch)await refresh();},'text-button'));list.append(card);}
   if(!(data?.items||[]).length)list.append(el('p','도착한 근무일지 알림이 없습니다.','muted'));
   status.textContent='읽지 않은 근무일지 알림 '+Number(data?.unread_count||0)+'건 · 휴지통은 전체 알림에서 관리합니다.';more.hidden=(data?.items||[]).length<limit||limit>=200;
  }catch(err){if(actor===api.profile()&&e===epoch&&r===request){list.replaceChildren();status.textContent=api.readable(err);more.hidden=true;}}
  finally{if(actor===api.profile()&&e===epoch&&r===request){busy=false;reload.disabled=false;}}
  if(monitor.open)await loadMonitor();
 }
 const actions={write:'새 내용 기록',edit:'내용 기록·수정',content_delete:'내용 수정·삭제',close:'업무 마감',archive:'일지 휴지통 이동',restore:'일지 복구',purge:'일지 영구삭제'};
 const roles={owner:'원장',english_director:'영어원장',math_director:'수학원장',manager:'실장',korean_teacher:'국어선생님'};
 async function loadMonitor(){
  if(mode!=='journal'||!staff()||!api.principal()||!monitor.open||monitorBusy)return;const actor=api.profile(),e=epoch,r=++monitorRequest;monitorBusy=true;monitorReload.disabled=true;monitorStatus.textContent='읽음 현황 확인 중…';
  try{const data=await rpc('cheongla_journal_alert_activity',{page_limit:monitorLimit});if(actor!==api.profile()||e!==epoch||r!==monitorRequest||!staff()||!api.principal())return;
   monitorList.replaceChildren();for(const item of data?.items||[]){const card=el('article',undefined,'qa-item');card.append(el('h4',item.work_on+' · '+(actions[item.action]||'근무일지 변경')),el('p',(item.author_name||'근무자')+' · '+stamp(item.opened_at),'muted'),el('p','전달 대상 '+item.recipient_count+'명 · 알림 읽음 '+item.read_count+'명'));
    const recipients=el('ul');for(const person of item.recipients||[])recipients.append(el('li',person.name+' · '+(roles[person.role]||'근무자')+' · '+(person.read_at?'읽음 '+stamp(person.read_at):'미확인')+(person.currently_active?'':' · 현재 이용 상태 변경')));card.append(recipients,button('이 날짜 근무일지 열기',()=>api.openDate(item.work_on)));monitorList.append(card);}
   if(!(data?.items||[]).length)monitorList.append(el('p','확인할 근무일지 알림 기록이 없습니다.','muted'));
   monitorStatus.textContent='최근 '+(data?.items||[]).length+'건 · 알림 읽음과 업무 처리 결과를 함께 확인해 주세요.';monitorMore.hidden=(data?.items||[]).length<monitorLimit||monitorLimit>=100;
  }catch(err){if(actor===api.profile()&&e===epoch&&r===monitorRequest){monitorList.replaceChildren();monitorStatus.textContent=api.readable(err);monitorMore.hidden=true;}}
  finally{if(actor===api.profile()&&e===epoch&&r===monitorRequest){monitorBusy=false;monitorReload.disabled=false;}}
 }
 monitor.addEventListener('toggle',()=>{if(monitor.open)void loadMonitor();});reset();
 return{reset,sync,select,refresh,loadMonitor,refreshIfOpen(){const panel=doc.getElementById('notificationPanel');if(panel&&!panel.hidden&&!panel.classList.contains('account-section-inactive'))void refresh();},get mode(){return mode;}};
}
root.CheonglaJournalAlerts={mount};
})(globalThis);
