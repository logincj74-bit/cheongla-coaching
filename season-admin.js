/* Shared visual preference. Only the approved active English director may write; RLS is authoritative. */
(function(root){'use strict';
 const doc=root.document;if(!doc?.head||root.CheonglaSeasonAdmin)return;
 const names={auto:'자동 · 달에 맞춰 변경',spring:'봄 · 벚꽃잎',summer:'여름 · 반짝이는 물방울',autumn:'가을 · 낙엽',winter:'겨울 · 눈'};
 const css=doc.createElement('link');css.rel='stylesheet';css.href='season-effects.css?v=1.9.42';doc.head.append(css);
 let panel,select,feedback,apply,setting=null,busy=false,reading=false,dirty=false;
 const actor=()=>typeof currentProfile!=='undefined'?currentProfile:null;
 const allowed=()=>{const p=actor();return p?.role==='english_director'&&p.approval_status==='approved'&&p.membership_state==='active';};
 const el=(tag,text)=>{const n=doc.createElement(tag);if(text)n.textContent=text;return n;};
 const client=()=>getClient();
 function use(row){setting=row;root.CheonglaSeasonMode=row.mode;root.CheonglaSeasonal?.setMode(row.mode);if(select&&!dirty)select.value=row.mode;}
 function configure(){
  if(!panel){const host=doc.querySelector('.home-motion-controls');if(!host)return;panel=el('details');panel.id='seasonAdminSettings';panel.className='season-admin-settings';panel.hidden=true;panel.append(el('summary','계절 효과 설정'));const label=el('label','홈화면 효과');select=el('select');select.setAttribute('aria-label','홈화면 계절 효과');for(const[value,text]of Object.entries(names)){const op=el('option',text);op.value=value;select.append(op);}label.append(select);apply=el('button','전체에 적용');apply.type='button';feedback=el('p');feedback.setAttribute('role','status');panel.append(label,apply,el('small','영어원장 전용 · 모든 이용자의 홈화면에 적용됩니다. 효과 끄기는 각 기기에서 선택합니다.'),feedback);host.after(panel);select.addEventListener('change',()=>{dirty=true;feedback.textContent='선택한 효과를 적용하려면 전체에 적용을 눌러 주세요.';});apply.addEventListener('click',save);if(setting)select.value=setting.mode;}
  panel.hidden=!allowed();if(!allowed()){panel.open=false;dirty=false;if(setting)select.value=setting.mode;}apply.disabled=busy||!setting;select.disabled=busy||!setting;
 }
 async function sync(){if(reading||busy||doc.hidden)return;reading=true;try{const c=await client();const r=await c.from('cheongla_season_settings').select('mode,updated_at').eq('singleton',true).single();if(r.error)throw r.error;use(r.data);if(feedback&&!dirty)feedback.textContent='현재 적용: '+names[r.data.mode];}catch(e){if(feedback)feedback.textContent='설정을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';}finally{reading=false;configure();}}
 async function save(){if(busy||!allowed()||!setting)return;const who=actor()?.id,mode=select.value,version=setting.updated_at;if(!Object.hasOwn(names,mode))return;busy=true;configure();feedback.textContent='적용 중…';try{const c=await client();const r=await c.from('cheongla_season_settings').update({mode}).eq('singleton',true).eq('updated_at',version).select('mode,updated_at').maybeSingle();if(r.error)throw r.error;if(!r.data)throw Error('conflict');if(actor()?.id!==who||!allowed())return;dirty=false;use(r.data);feedback.textContent='적용 완료 · '+names[mode]+' · 다른 이용자 화면은 최대 30초 내 갱신됩니다.';}catch(e){if(allowed())feedback.textContent=e.message==='conflict'?'설정이 변경됐거나 권한을 확인할 수 없습니다. 새로 불러온 설정을 확인한 뒤 다시 적용해 주세요.':'적용되지 않았습니다. 연결 상태를 확인하고 다시 눌러 주세요.';}finally{busy=false;configure();if(allowed()&&feedback.textContent.startsWith('설정이 변경'))void sync();}}
 root.CheonglaSeasonAdmin={sync,configure};
 if(typeof configureStaffWorkspace==='function'){const original=configureStaffWorkspace;configureStaffWorkspace=function(...args){const result=original.apply(this,args);configure();return result;};}
 configure();void sync();root.setInterval(()=>void sync(),30000);doc.addEventListener('visibilitychange',()=>{configure();if(!doc.hidden)void sync();});root.addEventListener('pageshow',()=>{configure();void sync();});
})(globalThis);
