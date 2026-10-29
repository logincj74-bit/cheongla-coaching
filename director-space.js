/* Public reading, principal-only authoring. Attachments stay private until saved. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,$=id=>doc.getElementById(id),names={greeting:'원장 인사말',thoughts:'원장의 단상',photos:'사진에게 말을 걸다',objects:'사물로 읽는 사람'},routes={greeting:'greeting',director_thoughts:'thoughts',director_photos:'photos',director_objects:'objects'};
 const el=(tag,text)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;return n;},button=(text,fn)=>{const n=el('button',text);n.type='button';n.className='secondary';n.addEventListener('click',fn);return n;};
 let sequence=0,currentKey=null,editing=null,busy=false,dirty=false;
 const dialog=el('dialog');dialog.setAttribute('aria-label','원장 글 작성·수정');dialog.style.cssText='width:min(900px,96vw);max-height:92dvh;border:1px solid #cad9ce;border-radius:16px;padding:22px';
 const heading=el('h2'),form=el('form'),title=el('input'),body=el('textarea'),visibility=el('select'),files=el('input'),status=el('p'),save=el('button','저장하기'),cancel=button('취소 · 닫기',()=>void close());
 title.type='text';title.required=true;title.maxLength=200;body.rows=16;body.maxLength=50000;files.type='file';files.multiple=true;files.accept='.jpg,.jpeg,.png,.webp,.gif,.pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.hwp,.hwpx,.txt';
 for(const[value,label]of[['published','공개 · 저장하면 새 글 알림'],['draft','임시저장 · 원장만 보기']]){const op=el('option',label);op.value=value;visibility.append(op);}
 function label(text,input){const n=el('label',text);n.append(input);form.append(n);}
 label('제목',title);label('본문',body);label('공개 상태',visibility);label('사진·파일 첨부 (한 번에 최대 10개 · 파일당 20MB)',files);save.type='submit';status.setAttribute('role','status');form.append(status,save,cancel);dialog.append(heading,form);doc.body.append(dialog);
 async function rpc(name,args){const c=await api.client(),r=await c.rpc(name,args);if(r.error)throw r.error;return r.data;}
 function reset(){sequence++;editing=null;dirty=false;form.reset();if(dialog.open)dialog.close();status.textContent='';}
 async function close(){if(busy)return;if(dirty&&!await api.confirm('저장하지 않은 글이 있습니다. 닫으시겠습니까?'))return;reset();}
 root.addEventListener?.('beforeunload',e=>{if(dirty||busy){e.preventDefault();e.returnValue='';}});
 dialog.addEventListener('cancel',e=>{e.preventDefault();void close();});form.addEventListener('input',()=>{dirty=true;});
 async function edit(category,post=null){
  if(busy||!api.principal())return;const actor=api.profile();busy=true;
  try{const row=await rpc('cheongla_prepare_director_post',{target_post:post?.id||null,post_category:category});if(actor!==api.profile()||!api.principal())return;
   editing={...row,actor,fileIds:[],uploaded:new Set()};heading.textContent=names[category]+' · 글 작성·수정';title.value=row.title==='새 글'?'':row.title;body.value=row.body||'';
   if(category==='greeting'&&!row.body){title.value=api.greeting().title;body.value=api.greeting().paragraphs.join('\n\n');}
   visibility.value=post?row.state:'published';files.value='';status.textContent='공개로 저장하면 회원에게 새 글 알림이 등록됩니다.';dirty=false;dialog.showModal();
  }catch(e){$('siteStatus').textContent=api.readable(e);}finally{busy=false;save.disabled=false;cancel.disabled=false;}
 }
 form.addEventListener('submit',async e=>{
  e.preventDefault();const item=editing;if(busy||!item||item.actor!==api.profile()||!api.principal()||!form.reportValidity())return;
  const chosen=Array.from(files.files||[]);if(chosen.length>10||chosen.some(f=>!f.size||f.size>20971520||!/\.(jpg|jpeg|png|webp|gif|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|hwpx|txt)$/i.test(f.name))){status.textContent='첨부파일 종류와 크기를 확인해 주세요. 최대 10개, 파일당 20MB입니다.';return;}
  busy=true;save.disabled=cancel.disabled=true;status.textContent='글과 첨부파일을 저장하는 중…';
  try{const c=await api.client();if(item!==editing||item.actor!==api.profile()||!api.principal())return;
   for(const f of chosen){const key=f.name+':'+f.size+':'+f.lastModified;if(item.uploaded.has(key))continue;
    const ext=f.name.split('.').pop().toLowerCase(),path=item.id+'/'+root.crypto.randomUUID()+'.'+ext;
    const type=/^(image\/(jpeg|png|webp|gif)|application\/pdf|text\/plain)$/.test(f.type)?f.type:'application/octet-stream';
    const up=await c.storage.from('cheongla-director').upload(path,f,{contentType:type,upsert:false});if(up.error)throw up.error;
    if(item!==editing||item.actor!==api.profile()||!api.principal())return;
    const id=await rpc('cheongla_stage_director_file',{target_post:item.id,object_name:path,original_name:f.name,file_size:f.size});item.fileIds.push(id);item.uploaded.add(key);
   }
   const saved=await rpc('cheongla_save_director_post',{target_post:item.id,post_title:title.value.trim(),post_body:body.value,post_state:visibility.value,expected_updated_at:item.updated_at,file_ids:item.fileIds});
   if(item!==editing||item.actor!==api.profile())return;
   const key=currentKey;reset();busy=false;await show(key);$('siteStatus').textContent=saved.state==='published'?'글을 공개했습니다. 회원 알림함에 알림이 등록됩니다.':'임시저장했습니다. 원장만 볼 수 있습니다.';void api.notifyReload();
  }catch(error){if(item===editing&&item.actor===api.profile())status.textContent=api.readable(error);}
  finally{busy=false;save.disabled=cancel.disabled=false;}
 });
 async function attachment(parent,file,request){
  const c=await api.client();if(request!==sequence)return;
  if(/\.(jpg|jpeg|png|webp|gif)$/i.test(file.filename)){
   const r=await c.storage.from('cheongla-director').createSignedUrl(file.object_path,300);if(!r.error&&request===sequence){const img=el('img');img.src=r.data.signedUrl;img.alt=file.filename;img.loading='lazy';img.style.cssText='display:block;max-width:100%;max-height:70vh;object-fit:contain;margin:16px auto';parent.append(img);}
  }
  if(request!==sequence)return;
  parent.append(button('첨부파일 내려받기 · '+file.filename,async()=>{try{const r=await c.storage.from('cheongla-director').createSignedUrl(file.object_path,60,{download:file.filename});if(r.error)throw r.error;const url=new URL(r.data.signedUrl);if(url.protocol!=='https:')throw Error('파일 주소를 확인해 주세요.');root.location.assign(url.href);}catch(e){$('siteStatus').textContent=api.readable(e);}}));
 }
 const originalShow=root.showPublicPage,originalHome=root.showSiteHome;
 async function show(key){
  const category=routes[key];if(!category)return originalShow(key);currentKey=key;const request=++sequence;originalShow('greeting');const target=$('publicContentBody');target.replaceChildren();$('publicContentTitle').textContent=names[category];
  const controls=el('div'),list=el('div'),feedback=el('p','글을 불러오는 중…');feedback.setAttribute('role','status');target.append(controls,feedback,list);
  try{const c=await api.client(),r=await c.from('cheongla_director_posts').select('*').eq('category',category).is('archived_at',null).order('created_at',{ascending:false}).limit(100);if(r.error)throw r.error;if(request!==sequence||$('publicContentPanel').hidden)return;
   const posts=r.data||[];
   if(api.principal())controls.append(button(category==='greeting'?'원장 인사말 수정':'새 글 작성',()=>edit(category,category==='greeting'?posts[0]:null)));
   feedback.textContent=posts.length?'':category==='greeting'?'':'아직 등록된 글이 없습니다.';
   const visible=posts.filter(p=>p.state==='published'||api.principal());
   if(category==='greeting'&&!visible.some(p=>p.body)){for(const paragraph of api.greeting().paragraphs)list.append(el('p',paragraph));}
   for(const post of visible){if(category==='greeting'&&!post.body)continue;const card=el('article');card.className='notice-form';card.append(el('h3',post.title),el('small',new Date(post.updated_at).toLocaleDateString('ko-KR')+(post.state==='draft'?' · 임시저장':'')));const text=el('p',post.body);text.className='notice-body';card.append(text);if(api.principal())card.append(button('글 수정 · 첨부파일 추가',()=>edit(category,post)));list.append(card);
    const f=await c.from('cheongla_director_files').select('id,filename,object_path').eq('post_id',post.id).eq('state','ready').order('created_at');if(request!==sequence)return;if(f.error){card.append(el('p','첨부파일을 불러오지 못했습니다. 다시 확인해 주세요.'));continue;}
    for(const file of f.data||[])await attachment(card,file,request);
   }
  }catch(e){if(request===sequence){feedback.textContent=api.readable(e);if(category==='greeting'&&!list.children.length){feedback.textContent+=' 기본 인사말을 표시합니다.';for(const text of api.greeting().paragraphs)list.append(el('p',text));}}}
 }
 root.showPublicPage=key=>{if(routes[key])return show(key);sequence++;return originalShow(key);};
 root.showSiteHome=function(){sequence++;return originalHome();};
 const originalNavigate=root.navigateNotification;root.navigateNotification=async function(id){
  if(!api.profile())return originalNavigate(id);try{const c=await api.client(),r=await c.from('cheongla_notifications').select('source_kind,source_id').eq('id',id).maybeSingle();if(r.error)throw r.error;if(r.data?.source_kind!=='director_post')return originalNavigate(id);
   const p=await c.from('cheongla_director_posts').select('category').eq('id',r.data.source_id).maybeSingle();if(p.error)throw p.error;if(!p.data)throw Error('공개된 글을 찾을 수 없습니다.');await show(p.data.category==='greeting'?'greeting':'director_'+p.data.category);const read=await c.rpc('cheongla_read_notification',{target_notification:id});if(read.error)throw read.error;void api.notifyReload();
  }catch(e){$('siteStatus').textContent=api.readable(e);}
 };
 return{show,reset,edit};
}
root.CheonglaDirectorSpaceFactory={mount};
})(globalThis);
