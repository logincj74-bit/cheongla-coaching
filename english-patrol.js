/* Approved-member English: flashcards, downloadable wordbook and etymology. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,english=doc.getElementById('englishPanel'),profile=()=>api.profile();
 const member=()=>profile()?.approval_status==='approved'&&profile()?.membership_state==='active';
 const staff=()=>member()&&['owner','english_director','math_director','manager'].includes(profile()?.role);
 const cards=root.CheonglaEnglishCards?.mount(api);let epoch=0,bookURL=null;
 const el=(tag,text,cls)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 const btn=(text,fn)=>{const b=el('button',text,'secondary');b.type='button';b.addEventListener('click',fn);return b;};
 async function rpc(name,args={}){const c=await api.client(),r=await c.rpc(name,args);if(r.error)throw r.error;return r.data;}
 async function leave(){return cards?cards.leave():true;}
 function reset(){epoch++;cards?.reset();if(bookURL)root.URL.revokeObjectURL(bookURL);bookURL=null;english.replaceChildren();}
 async function open(kind='study'){
  kind=kind==='book'?'book':'study';
  if(!member())return;if(!await leave())return;const request=++epoch,actor=profile();english.hidden=false;english.replaceChildren();english.append(el('h2','청라영어'),el('p','영어 어원사전 · 플래시카드 암기 · 수능 기출 단어장','muted'));const tabs=el('div',undefined,'row');tabs.append(btn('카드로 암기',()=>api.navigate('english_study')),btn('수능 기출 단어장',()=>api.navigate('english_book')));const dictionary=el('a','영어 어원사전 Etymonline ↗','contact-link');dictionary.href='https://www.etymonline.com/';dictionary.target='_blank';dictionary.rel='noopener noreferrer';tabs.append(dictionary);english.append(tabs);const message=el('p','불러오는 중…');message.setAttribute('role','status');english.append(message);
  try{if(kind==='book'){message.textContent='표지는 청라 로고와 제목으로 교체했으며 단어장 본문은 원본입니다.';const load=btn('단어장 열기 · 내려받기',async()=>{load.disabled=true;try{const raw=await rpc('cheongla_english_wordbook');if(request!==epoch||actor!==profile())return;const binary=root.atob(raw),bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));if(bookURL)root.URL.revokeObjectURL(bookURL);bookURL=root.URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}));const a=el('a','수능 기출 단어 PDF 내려받기','contact-link');a.href=bookURL;a.download='청라_수능기출단어.pdf';const frame=el('iframe');frame.title='수능 기출 단어장';frame.src=bookURL;frame.style.cssText='width:100%;height:75vh;border:1px solid #dce4d9;margin-top:18px';english.append(a,frame);load.hidden=true;}catch(e){message.textContent=api.readable(e);}finally{load.disabled=false;}});english.append(load);return;}
   const catalog=await rpc('cheongla_english_catalog');if(request!==epoch||actor!==profile())return;if(!cards)throw Error('플래시카드 기능을 불러오지 못했습니다. 앱을 다시 열어 주세요.');message.textContent='올려주신 원본 33회차 · 총 1,597단어로 학습합니다.';await cards.open(english,catalog,'study');
  }catch(e){if(request===epoch)message.textContent=api.readable(e);}
 }
 return{open,openPatrol:async()=>false,reset,leave,member,staff,get dirty(){return !!cards?.dirty;}};
}
root.CheonglaEnglishPatrol={mount};
})(globalThis);
