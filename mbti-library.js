/* The revised type library is separate from introduction/group/parent articles. */
(function(root){'use strict';
const groups={NF:{name:'의미와 관계',types:['ENFJ','ENFP','INFJ','INFP']},NT:{name:'원리와 전략',types:['ENTJ','ENTP','INTJ','INTP']},SJ:{name:'책임과 체계',types:['ESTJ','ESFJ','ISTJ','ISFJ']},SP:{name:'경험과 실전',types:['ESTP','ESFP','ISTP','ISFP']}};
const labels=['유형·기질 이해','태도 방향성','강점·점검 행동','학습 능력·운영 설계','국어','수학','영어','과학탐구','사회탐구','학생 조언','학부모 조언','원장 상담 가이드'];
const css=`.mbti-library{--ml-green:#205b50;--ml-line:#dce5df;color:#233d42;min-width:0}.mbti-library *{box-sizing:border-box}.mbti-library button,.mbti-library select,.mbti-library input,.mbti-library textarea{font:inherit;max-width:100%}.mbti-library button{cursor:pointer;border:1px solid var(--ml-line);border-radius:12px;background:#f2f6f1;color:#28574d;padding:12px 14px;min-height:46px;line-height:1.45}.mbti-library button:disabled{opacity:.5;cursor:default}.mbti-library button[aria-pressed=true],.mbti-library .ml-primary{background:#205b50;color:#fff;border-color:#205b50}.mbti-library h2{font-size:clamp(24px,4vw,34px);line-height:1.4;margin:10px 0}.mbti-library h3{line-height:1.6}.mbti-library p{line-height:1.8}.mbti-library .ml-eyebrow{font-size:12px;color:#517468;font-weight:700;letter-spacing:.08em}.mbti-library .ml-muted{color:#62756b;font-size:14px}.mbti-library .ml-top,.mbti-library .ml-actions,.mbti-library .ml-types{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.mbti-library .ml-top{justify-content:space-between;margin-bottom:18px}.mbti-library .ml-badge{font-size:12px;border:1px solid #c7dccf;background:#edf5ee;border-radius:30px;padding:5px 10px;display:inline-block}.mbti-library .ml-groups{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:18px 0}.mbti-library .ml-group{text-align:left;display:grid;gap:5px;padding:17px}.mbti-library .ml-group strong{font-size:24px}.mbti-library .ml-group small{font-size:11px;line-height:1.8}.mbti-library .ml-reader{background:white;border:1px solid var(--ml-line);border-radius:20px;padding:clamp(16px,3vw,28px);margin-top:20px}.mbti-library .ml-types button{flex:1;min-width:80px}.mbti-library .ml-types button:first-child{flex:1.5}.mbti-library .ml-search{display:block;margin:20px 0}.mbti-library .ml-search input,.mbti-library .ml-editor input,.mbti-library .ml-editor textarea{width:100%;border:1px solid #bdcfc3;border-radius:10px;padding:12px;background:white;color:#233d42}.mbti-library .ml-sectionmenu{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin:10px 0 24px}.mbti-library .ml-sectionmenu button{text-align:left;display:flex;gap:8px;font-size:14px;padding:12px 10px;align-items:baseline}.mbti-library .ml-num{font-size:11px;opacity:.75}.mbti-library .ml-content{line-height:1.9;overflow-wrap:anywhere}.mbti-library .ml-content p{white-space:pre-wrap;margin:12px 0;line-height:1.9}.mbti-library .ml-content h4{font-size:17px;margin:24px 0 12px;line-height:1.6}.mbti-library .ml-table{overflow-x:auto;margin:16px 0;-webkit-overflow-scrolling:touch}.mbti-library table{border-collapse:collapse;width:100%;min-width:480px;font-size:14px}.mbti-library th,.mbti-library td{border:1px solid var(--ml-line);padding:10px;vertical-align:top;white-space:pre-wrap;line-height:1.8}.mbti-library th{background:#f0f5ed}.mbti-library .ml-guide{border-left:3px solid #8cad9a;padding:8px 14px;background:#f7faf5;margin:16px 0}.mbti-library .ml-editor label{display:block;margin:18px 0;font-weight:600}.mbti-library .ml-editor textarea{display:block;min-height:130px;margin-top:8px;font-weight:400;line-height:1.8}.mbti-library .ml-editor textarea[data-body]{min-height:440px}.mbti-library .ml-danger{color:#9a3e39;background:#fff8f5;border-color:#e9c9c1}.mbti-library .ml-trashitem{padding:18px 0;border-bottom:1px solid var(--ml-line)}.mbti-library .ml-status{white-space:pre-wrap;line-height:1.7;color:#356456}.mbti-library .ml-split{border-top:1px solid var(--ml-line);margin-top:28px;padding-top:20px}.mbti-library [hidden]{display:none!important}@media(max-width:700px){.mbti-library .ml-groups{grid-template-columns:repeat(2,minmax(0,1fr))}.mbti-library .ml-sectionmenu{grid-template-columns:repeat(2,minmax(0,1fr))}.mbti-library .ml-actions button{flex:1}.mbti-library .ml-reader{border-radius:14px}.mbti-library .ml-types button{min-width:70px}}
`;
function el(doc,tag,text,cls){const node=doc.createElement(tag);if(text!=null)node.textContent=text;if(cls)node.className=cls;return node;}
function markdown(parent,body,doc=parent.ownerDocument){
 const lines=String(body||'').split('\n');let pending=[];
 const flush=()=>{if(pending.length)parent.append(el(doc,'p',pending.join('\n')));pending=[];};
 const cells=line=>line.trim().replace(/^\|/,'').replace(/\|$/,'').split(/(?<!\\)\|/).map(s=>s.trim().replace(/\\\|/g,'|').replace(/<br>/g,'\n'));
 for(let i=0;i<lines.length;i++){
  const text=lines[i];
  if(text.startsWith('|')&&i+1<lines.length&&/^\|[\s:|\-]+\|$/.test(lines[i+1].trim())){
   flush();const wrap=el(doc,'div',null,'ml-table'),table=el(doc,'table'),head=el(doc,'thead'),row=el(doc,'tr');for(const text of cells(lines[i]))row.append(el(doc,'th',text));head.append(row);table.append(head);i+=2;const tbody=el(doc,'tbody');
   while(i<lines.length&&lines[i].trim().startsWith('|')){const tr=el(doc,'tr');for(const text of cells(lines[i]))tr.append(el(doc,'td',text));tbody.append(tr);i++;}i--;table.append(tbody);wrap.append(table);parent.append(wrap);
  }else if(/^### /.test(text)){flush();parent.append(el(doc,'h4',text.slice(4)));}
  else if(!text.trim())flush();else pending.push(text);
 }flush();
}
function mount(api){
 const collection=api.collection,initialCode=collection?.codes[0]||'NF';
 const doc=api.document,host=api.host||doc.getElementById('mbtiLibraryRoot');if(!host)return null;host.classList.add('mbti-library');
 if(!doc.getElementById('mbtiLibraryStyles')){const style=el(doc,'style',css);style.id='mbtiLibraryStyles';doc.head.append(style);}
 let rows=[],code=initialCode,section=1,editing=null,dirty=false,busy=false,loading=false,generation=0,actor=null,view='reader',message='',query='',myType='',initialized=false;
 const who=()=>api.profile(),allowed=()=>api.canUse(),editable=()=>allowed()&&api.canEdit(),find=c=>rows.find(row=>row.code===c),active=row=>!!row?.content&&!row.archived_at&&!row.purged_at;
 const live=(token,p)=>token===generation&&p===who()&&allowed();
 async function rpc(name,args){if(collection)name=name.replace('mbti_library','mbti_articles');if(api.rpc)return api.rpc(name,args);const db=await api.client(),r=await db.rpc(name,args);if(r.error)throw r.error;return r.data;}
 function reset(){generation++;rows=[];editing=null;dirty=false;busy=false;loading=false;actor=null;view='reader';message='';query='';myType='';initialized=false;code=initialCode;section=1;host.replaceChildren();root.CheonglaPrint?.clear();}
 async function leave(){if(busy){message='저장 중입니다. 잠시 후 이동해 주세요.';setStatus();return false;}if(dirty&&!(await api.confirm('저장하지 않은 MBTI 수정 내용이 있습니다. 버리고 이동할까요?')))return false;dirty=false;editing=null;return true;}
 function setStatus(){const status=host.querySelector('[data-ml-status]');if(status)status.textContent=message;}
 function button(text,fn,cls){const node=el(doc,'button',text,cls);node.type='button';node.disabled=busy||loading;node.addEventListener('click',()=>{const fail=error=>{message=api.readable(error);setStatus();};try{Promise.resolve(fn()).catch(fail);}catch(error){fail(error);}});return node;}
 async function open(){
  if(!allowed()){reset();return;}if(dirty&&!await leave())return;
  const token=++generation,p=who();actor=p;loading=true;message=(collection?.title||'기질·유형별 학습법')+'을 불러오는 중…';render();
  try{const [data,preference]=await Promise.all([rpc('cheongla_mbti_library_list'),!initialized&&api.preference?api.preference():Promise.resolve(myType)]);if(!live(token,p))return;rows=data||[];myType=preference||'';if(!initialized&&find(myType))code=myType;initialized=true;message='';}
  catch(error){if(live(token,p))message='새 학습법 자료를 불러오지 못했습니다. '+api.readable(error);}
  finally{if(live(token,p)){loading=false;render();}}
 }
 async function choose(nextCode,nextSection=1){if(!await leave())return;code=nextCode;section=nextSection;query='';view='reader';message='';render();}
 function trash(){return rows.flatMap(row=>!row.content||row.purged_at?[]:row.archived_at?[{row,id:null,title:(collection?row.content.title:row.code)+' · 문서 전체'}]:row.content.sections.filter(s=>s.archived_at&&!s.purged_at).map(s=>({row,id:s.id,title:(collection?row.content.title:row.code)+' · '+s.id+'. '+s.title})));}
 async function action(row,operation,id=null){
  if(!editable()||busy||!await leave())return;
  const target=id?'이 항목':'이 문서 전체';
  if(!(await api.confirm(operation==='purge'?target+'를 영구삭제할까요? 삭제된 본문은 복구할 수 없습니다.':operation==='restore'?target+'를 복원할까요?':target+'를 삭제하고 휴지통으로 옮길까요?')))return;
  const token=generation,p=who();if(!live(token,p)||!editable())return;busy=true;render();
  try{await rpc('cheongla_mbti_library_action',{target_code:row.code,operation,expected_revision:row.revision,section_id:id});if(!live(token,p))return;busy=false;await open();message=operation==='archive'?'휴지통으로 옮겼습니다.':operation==='restore'?'복원했습니다.':'영구삭제했습니다.';setStatus();}
  catch(error){if(live(token,p)){busy=false;message=api.readable(error);render();}}
 }
 async function emptyTrash(){
  if(!editable()||busy||!trash().length)return;const items=trash(),expected=[...new Map(items.map(item=>[item.row.code,{code:item.row.code,revision:item.row.revision}])).values()];
  if(!(await api.confirm('현재 휴지통의 '+items.length+'개 문서·항목을 모두 영구삭제할까요? 복구할 수 없습니다.')))return;
  const token=generation,p=who();if(!live(token,p)||!editable())return;busy=true;render();
  try{await rpc('cheongla_mbti_library_empty_trash',{expected_items:expected});if(!live(token,p))return;busy=false;await open();message='휴지통을 비웠습니다.';setStatus();}catch(error){if(live(token,p)){busy=false;message=api.readable(error);render();}}
 }
 function print(all){
  const row=find(code);if(!allowed()||!active(row)||dirty)return;const content=row.content;
  const sections=content.sections.filter(s=>!s.archived_at&&!s.purged_at&&(all||s.id===section));if(!sections.length)return;
  const title=collection?content.title+(all?'':' · '+sections[0].title):code+' · '+(content.kind==='temperament'?'기질 종합':'유형별')+' 학습법'+(all?'':' · '+section+'번 항목');
  if(!root.CheonglaPrint?.open)throw Error('인쇄 기능을 준비 중입니다. 잠시 후 다시 눌러 주세요.');
  root.CheonglaPrint.open(title,(body,out)=>{
   if(content.curriculum)body.append(el(out,'p',content.curriculum));if(all&&content.frontmatter)markdown(body,content.frontmatter,out);
   for(const item of sections){const block=el(out,'section');block.append(el(out,'h2',(collection?'':item.id+'. ')+item.title));markdown(block,item.body,out);body.append(block);}
  },'청라MBTI학습법_'+(collection?collection.labels[code]:code)+(collection?'_2026':'_2022')+(all?'':'_'+section));
 }
 function edit(row,item){if(!editable()||busy)return;editing={row:JSON.parse(JSON.stringify(row)),item:JSON.parse(JSON.stringify(item)),actor:who()};dirty=false;message='표는 | 기호로 칸을 구분합니다. 원본 본문을 수정한 뒤 저장을 눌러 주세요.';render();}
 function editor(parent){
  const state=editing,form=el(doc,'form',null,'ml-editor');form.addEventListener('submit',event=>event.preventDefault());form.addEventListener('input',()=>dirty=true);
  form.append(el(doc,'h3',(collection?state.row.content.title:code)+' · '+section+'번 항목 수정'));
  function field(label,value,area=false){const wrap=el(doc,'label',label),input=el(doc,area?'textarea':'input');input.value=value||'';if(!area)input.type='text';wrap.append(input);form.append(wrap);return input;}
  const title=field('문서 제목',state.row.content.title);title.maxLength=200;title.required=true;
  const front=field('자료 안내 · 사용 원칙',state.row.content.frontmatter,true);front.maxLength=10000;
  const heading=field('항목 제목',state.item.title);heading.maxLength=200;heading.required=true;
  const body=field('항목 본문',state.item.body,true);body.dataset.body='true';body.maxLength=60000;body.required=true;
  const actions=el(doc,'div',null,'ml-actions');
  actions.append(button('수정 내용 저장',async()=>{
   if(busy||!editable()||state!==editing||state.actor!==who()||!form.reportValidity())return;
   const token=generation,p=who();busy=true;for(const input of form.querySelectorAll('input,textarea,button'))input.disabled=true;
   try{const data=await rpc('cheongla_mbti_library_save',{target_code:code,section_id:section,document_title:title.value.trim(),document_frontmatter:front.value,section_title:heading.value.trim(),section_body:body.value.trim(),expected_revision:state.row.revision});if(!live(token,p)||state!==editing)return;rows=rows.map(row=>row.code===data.code?data:row);editing=null;dirty=false;message='수정 내용을 저장했습니다.';}
   catch(error){if(live(token,p)){message=api.readable(error);for(const input of form.querySelectorAll('input,textarea,button'))input.disabled=false;}}
   finally{if(live(token,p)){busy=false;if(!editing)render();else setStatus();}}
  },'ml-primary'),button('수정 취소',async()=>{if(await leave()){message='';render();}}));form.append(actions);parent.append(form);
 }
 function render(){
  host.replaceChildren();if(!allowed())return;
  const top=el(doc,'div',null,'ml-top'),head=el(doc,'div');head.append(el(doc,'div','CHEONGLA · MBTI LIBRARY','ml-eyebrow'),el(doc,'h2',collection?.title||'기질·유형별 학습법'),el(doc,'span',collection?'2026 수정 자료':'2022 개정 교육과정 · 2028학년도 수능','ml-badge'));
  const controls=el(doc,'div',null,'ml-actions');controls.append(button('다시 불러오기',open));if(editable())controls.append(button('휴지통 ('+trash().length+')',async()=>{if(await leave()){view=view==='trash'?'reader':'trash';render();}}));top.append(head,controls);host.append(top);
  const status=el(doc,'p',message,'ml-status');status.dataset.mlStatus='true';status.setAttribute('role','status');host.append(status);
  if(view==='trash'){
   const box=el(doc,'section',null,'ml-reader');box.append(el(doc,'h3',collection?'MBTI 안내 자료 휴지통':'기질·유형 자료 휴지통'),el(doc,'p','문서와 항목의 삭제 내용을 이곳에서 관리합니다. 영구삭제 후에는 복구되지 않습니다.','ml-muted'));
   const entries=trash();if(!entries.length)box.append(el(doc,'p','휴지통이 비어 있습니다.'));
   else{box.append(button('휴지통 비우기',emptyTrash,'ml-danger'));for(const item of entries){const card=el(doc,'article',null,'ml-trashitem'),actions=el(doc,'div',null,'ml-actions');card.append(el(doc,'strong',item.title));actions.append(button('복원',()=>action(item.row,'restore',item.id)),button('영구삭제',()=>action(item.row,'purge',item.id),'ml-danger'));card.append(actions);box.append(card);}}
   box.append(button('학습법으로 돌아가기',()=>{view='reader';render();}));host.append(box);return;
  }
  if(collection){
   host.append(el(doc,'p',collection.description,'ml-muted'));
   const docs=el(doc,'nav',null,'ml-sectionmenu');docs.setAttribute('aria-label',collection.title+' 문서 선택');
   for(const next of collection.codes){const row=find(next),b=button(collection.labels[next]+(row?.archived_at?' · 휴지통':row?.purged_at?' · 삭제됨':''),()=>choose(next));b.setAttribute('aria-pressed',String(code===next));b.dataset.document=next;docs.append(b);}host.append(docs);
  }else{
  host.append(el(doc,'p','먼저 기질의 공통점을 살펴보고, 같은 기질 안의 네 유형을 비교해 보세요. 유형을 고르면 언제든 기질 종합 안내로 돌아갈 수 있습니다.','ml-muted'));
  const group=groups[code]?code:find(code)?.content?.temperament||Object.keys(groups).find(key=>groups[key].types.includes(code))||'NF';
  const quick=el(doc,'div',null,'ml-top'),quickLabel=el(doc,'label','유형 바로 찾기 '),quickSelect=el(doc,'select');quickSelect.setAttribute('aria-label','유형 바로 찾기');
  const blank=el(doc,'option','16개 유형 중 선택');blank.value='';quickSelect.append(blank);
  for(const value of Object.values(groups))for(const type of value.types){const option=el(doc,'option',type);option.value=type;quickSelect.append(option);}quickSelect.value=groups[code]?'':code;
  quickSelect.addEventListener('change',()=>{if(quickSelect.value)void choose(quickSelect.value);});quickLabel.append(quickSelect);quick.append(quickLabel,el(doc,'span',myType?'내 MBTI: '+myType:'내 MBTI 미저장','ml-muted'));
  if(!groups[code]&&api.operations)quick.append(button('학생별 학습 처방',()=>api.operations(code)));
  if(!groups[code]&&api.savePreference)quick.append(button('이 유형을 내 MBTI로 저장',async()=>{if(!await leave())return;const token=generation,p=who(),chosen=code;busy=true;render();try{await api.savePreference(chosen);if(live(token,p)){myType=chosen;message='내 MBTI를 '+chosen+'로 저장했습니다.';}}catch(error){if(live(token,p))message=api.readable(error);}finally{if(live(token,p)){busy=false;render();}}}));host.append(quick);
  const cards=el(doc,'nav',null,'ml-groups');cards.setAttribute('aria-label','네 가지 기질 선택');
  for(const[key,value]of Object.entries(groups)){const b=button('',()=>choose(key));b.classList.add('ml-group');b.setAttribute('aria-pressed',String(group===key));b.append(el(doc,'strong',key),el(doc,'span',value.name),el(doc,'small',value.types.join(' · ')));cards.append(b);}host.append(cards);
  const types=el(doc,'nav',null,'ml-types');types.setAttribute('aria-label','기질 종합과 네 유형');for(const next of [group,...groups[group].types]){const row=find(next),b=button(next===group?group+' 기질 종합':next,()=>choose(next));b.setAttribute('aria-pressed',String(code===next));if(row?.purged_at)b.textContent+=' · 삭제됨';types.append(b);}host.append(types);
  }
  const row=find(code),reader=el(doc,'section',null,'ml-reader');host.append(reader);
  if(!active(row)){reader.append(el(doc,'h3',collection?collection.labels[code]:code+' 학습법'),el(doc,'p',loading?'자료를 불러오는 중입니다.':row?.archived_at?'이 문서는 휴지통에 있습니다. 복원 후 열람할 수 있습니다.':row?.purged_at?'영구삭제된 문서입니다.':'아직 등록된 자료가 없습니다.'));return;}
  const content=row.content,item=content.sections.find(s=>s.id===section);
  const count=content.sections.length;
  reader.append(el(doc,'div',(collection?'자료별 항목':groups[code]?'기질의 공통점과 유형 간 차이':(content.temperament||'')+' 기질 · '+code+' 유형')+' / '+count+'개 항목','ml-eyebrow'),el(doc,'h3',content.title));
  if(collection)reader.append(el(doc,'p','원문: '+content.source.filename,'ml-muted'));
  if(editing){editor(reader);return;}
  if(content.frontmatter){const intro=el(doc,'details',null,'ml-guide');intro.append(el(doc,'summary','자료 안내 · 사용 원칙'));const body=el(doc,'div',null,'ml-content');markdown(body,content.frontmatter,doc);intro.append(body);reader.append(intro);}
  const search=el(doc,'label','이 문서에서 찾기','ml-search'),input=el(doc,'input');input.type='search';input.placeholder=collection?'예: 학습, 대화, 자녀':'예: 대수, 통합과학, 학부모';input.value=query;search.append(input);reader.append(search);
  const menu=el(doc,'nav',null,'ml-sectionmenu');menu.setAttribute('aria-label',content.sections.length+'개 학습법 항목');
  function paintMenu(){menu.replaceChildren();for(const part of content.sections){if(query&&!(part.title+' '+part.body).toLowerCase().includes(query.toLowerCase()))continue;const removed=!!part.archived_at||!!part.purged_at,b=button('',()=>choose(code,part.id));b.dataset.section=part.id;b.append(el(doc,'span',String(part.id).padStart(2,'0'),'ml-num'),el(doc,'span',(collection?part.title:labels[part.id-1])+(removed?' · 삭제됨':'')));b.setAttribute('aria-pressed',String(part.id===section));menu.append(b);}if(!menu.children.length)menu.append(el(doc,'p','검색 결과가 없습니다.'));}
  input.addEventListener('input',()=>{query=input.value;paintMenu();});paintMenu();reader.append(menu);
  if(!item||item.archived_at||item.purged_at){reader.append(el(doc,'p','이 항목은 삭제되어 표시하지 않습니다. 휴지통에 있다면 복원할 수 있습니다.'));return;}
  const article=el(doc,'article',null,'ml-content');article.dataset.sectionBody=String(section);article.append(el(doc,'h3',(collection?'':item.id+'. ')+item.title));markdown(article,item.body,doc);reader.append(article);
  const actions=el(doc,'div',null,'ml-actions ml-split');actions.append(button('이 항목 인쇄 / PDF',()=>print(false)),button('문서 전체 인쇄 / PDF',()=>print(true)));
  if(editable())actions.append(button('이 항목 수정',()=>edit(row,item)),button('이 항목 삭제 · 휴지통',()=>action(row,'archive',item.id),'ml-danger'));
  reader.insertBefore(actions,search);
  const navigation=el(doc,'div',null,'ml-actions ml-split');if(section>1)navigation.append(button('← 이전 항목',()=>choose(code,section-1)));if(section<content.sections.length)navigation.append(button('다음 항목 →',()=>choose(code,section+1)));reader.append(navigation);
  if(editable()){const manage=el(doc,'details',null,'ml-split');manage.append(el(doc,'summary','문서 전체 관리'),el(doc,'p','현재 문서 전체를 휴지통으로 이동합니다.','ml-muted'),button('이 문서 전체 삭제 · 휴지통',()=>action(row,'archive'),'ml-danger'));reader.append(manage);}
 }
 const navigationSelector='#siteNavigation button,#academyHome,#siteGoHome,#siteBack,#backToHome,#openMemberArea,#openNotificationInbox';
 doc.addEventListener('click',event=>{const target=event.target.closest?.(navigationSelector);if(!target||!dirty)return;event.preventDefault();event.stopImmediatePropagation();void leave().then(ok=>{if(ok)target.click();});},true);
 root.addEventListener?.('beforeunload',event=>{if(dirty){event.preventDefault();event.returnValue='';}});
 return {open,reset,leave,get dirty(){return dirty;},get code(){return code;},references(target){return active(find(target))?find(target).content.sections.filter(s=>[4,12].includes(s.id)&&!s.archived_at&&!s.purged_at).map(s=>({title:s.title,body:s.body})):[];}};
}
root.CheonglaMBTILibrary={mount,markdown,groups,labels};
})(globalThis);
