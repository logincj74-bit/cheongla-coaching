/* Public reading, principal-only authoring. Attachments stay private until saved. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,$=id=>doc.getElementById(id),names={greeting:'원장 인사말',thoughts:'원장의 단상',photos:'사진에게 말을 걸다',objects:'사물로 읽는 사람'},routes={greeting:'greeting',director_thoughts:'thoughts',director_photos:'photos',director_objects:'objects'};
 const el=(tag,text)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;return n;},button=(text,fn)=>{const n=el('button',text);n.type='button';n.className='secondary';n.addEventListener('click',fn);return n;};
 const protectedCategories=new Set(['thoughts','photos','objects']);
 const copyright='저작권 보호 콘텐츠 · 무단 복제·저장·배포 금지';
 const deny=e=>{e.preventDefault();e.stopPropagation();};
 function shield(node){node.className+=' director-protected';for(const event of ['copy','cut','contextmenu','dragstart','selectstart'])node.addEventListener(event,deny);}
 function protectedView(){return protectedCategories.has(routes[currentKey])&&!$('publicContentPanel').hidden&&!dialog.open;}
 function protectedSelection(e){const target=e.target?.nodeType===3?e.target.parentElement:e.target;const selection=doc.getSelection?.();return !!target?.closest?.('.director-protected')||!!selection?.anchorNode?.parentElement?.closest?.('.director-protected')||!!selection?.focusNode?.parentElement?.closest?.('.director-protected');}
 for(const event of ['copy','cut'])doc.addEventListener?.(event,e=>{if(protectedView()&&protectedSelection(e))deny(e);},true);
 doc.addEventListener?.('keydown',e=>{if(!protectedView()||!(e.ctrlKey||e.metaKey)||e.altKey)return;const key=e.key.toLowerCase();if(['s','p'].includes(key)||(['c','x'].includes(key)&&protectedSelection(e)))deny(e);},true);
 const protectionStyle=el('style');protectionStyle.textContent='.director-protected{user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}.director-protected img{user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;-webkit-user-drag:none;pointer-events:none}.director-protected-photo{margin:18px 0;padding:0}.director-protected-photo figcaption,.director-copyright-note{font-size:12px;line-height:1.7;color:#526c62}.director-copyright-note{padding:12px 14px;border:1px solid #dce4d9;background:#f1f5ed;border-radius:10px}.director-protected-photo figcaption{text-align:center}.director-file-tool{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin:10px 0;padding:12px;border:1px solid #dce4d9;border-radius:10px}.director-file-tool span{overflow-wrap:anywhere}.director-protected-print-note{display:none}@media print{.director-file-tools{display:none!important}.director-protected{display:none!important}.director-protected-print-note{display:block!important}}';doc.head?.append(protectionStyle);
 let sequence=0,currentKey=null,editing=null,busy=false,dirty=false,trashView=false;
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
 async function trash(post,restore){
  if(busy||!api.principal())return;const actor=api.profile(),key=currentKey;
  if(!await api.confirm(restore?'이 글을 임시저장 상태로 복구할까요? 확인 후 공개로 저장해 주세요.':'이 글을 삭제해 휴지통으로 이동할까요? 글과 첨부파일이 열람 화면에서 함께 숨겨집니다.'))return;
  if(busy||actor!==api.profile()||!api.principal())return;busy=true;
  try{await rpc('cheongla_trash_director_post',{target_post:post.id,expected_updated_at:post.updated_at,restore_post:restore});if(actor!==api.profile())return;if(currentKey===key)await show(key,restore?false:trashView);$('siteStatus').textContent=restore?'글을 임시저장으로 복구했습니다. 확인 후 공개로 저장해 주세요.':'글을 휴지통으로 이동했습니다. 휴지통에서 복구할 수 있습니다.';void api.notifyReload();}
  catch(e){$('siteStatus').textContent=api.readable(e);}finally{busy=false;}
 }
 async function removePermanently(post,file=null){
  if(busy||!api.principal()||!protectedCategories.has(post.category))return;
  const actor=api.profile(),key=currentKey,inTrash=trashView,confirmation=file?'첨부파일 삭제':'글 영구삭제';
  const message=file?'「'+file.filename+'」을 삭제할까요?\n이 파일은 복구할 수 없습니다. 글과 다른 첨부파일은 유지됩니다.':'「'+post.title+'」을 영구삭제할까요?\n이 글과 모든 사진·첨부파일, 수정 이력이 삭제되며 복구할 수 없습니다.';
  if(!await api.confirm(message,confirmation))return;
  if(busy||actor!==api.profile()||!api.principal())return;busy=true;$('siteStatus').textContent='첨부파일과 삭제 상태를 확인하는 중…';
  let complete=false,error=null;
  try{
   const args={target_post:post.id,target_file:file?.id||null,expected_updated_at:post.updated_at,confirmation};
   const job=await rpc('cheongla_begin_director_removal',args);
   if(actor!==api.profile()||!api.principal())return;
   if(job.post_id!==post.id||job.file_id!==(file?.id||null)||!Array.isArray(job.paths)||job.paths.some(path=>typeof path!=='string'||!path.startsWith(post.id+'/')||path.includes('..')))throw Error('삭제할 파일 목록을 확인해 주세요.');
   const c=await api.client();
   for(let i=0;i<job.paths.length;i+=1000){
    if(actor!==api.profile()||!api.principal())return;
    const r=await c.storage.from('cheongla-director').remove(job.paths.slice(i,i+1000));if(r.error)throw r.error;
   }
   if(actor!==api.profile()||!api.principal())return;
   await rpc('cheongla_finish_director_removal',{...args,expected_updated_at:job.updated_at});complete=true;
  }catch(e){error=api.readable(e);}
  finally{
   try{if(actor===api.profile()){
    if(currentKey===key)await show(key,inTrash);
    $('siteStatus').textContent=complete?(file?'선택한 첨부파일을 삭제했습니다. 글과 다른 첨부파일은 유지됩니다.':'글과 첨부파일을 영구삭제했습니다.'):error?'삭제를 완료하지 못했습니다. 삭제 버튼을 다시 눌러 마쳐 주세요. '+error:'삭제가 중단되었습니다. 다시 로그인한 뒤 삭제를 마쳐 주세요.';
    if(complete)void api.notifyReload();
   }}finally{busy=false;}
  }
 }
 async function attachment(parent,file,request,protectedContent=false){
  const imageFile=/\.(jpg|jpeg|png|webp|gif)$/i.test(file.filename);
  if(protectedContent&&!imageFile){parent.append(el('p','원본 파일 제공 제한 · '+file.filename));return;}
  const c=await api.client();if(request!==sequence)return;
  if(/\.(jpg|jpeg|png|webp|gif)$/i.test(file.filename)){
   const r=await c.storage.from('cheongla-director').createSignedUrl(file.object_path,300);if(!r.error&&request===sequence){const img=el('img');img.src=r.data.signedUrl;img.alt=file.filename;img.loading='lazy';img.style.cssText='display:block;max-width:100%;max-height:70vh;object-fit:contain;margin:16px auto';if(protectedContent){img.draggable=false;img.setAttribute('draggable','false');const figure=el('figure');figure.className='director-protected-photo';figure.append(img,el('figcaption',copyright));parent.append(figure);}else parent.append(img);}
  }
  if(request!==sequence||protectedContent)return;
  parent.append(button('첨부파일 내려받기 · '+file.filename,async()=>{try{const r=await c.storage.from('cheongla-director').createSignedUrl(file.object_path,60,{download:file.filename});if(r.error)throw r.error;const url=new URL(r.data.signedUrl);if(url.protocol!=='https:')throw Error('파일 주소를 확인해 주세요.');root.location.assign(url.href);}catch(e){$('siteStatus').textContent=api.readable(e);}}));
 }
 const originalShow=root.showPublicPage,originalHome=root.showSiteHome;
 async function show(key,inTrash=false){
  const category=routes[key];if(!category)return originalShow(key);currentKey=key;trashView=!!(inTrash&&api.principal()&&protectedCategories.has(category));const request=++sequence;originalShow('greeting');const target=$('publicContentBody');target.replaceChildren();$('publicContentTitle').textContent=names[category]+(trashView?' · 휴지통':'');
  const controls=el('div'),list=el('div'),feedback=el('p','글을 불러오는 중…');feedback.setAttribute('role','status');target.append(controls,feedback);if(protectedCategories.has(category)){const note=el('p',copyright);note.className='director-copyright-note';const printNote=el('p','저작권 보호 콘텐츠는 인쇄·PDF 저장을 제공하지 않습니다.');printNote.className='director-protected-print-note';target.append(note,printNote);}target.append(list);
  try{const c=await api.client(),query=c.from('cheongla_director_posts').select('*').eq('category',category);const r=await(trashView?query.not('archived_at','is',null):query.is('archived_at',null)).order('updated_at',{ascending:false}).limit(100);if(r.error)throw r.error;if(request!==sequence||$('publicContentPanel').hidden)return;
   const posts=r.data||[];
   if(api.principal()&&!trashView)controls.append(button(category==='greeting'?'원장 인사말 수정':'새 글 작성',()=>edit(category,category==='greeting'?posts[0]:null)));
   if(api.principal()&&protectedCategories.has(category))controls.append(button(trashView?'← 글 목록':'휴지통',()=>show(key,!trashView)));
   feedback.textContent=posts.length?'':category==='greeting'?'':trashView?'휴지통이 비어 있습니다.':'아직 등록된 글이 없습니다.';
   const visible=posts.filter(p=>!!p.archived_at===trashView&&(p.state==='published'||api.principal()));
   if(category==='greeting'&&!visible.some(p=>p.body)){for(const paragraph of api.greeting().paragraphs)list.append(el('p',paragraph));}
   for(const post of visible){if(category==='greeting'&&!post.body)continue;const card=el('article');card.className='notice-form';const content=el('div');content.className='director-post-content';content.append(el('h3',post.title),el('small',new Date(post.updated_at).toLocaleDateString('ko-KR')+(post.state==='draft'?' · 임시저장':'')));const text=el('p',post.body);text.className='notice-body';content.append(text);if(protectedCategories.has(category))shield(content);card.append(content);if(api.principal()){if(!trashView)card.append(button('글 수정 · 첨부파일 추가',()=>edit(category,post)));if(protectedCategories.has(category)){if(!post.purge_requested_at)card.append(button(trashView?'글 복구':'글 삭제',()=>trash(post,trashView)));if(trashView){const purge=button(post.purge_requested_at?'영구삭제 계속':'글 영구삭제',()=>removePermanently(post));purge.className='danger';card.append(purge);}}}list.append(card);
    const f=await c.from('cheongla_director_files').select('id,filename,object_path,removal_requested_at').eq('post_id',post.id).eq('state','ready').order('created_at');if(request!==sequence)return;if(f.error){card.append(el('p','첨부파일을 불러오지 못했습니다. 다시 확인해 주세요.'));continue;}
    const fileTools=el('div');fileTools.className='director-file-tools';
    if(post.purge_requested_at){content.append(el('p','영구삭제 진행 중입니다. 영구삭제 계속 버튼으로 마쳐 주세요.'));continue;}
    for(const file of f.data||[]){
     if(file.removal_requested_at)content.append(el('p','첨부파일 삭제 진행 중 · '+file.filename));
     else await attachment(content,file,request,protectedCategories.has(category));
     if(request!==sequence)return;
     if(api.principal()&&!trashView&&protectedCategories.has(category)){
      const line=el('div');line.className='director-file-tool';const remove=button(file.removal_requested_at?'삭제 계속':'첨부 삭제',()=>removePermanently(post,file));remove.className='danger';remove.setAttribute('aria-label',file.filename+' '+(file.removal_requested_at?'삭제 계속':'첨부 삭제'));line.append(el('span',file.filename+' '),remove);fileTools.append(line);
     }
    }
    if(fileTools.children.length){card.append(el('p','첨부파일 관리 · 원장 전용'),fileTools);} 
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
