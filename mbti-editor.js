/* Structured editing keeps all other types and subject groups intact. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,$=id=>doc.getElementById(id);let state=null,busy=false,dirty=false,bindings=[];
 function reset(){state=null;dirty=false;bindings=[];if($('mbtiEditDialog').open)$('mbtiEditDialog').close();$('mbtiEditFields').replaceChildren();$('mbtiEditStatus').textContent='';}
 function field(parent,label,path,value,body=false){
  const wrap=doc.createElement('label'),input=doc.createElement(body?'textarea':'input');wrap.textContent=label;
  if(body){input.rows=9;input.maxLength=30000;}else{input.type='text';input.maxLength=path[0]==='subtitle'?500:200;}
  input.value=value||'';input.name=path.join('.');input.required=path[0]!=='subtitle';wrap.append(input);parent.append(wrap);bindings.push({path,input});
 }
 function open(){
  if(busy||!api.canEdit())return;const current=api.current();if(!current?.guide)return;reset();
  state={...current,actor:api.profile(),guide:JSON.parse(JSON.stringify(current.guide))};
  const fields=$('mbtiEditFields'),group=api.groups[current.group];$('mbtiEditTitle').textContent=current.code+' · '+group.title+' 내용 수정';
  field(fields,'학습법 제목',['title'],current.guide.title);field(fields,'한 줄 소개',['subtitle'],current.guide.subtitle);
  const section=(item,path)=>{if(!item)return;field(fields,'항목 제목',[...path,'title'],item.title);field(fields,'본문',[...path,'body'],item.body,true);};
  if(group.sections){for(const [index,item]of(current.guide[group.sections]||[]).entries())section(item,[group.sections,index]);}
  else{section(current.guide.groupIntroductions?.[current.group],['groupIntroductions',current.group]);for(const[key,label]of group.subjects)field(fields,label+' 학습법',['subjects',key],current.guide.subjects?.[key],true);}
  $('mbtiEditSave').disabled=false;$('mbtiEditCancel').disabled=false;$('mbtiEditDialog').showModal();
 }
 async function close(){if(busy)return;if(dirty&&!await api.confirm('저장하지 않은 수정 내용이 있습니다. 변경을 버리고 닫으시겠습니까?'))return;reset();}
 $('mbtiEditForm').addEventListener('input',()=>{dirty=true;});
 $('mbtiEditCancel').addEventListener('click',close);
 $('mbtiEditDialog').addEventListener('cancel',event=>{event.preventDefault();void close();});
 $('mbtiEditDialog').addEventListener('close',()=>{if(state&&!busy)reset();});
 $('editMBTIStudy').addEventListener('click',open);
 $('mbtiEditForm').addEventListener('submit',async event=>{
  event.preventDefault();const editing=state;if(busy||!editing||editing.actor!==api.profile()||!api.canEdit()||!$('mbtiEditForm').reportValidity())return;
  const guide=JSON.parse(JSON.stringify(editing.guide));
  for(const{path,input}of bindings){let target=guide;for(const key of path.slice(0,-1))target=target[key];target[path.at(-1)]=input.value.trim();}
  busy=true;$('mbtiEditSave').disabled=true;$('mbtiEditCancel').disabled=true;$('mbtiEditStatus').textContent='학습법 저장 중…';
  try{
   const c=await api.client();if(editing!==state||editing.actor!==api.profile()||!api.canEdit())return;
   const r=await c.rpc('cheongla_save_mbti_guide',{selected_mbti:editing.code,guide_content:guide,expected_updated_at:editing.version||null});if(r.error)throw r.error;
   if(editing!==state||editing.actor!==api.profile()||!api.canEdit())return;
   api.saved(r.data);dirty=false;reset();
  }catch(e){if(editing===state&&editing.actor===api.profile())$('mbtiEditStatus').textContent=api.readable(e);}
  finally{busy=false;$('mbtiEditSave').disabled=false;$('mbtiEditCancel').disabled=false;}
 });
 return{open,reset};
}
root.CheonglaMBTIEditor={mount};
})(globalThis);
