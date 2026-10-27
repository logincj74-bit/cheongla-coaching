// Public dictionary content only. Server RLS authorizes principal writes.
export function mountDictionaryAdmin(adapter,api){
 const doc=adapter.document||document,host=doc.getElementById('homeDictionary');
 if(!host||host.querySelector('#dictionaryAdmin'))return {configure(){}};
 const actor=()=>adapter.profile?.(),allowed=()=>{const p=actor();return !!p&&p.approval_status==='approved'&&p.membership_state==='active'&&['owner','english_director','math_director'].includes(p.role);};
 const el=(tag,text,cls)=>{const n=doc.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
 const link=el('link');link.rel='stylesheet';link.href='dictionary-admin.css?v=20261027-1';doc.head.append(link);
 const box=el('details',null,'dictionary-admin');box.id='dictionaryAdmin';box.hidden=true;box.append(el('summary','원장 · 단어 추가·수정'));
 box.append(el('p','등록하거나 수정한 뜻은 모든 이용자의 검색에 반영됩니다. 기본 사전 자료는 그대로 보관됩니다.'));
 const wordLabel=el('label','관리할 영어 단어'),word=el('input');word.type='search';word.maxLength=80;word.autocapitalize='none';word.spellcheck=false;word.setAttribute('aria-label','관리할 영어 단어');wordLabel.append(word);
 const loadButton=el('button','단어 불러오기');loadButton.type='button';const loadRow=el('div',null,'dictionary-admin-actions');loadRow.append(wordLabel,loadButton);box.append(loadRow);
 const form=el('form'),pronLabel=el('label','발음기호 (선택)'),pron=el('input');pron.maxLength=180;pron.setAttribute('aria-label','등록할 발음기호');pronLabel.append(pron);form.append(pronLabel,el('p','품사와 뜻을 입력하세요. 뜻 하나당 한 줄로, 최대 20개까지 등록할 수 있습니다.'));
 const senses=el('div',null,'dictionary-admin-senses');form.append(senses);
 const add=el('button','＋ 뜻 추가');add.type='button';add.className='secondary';form.append(add);
 const save=el('button','단어·뜻 저장');save.type='submit';const restore=el('button','원장 등록 뜻 지우기');restore.type='button';restore.className='secondary';const actions=el('div',null,'dictionary-admin-actions');actions.append(save,restore);form.append(actions);box.append(form);
 const status=el('p');status.setAttribute('role','status');status.setAttribute('aria-live','polite');status.textContent='단어를 입력하고 단어 불러오기를 눌러 주세요.';box.append(status);
 const report=el('details');report.append(el('summary','기본 어휘 점검 결과'));report.append(el('p','2015·2022 개정 교육과정의 기본 어휘 각 3,000개와 목록에 제시된 관련형, NGSL 1.2, NAWL 1.2를 대조했습니다. 세부 수치는 점검 보고서에서 확인할 수 있습니다. 수능에 출제되는 모든 어휘를 보장하는 목록은 아닙니다.'));const reportLink=el('a','어휘 점검 보고서');reportLink.href='assets/dictionary/coverage-report.json';reportLink.target='_blank';reportLink.rel='noopener';report.append(reportLink);box.append(report);
 host.insertBefore(box,doc.getElementById('dictionaryResultsWrap'));
 const pos=[['','품사 선택'],['n.','명사'],['v.','동사'],['adj.','형용사'],['adv.','부사'],['pron.','대명사'],['prep.','전치사'],['conj.','접속사'],['interj.','감탄사'],['det.','한정사'],['num.','수사'],['art.','관사'],['phr.','구'],['고유명사','고유명사'],['약어','약어'],['접두사','접두사'],['접미사','접미사']];
 let dirty=false,busy=false,loaded=null,owner=null,request=0;
 const confirm=text=>adapter.confirm?adapter.confirm(text):Promise.resolve(window.confirm(text));
 function row(part='',meaning=''){
  const line=el('div',null,'dictionary-admin-sense'),select=el('select');select.setAttribute('aria-label','뜻의 품사');for(const [key,label]of pos){const o=el('option',label);o.value=key;select.append(o);}select.value=part;
  const input=el('textarea');input.rows=2;input.maxLength=600;input.required=true;input.value=meaning;input.setAttribute('aria-label','한국어 뜻');const remove=el('button','줄 지우기');remove.type='button';remove.className='secondary';remove.addEventListener('click',()=>{line.remove();dirty=true;if(!senses.children.length)row();configure();});
  for(const n of [select,input])n.addEventListener('input',()=>{dirty=true;status.textContent='변경 내용을 저장해 주세요.';});line.append(select,input,remove);senses.append(line);
 }
 function configure(){
  const p=actor();if(owner&&owner!==p?.id){request++;loaded=null;dirty=false;pron.value='';senses.replaceChildren();word.value='';status.textContent='단어를 입력하고 불러오세요.';}owner=p?.id||null;
  box.hidden=!allowed();for(const n of box.querySelectorAll('input,select,textarea,button'))n.disabled=busy||!allowed();
  save.disabled=busy||!allowed()||!loaded;add.disabled=save.disabled||senses.children.length>=20;restore.hidden=!loaded?.custom;restore.disabled=save.disabled;
 }
 async function load(){
  if(busy||!allowed())return;const key=api.normalize(word.value);if(!api.valid(key)){status.textContent='올바른 영어 단어를 입력해 주세요.';return;}
  if(dirty&&!await confirm('저장하지 않은 내용을 취소하고 다른 단어를 불러올까요?'))return;
  const who=actor()?.id,ticket=++request;busy=true;configure();status.textContent='단어를 불러오는 중…';
  try{
   const c=await adapter.client();if(actor()?.id!==who||!allowed())return;const r=await c.from('cheongla_dictionary_overrides').select('word,pronunciation,senses,updated_at').eq('word',key).maybeSingle();if(r.error)throw r.error;
   let original;if(!r.data){const b=await api.baseLookup(key);original=b.results.find(x=>x.word===key);if(b.incomplete)throw Error('기본 사전 연결을 확인한 후 다시 불러와 주세요.');}
   if(ticket!==request||actor()?.id!==who||!allowed())return;
   loaded={word:key,version:r.data?.updated_at||null,custom:!!r.data};word.value=key;pron.value=r.data?.pronunciation||original?.pronunciation?.slice(0,180)||'';senses.replaceChildren();
   const rows=r.data?.senses||original?.senses.map(x=>({pos:pos.find(p=>p[1]===x.pos)?.[0]||'',meaning:x.meaning}))||[{pos:'',meaning:''}];for(const sense of rows.slice(0,20))row(sense.pos,sense.meaning);
   dirty=false;status.textContent=r.data?'원장님이 등록한 뜻입니다. 수정한 뒤 저장하세요.':original?'기본 사전의 뜻입니다. 수정하면 원장 등록 뜻이 우선 표시됩니다.':'새 단어입니다. 한국어 뜻을 입력한 뒤 저장하세요.';
  }catch(e){status.textContent=e.message||'불러오지 못했습니다. 다시 시도해 주세요.';}finally{busy=false;configure();}
 }
 async function persist(remove=false){
  if(busy||!allowed()||!loaded)return;if(api.normalize(word.value)!==loaded.word){status.textContent='단어가 바뀌었습니다. 단어 불러오기를 먼저 눌러 주세요.';return;}
  if(remove&&!await confirm('이 단어에 원장님이 등록한 뜻을 지울까요? 기본 사전의 뜻은 유지됩니다.'))return;
  const data={pronunciation:pron.value.trim(),senses:[...senses.children].map(line=>({pos:line.querySelector('select').value,meaning:line.querySelector('textarea').value.trim()}))};
  if(!remove&&(!form.reportValidity()||!data.senses.length||data.senses.some(x=>!x.meaning))){status.textContent='빈 뜻을 채워 주세요.';return;}
  const who=actor()?.id,snapshot={...loaded};busy=true;configure();status.textContent='저장 중…';
  try{
   const c=await adapter.client();if(actor()?.id!==who||!allowed())return;const table=c.from('cheongla_dictionary_overrides');
   const q=remove?table.delete().eq('word',snapshot.word).eq('updated_at',snapshot.version):snapshot.custom?table.update(data).eq('word',snapshot.word).eq('updated_at',snapshot.version):table.insert({word:snapshot.word,...data});
   const r=await q.select('word,pronunciation,senses,updated_at').maybeSingle();if(r.error)throw r.error;if(!r.data)throw Error('다른 기기에서 이 단어가 변경되었습니다. 작성한 뜻을 복사해 두고 다시 불러와 주세요.');
   if(actor()?.id!==who||!allowed())return;
   loaded=remove?null:{word:r.data.word,version:r.data.updated_at,custom:true};dirty=false;status.textContent=remove?'원장 등록 뜻을 지웠습니다. 검색에는 기본 사전이 적용됩니다.':'저장 완료 · 학생과 학부모가 다시 검색하면 반영됩니다.';api.onSaved(snapshot.word);
  }catch(e){status.textContent=e.code==='23505'?'다른 기기에서 먼저 등록했습니다. 작성한 뜻을 복사해 두고 다시 불러와 주세요.':(e.message||'저장되지 않았습니다. 작성한 내용은 유지됩니다.');}finally{busy=false;configure();}
 }
 loadButton.addEventListener('click',()=>void load());word.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();void load();}});pron.addEventListener('input',()=>{dirty=true;});
 add.addEventListener('click',()=>{if(senses.children.length<20){row();dirty=true;configure();}});form.addEventListener('submit',e=>{e.preventDefault();void persist();});restore.addEventListener('click',()=>void persist(true));
 configure();return {configure};
}
