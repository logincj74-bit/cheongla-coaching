/* Public reading, principal-only authoring. Attachments stay private until saved. */
(function(root){'use strict';
function mount(api){
 const doc=api.document,$=id=>doc.getElementById(id),names={greeting:'원장 인사말',thoughts:'이청지단상(以聽之斷想)',photos:'사진에게 말을 걸다',objects:'사물로 읽는 사람',column:'칼럼'},routes={greeting:'greeting',director_thoughts:'thoughts',director_photos:'photos',director_objects:'objects',director_column:'column'};
 const el=(tag,text)=>{const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;return n;},button=(text,fn)=>{const n=el('button',text);n.type='button';n.className='secondary';n.addEventListener('click',fn);return n;};
 const protectedCategories=new Set(['thoughts','photos','objects','column']);
 const hasImageExtension=name=>/\.(jpg|jpeg|png|webp|gif)$/i.test(name);
 const fileKey=file=>[file.name,file.size,file.lastModified].join(':');
 function normalizePostBody(value){
  // Pasted text can use both a Unicode line separator and an LF for one break.
  return value.replace(/\r\n?/g,'\n').replace(/[\n\u2028]+/g,breaks=>{
   const lineFeeds=breaks.replace(/\u2028/g,'').length;
   return '\n'.repeat(Math.max(lineFeeds,breaks.length-lineFeeds));
  }).replace(/\u2029/g,'\n\n');
 }

 const copyright='저작권 보호 콘텐츠 · 무단 복제·저장·배포 금지';
 const deny=e=>{e.preventDefault();e.stopPropagation();};
 function shield(node){node.className+=' director-protected';for(const event of ['copy','cut','contextmenu','dragstart','selectstart'])node.addEventListener(event,deny);}
 function protectedView(){return protectedCategories.has(routes[currentKey])&&!$('publicContentPanel').hidden&&!dialog.open;}
 function protectedSelection(e){const target=e.target?.nodeType===3?e.target.parentElement:e.target;const selection=doc.getSelection?.();return !!target?.closest?.('.director-protected')||!!selection?.anchorNode?.parentElement?.closest?.('.director-protected')||!!selection?.focusNode?.parentElement?.closest?.('.director-protected');}
 for(const event of ['copy','cut'])doc.addEventListener?.(event,e=>{if(protectedView()&&protectedSelection(e))deny(e);},true);
 doc.addEventListener?.('keydown',e=>{if(!protectedView()||!(e.ctrlKey||e.metaKey)||e.altKey)return;const key=e.key.toLowerCase();if(['s','p'].includes(key)||(['c','x'].includes(key)&&protectedSelection(e)))deny(e);},true);
 const accordionStyle=el('style');accordionStyle.textContent='.director-post-accordion{padding:0!important;overflow:hidden}.director-post-heading{cursor:pointer;padding:14px 16px;display:flex;flex-direction:column;gap:5px;line-height:1.5}.director-post-heading strong{font-size:1rem;overflow-wrap:anywhere}.director-post-heading small{font-size:.78rem;opacity:.75}.director-post-accordion>.director-post-content{padding:0 16px 12px}.director-post-accordion:not([open])>.director-post-content{display:none}.director-post-accordion>button,.director-post-accordion>.director-file-tools{margin:8px 12px 12px}.director-post-heading:focus-visible{outline:2px solid currentColor;outline-offset:-3px}';accordionStyle.textContent+=`
 .director-post-heading:has(.director-post-thumbnail){display:grid;grid-template-columns:minmax(0,1fr) 64px;column-gap:12px}
 .director-post-heading:has(.director-post-thumbnail)>strong,.director-post-heading:has(.director-post-thumbnail)>small{grid-column:1}
 .director-post-thumbnail{grid-column:2;grid-row:1/3;align-self:center;width:64px;height:52px;margin:0;overflow:hidden;border-radius:6px}
 .director-post-thumbnail>img{display:block;width:100%;height:100%;object-fit:cover}
 .public-content .director-post-content>.notice-body,.director-reader-preview .notice-body{font-size:1rem;font-weight:400;line-height:1.7;color:inherit;white-space:pre-wrap;word-break:keep-all;overflow-wrap:anywhere}
 .director-reader-preview{width:min(100%,40rem);margin:14px auto;padding:14px 16px;border:1px solid #dce4d9;border-radius:12px}
 .director-reader-preview>strong{display:block;overflow-wrap:anywhere}
 .director-reader-preview [role=status]:empty{display:none}
 .director-post-editor-body{font-size:1rem;line-height:1.7}
 .director-photo-caption{display:block;white-space:pre-wrap;overflow-wrap:anywhere;font-size:.95rem;margin:0 0 6px}
 .director-caption-fields{min-width:0;margin:10px 0;padding:12px;border:1px solid #dce4d9}
 .director-caption-fields label{display:block;overflow-wrap:anywhere}
 `;doc.head.append(accordionStyle);const protectionStyle=el('style');protectionStyle.textContent='.director-protected{user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}.director-protected img{user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;-webkit-user-drag:none;pointer-events:none}.director-protected-photo{margin:18px 0;padding:0}.director-protected-photo figcaption,.director-copyright-note{font-size:12px;line-height:1.7;color:#526c62}.director-copyright-note{padding:12px 14px;border:1px solid #dce4d9;background:#f1f5ed;border-radius:10px}.director-protected-photo figcaption{text-align:center}.director-file-tool{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin:10px 0;padding:12px;border:1px solid #dce4d9;border-radius:10px}.director-file-tool span{overflow-wrap:anywhere}.director-protected-print-note{display:none}@media print{.director-file-tools{display:none!important}.director-protected{display:none!important}.director-protected-print-note{display:block!important}}';doc.head?.append(protectionStyle);
 let sequence=0,currentKey=null,editing=null,busy=false,dirty=false,trashView=false;
 const dialog=el('dialog');dialog.setAttribute('aria-label','원장 글 작성·수정');dialog.style.cssText='width:min(900px,96vw);max-height:92dvh;border:1px solid #cad9ce;border-radius:16px;padding:22px';
 const heading=el('h2'),form=el('form'),title=el('input'),body=el('textarea'),visibility=el('select'),files=el('input'),status=el('p'),save=el('button','저장하기'),cancel=button('취소 · 닫기',()=>void close());
 title.type='text';title.required=true;title.maxLength=200;body.className='director-post-editor-body';body.rows=16;body.maxLength=50000;files.type='file';files.multiple=true;files.accept='.jpg,.jpeg,.png,.webp,.gif,.pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.hwp,.hwpx,.txt';
 for(const[value,label]of[['published','공개 · 저장하면 새 글 알림'],['draft','임시저장 · 원장만 보기']]){const op=el('option',label);op.value=value;visibility.append(op);}
 function label(text,input){const n=el('label',text);n.append(input);form.append(n);}
 label('제목',title);label('본문',body);label('공개 상태',visibility);label('사진·파일 첨부 (한 번에 최대 10개 · 파일당 20MB)',files);save.type='submit';status.setAttribute('role','status');form.append(status,save,cancel);dialog.append(heading,form);doc.body.append(dialog);
 const preview=el('section'),previewTitle=el('strong'),previewPhotos=el('div'),previewBody=postText(''),previewStatus=el('p');
 const previewButton=button('독자 화면 미리보기',togglePreview);
 const previewUrls=[];
 let previewRequest=0;
 preview.id='directorReaderPreview';preview.className='director-reader-preview';preview.hidden=true;
 preview.setAttribute('aria-label','독자 화면 미리보기');
 previewStatus.setAttribute('role','status');
 preview.append(previewTitle,previewPhotos,previewBody,previewStatus);
 previewButton.setAttribute('aria-controls',preview.id);previewButton.setAttribute('aria-expanded','false');
 form.insertBefore(previewButton,status);form.insertBefore(preview,status);
 const captionFields=el('fieldset'),existingCaptions=el('div'),newCaptions=el('div');
 captionFields.className='director-caption-fields';captionFields.hidden=true;
 captionFields.append(el('legend','사진 설명 · 선택 (160자까지)'),existingCaptions,newCaptions);
 form.insertBefore(captionFields,previewButton);

 function postText(value){
  const text=el('p',normalizePostBody(value||''));
  text.className='notice-body';
  return text;
 }

 function clearPreview(){
  previewRequest++;
  for(const url of previewUrls.splice(0))root.URL.revokeObjectURL(url);
  previewPhotos.replaceChildren();previewTitle.textContent=previewBody.textContent=previewStatus.textContent='';
  preview.hidden=true;previewButton.textContent='독자 화면 미리보기';previewButton.setAttribute('aria-expanded','false');
 }

 async function togglePreview(){
  if(!preview.hidden){clearPreview();return;}
  const item=editing;
  if(busy||!item||item.actor!==api.profile()||!api.principal())return;
  const request=++previewRequest;
  const active=()=>request===previewRequest&&item===editing&&item.actor===api.profile()&&api.principal();
  preview.hidden=false;previewButton.textContent='미리보기 닫기';previewButton.setAttribute('aria-expanded','true');
  previewTitle.textContent=title.value.trim()||'제목 없음';
  previewBody.textContent=normalizePostBody(body.value);
  if(!protectedCategories.has(item.category))return;
  previewStatus.textContent='사진 미리보기를 준비하는 중…';
  let unavailable=false;
  try{
   const c=await api.client();
   if(!active())return;
   const saved=await c.from('cheongla_director_files').select('id,filename,object_path,caption,removal_requested_at')
    .eq('post_id',item.id).eq('state','ready').order('created_at');
   if(!active())return;
   if(saved.error)throw saved.error;
   const existing=(saved.data||[]).filter(file=>!file.removal_requested_at&&hasImageExtension(file.filename));
   const storage=c.storage.from('cheongla-director');
   const links=await Promise.allSettled(existing.map(file=>storage.createSignedUrl(file.object_path,300)));
   if(!active())return;
   for(const [index,file] of existing.entries()){
    const link=links[index];
    if(link.status!=='fulfilled'||link.value.error){unavailable=true;continue;}
    const caption=(item.oldCaptions.get(file.id)?.input.value??file.caption??'').trim();
    previewPhotos.append(photoFigure(postImage(link.value.data.signedUrl,file.filename,caption),caption));
   }
  }catch{
   unavailable=true;
  }
  if(!active())return;
  const chosen=new Map([...item.pendingPhotos].map(([key,entry])=>[key,entry.file]));
  for(const file of Array.from(files.files||[]).slice(0,10)){
   if(hasImageExtension(file.name)&&file.size>0&&file.size<=20971520)chosen.set(fileKey(file),file);
  }
  for(const [key,file] of chosen){
   try{
    const url=root.URL.createObjectURL(file),caption=item.newCaptions.get(key)?.value.trim()||'';
    previewUrls.push(url);
    previewPhotos.append(photoFigure(postImage(url,file.name,caption),caption));
   }catch{unavailable=true;}
  }
  previewStatus.textContent=unavailable?'일부 사진을 미리 불러오지 못했습니다.':'';
 }

 // Text updates in place. Close previews when attachments change so they are rebuilt.
 form.addEventListener('input',event=>{
  dirty=true;
  if(preview.hidden)return;
  if(event.target===title)previewTitle.textContent=title.value.trim()||'제목 없음';
  else if(event.target===body)previewBody.textContent=normalizePostBody(body.value);
  else if(captionFields.contains(event.target))clearPreview();
 });

 function appendCaptionField(parent,filename,value=''){
  const label=el('label',filename),input=el('input');
  input.type='text';input.maxLength=160;input.value=value;
  label.append(input);parent.append(label);
  return input;
 }

 files.addEventListener('change',()=>{
  clearPreview();
  if(editing?.category!=='photos')return;
  newCaptions.replaceChildren();
  for(const [key,file] of editing.pendingPhotos){
   const value=editing.newCaptions.get(key)?.value;
   editing.newCaptions.set(key,appendCaptionField(newCaptions,file.name,value));
  }
  for(const file of Array.from(files.files||[]).slice(0,10)){
   const key=fileKey(file);
   if(!hasImageExtension(file.name)||editing.pendingPhotos.has(key))continue;
   const value=editing.newCaptions.get(key)?.value;
   editing.newCaptions.set(key,appendCaptionField(newCaptions,file.name,value));
  }
  captionFields.hidden=!existingCaptions.children.length&&!newCaptions.children.length;
 });

 async function rpc(name,args){const c=await api.client(),r=await c.rpc(name,args);if(r.error)throw r.error;return r.data;}
 function reset(){sequence++;clearPreview();editing=null;dirty=false;form.reset();existingCaptions.replaceChildren();newCaptions.replaceChildren();captionFields.hidden=true;if(dialog.open)dialog.close();status.textContent='';}
 async function close(){if(busy)return;if(dirty&&!await api.confirm('저장하지 않은 글이 있습니다. 닫으시겠습니까?'))return;reset();}
 root.addEventListener?.('beforeunload',e=>{if(dirty||busy){e.preventDefault();e.returnValue='';}});
 dialog.addEventListener('cancel',e=>{e.preventDefault();void close();});
 async function edit(category,post=null){
  if(busy||!api.principal())return;const actor=api.profile();busy=true;
  try{const row=await rpc('cheongla_prepare_director_post',{target_post:post?.id||null,post_category:category});if(actor!==api.profile()||!api.principal())return;
   const item={...row,actor,fileIds:[],uploaded:new Set(),oldCaptions:new Map(),newCaptions:new Map(),pendingPhotos:new Map()};
   existingCaptions.replaceChildren();newCaptions.replaceChildren();captionFields.hidden=true;
   if(category==='photos'&&post){
    const c=await api.client(),result=await c.from('cheongla_director_files')
     .select('id,filename,caption,removal_requested_at').eq('post_id',row.id).eq('state','ready').order('created_at');
    if(result.error)throw result.error;
    if(actor!==api.profile()||!api.principal())return;
    for(const file of result.data||[]){
     if(file.removal_requested_at||!hasImageExtension(file.filename))continue;
     const input=appendCaptionField(existingCaptions,file.filename,file.caption||'');
     item.oldCaptions.set(file.id,{input,original:input.value});
    }
    captionFields.hidden=!existingCaptions.children.length;
   }
   editing=item;heading.textContent=names[category]+' · 글 작성·수정';title.value=row.title==='새 글'?'':row.title;body.value=normalizePostBody(row.body||'');
   if(category==='greeting'&&!row.body){title.value=api.greeting().title;body.value=api.greeting().paragraphs.join('\n\n');}
   visibility.value=post?row.state:'published';files.value='';status.textContent='공개로 저장하면 회원에게 새 글 알림이 등록됩니다.';dirty=false;dialog.showModal();
  }catch(e){$('siteStatus').textContent=api.readable(e);}finally{busy=false;save.disabled=false;cancel.disabled=false;}
 }
 form.addEventListener('submit',async e=>{
  e.preventDefault();const item=editing;if(busy||!item||item.actor!==api.profile()||!api.principal()||!form.reportValidity())return;
  const chosen=Array.from(files.files||[]);if(chosen.length>10||chosen.some(f=>!f.size||f.size>20971520||!/\.(jpg|jpeg|png|webp|gif|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|hwpx|txt)$/i.test(f.name))){status.textContent='첨부파일 종류와 크기를 확인해 주세요. 최대 10개, 파일당 20MB입니다.';return;}
  busy=true;save.disabled=cancel.disabled=true;status.textContent='글과 첨부파일을 저장하는 중…';
  try{const c=await api.client();if(item!==editing||item.actor!==api.profile()||!api.principal())return;
   for(const f of chosen){const key=fileKey(f);if(item.uploaded.has(key))continue;
    const ext=f.name.split('.').pop().toLowerCase(),path=item.id+'/'+root.crypto.randomUUID()+'.'+ext;
    const type=/^(image\/(jpeg|png|webp|gif)|application\/pdf|text\/plain)$/.test(f.type)?f.type:'application/octet-stream';
    const up=await c.storage.from('cheongla-director').upload(path,f,{contentType:type,upsert:false});if(up.error)throw up.error;
    if(item!==editing||item.actor!==api.profile()||!api.principal())return;
    const id=await rpc('cheongla_stage_director_file',{target_post:item.id,object_name:path,original_name:f.name,file_size:f.size});item.fileIds.push(id);item.uploaded.add(key);
    if(hasImageExtension(f.name))item.pendingPhotos.set(key,{id,name:f.name,file:f});
   }
   const args={target_post:item.id,post_title:title.value.trim(),post_body:normalizePostBody(body.value),post_state:visibility.value,expected_updated_at:item.updated_at,file_ids:item.fileIds};
   let saveFunction='cheongla_save_director_post';
   if(item.category==='photos'){
    const captions={};
    for(const [id,{input,original}] of item.oldCaptions){
     if(input.value!==original)captions[id]=input.value.trim();
    }
    for(const [key,{id}] of item.pendingPhotos){
     captions[id]=item.newCaptions.get(key)?.value.trim()||'';
    }
    args.photo_captions=captions;
    saveFunction='cheongla_save_director_photo_post';
   }
   const saved=await rpc(saveFunction,args);
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
 async function removePermanently(post,file=null,confirmed=false){
  if(busy||!api.principal()||!protectedCategories.has(post.category))return;
  const actor=api.profile(),key=currentKey,inTrash=trashView,confirmation=file?'첨부파일 삭제':'글 영구삭제';
  const message=file?'「'+file.filename+'」을 삭제할까요?\n이 파일은 복구할 수 없습니다. 글과 다른 첨부파일은 유지됩니다.':'「'+post.title+'」을 영구삭제할까요?\n이 글과 모든 사진·첨부파일, 수정 이력이 삭제되며 복구할 수 없습니다.';
  if(!confirmed&&!await api.confirm(message,confirmation))return;
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
  return complete;
 }
 const isImageAttachment=file=>hasImageExtension(file.filename);
 function postImage(url,filename,caption){
  const img=el('img');
  img.src=url;img.alt=caption?'':filename;img.loading='lazy';img.decoding='async';
  img.style.cssText='display:block;max-width:100%;max-height:70vh;object-fit:contain;margin:16px auto';
  return img;
 }
 function photoFigure(img,description){
  img.draggable=false;img.setAttribute('draggable','false');
  const figure=el('figure'),caption=el('figcaption');
  figure.className='director-protected-photo';
  if(description){
   const text=el('span',description);
   text.className='director-photo-caption';caption.append(text);
  }
  caption.append(el('span',copyright));figure.append(img,caption);
  return figure;
 }
 async function attachment(parent,file,request,protectedContent,previewHeading){
  const imageFile=isImageAttachment(file);
  if(protectedContent&&!imageFile){parent.append(el('p','원본 파일 제공 제한 · '+file.filename));return;}
  const c=await api.client();if(request!==sequence)return;
  if(imageFile){
   const r=await c.storage.from('cheongla-director').createSignedUrl(file.object_path,300);
   if(!r.error&&request===sequence){
    const url=r.data.signedUrl,img=postImage(url,file.filename,file.caption);
    if(protectedContent){
     parent.append(photoFigure(img,file.caption));
     if(previewHeading&&!previewHeading.querySelector('.director-post-thumbnail')){
      const thumbnail=el('span'),preview=el('img');
      thumbnail.className='director-post-thumbnail';shield(thumbnail);
      preview.alt='';preview.loading='lazy';preview.decoding='async';preview.draggable=false;
      preview.width=64;preview.height=52;
      preview.addEventListener('error',()=>thumbnail.remove(),{once:true});
      preview.src=url;thumbnail.append(preview);previewHeading.append(thumbnail);
     }
    }else parent.append(img);
   }
  }
  if(request!==sequence||protectedContent)return;
  parent.append(button('첨부파일 내려받기 · '+file.filename,async()=>{try{await root.CheonglaDocumentBrand.downloadAttachment(c.storage.from('cheongla-director'),file);}catch(e){$('siteStatus').textContent=api.readable(e);}}));
 }
 const originalShow=root.showPublicPage,originalHome=root.showSiteHome;
 const articleCards=new Map();
 let openArticle='',displayedList=null;
 const tracksArticles=key=>protectedCategories.has(routes[key]);

 function displayArticle(id=''){
  const previous=articleCards.get(openArticle);
  if(previous)previous.open=false;
  openArticle=id;
  const next=articleCards.get(id);
  if(next)next.open=true;
 }

 function closeArticle(key,id){
  const entry=root.history?.state?.cheonglaView;
  if(entry?.view==='public'&&entry.key===key&&entry.detail===id){root.history.back();return;}
  displayArticle();
 }

 async function restoreView(key,detail=''){
  if(currentKey===key&&!trashView&&!$('publicContentPanel').hidden&&displayedList?.parentNode===$('publicContentBody')){
   displayArticle(detail);
   return;
  }
  await show(key,false,detail);
 }

 async function show(key,inTrash=false,detail=''){
  const category=routes[key];if(!category)return originalShow(key);currentKey=key;trashView=!!(inTrash&&api.principal()&&protectedCategories.has(category));const request=++sequence;articleCards.clear();openArticle=detail;originalShow('greeting',tracksArticles(key)?key:'greeting');const target=$('publicContentBody');target.replaceChildren();$('publicContentTitle').textContent=names[category]+(trashView?' · 휴지통':'');
  const controls=el('div'),list=el('div'),feedback=el('p','글을 불러오는 중…');feedback.setAttribute('role','status');target.append(controls,feedback);if(protectedCategories.has(category)){const note=el('p',copyright);note.className='director-copyright-note';const printNote=el('p','저작권 보호 콘텐츠는 인쇄·PDF 저장을 제공하지 않습니다.');printNote.className='director-protected-print-note';target.append(note,printNote);}target.append(list);displayedList=list;
  try{const c=await api.client(),query=c.from('cheongla_director_posts').select('*').eq('category',category);const r=await(trashView?query.not('archived_at','is',null):query.is('archived_at',null)).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(100);if(r.error)throw r.error;if(request!==sequence||$('publicContentPanel').hidden)return;
   const posts=(r.data||[]).slice().sort((a,b)=>new Date(b.created_at||0)-new Date(a.created_at||0)||String(b.id).localeCompare(String(a.id)));
   if(api.principal()&&!trashView)controls.append(button(category==='greeting'?'원장 인사말 수정':'새 글 작성',()=>edit(category,category==='greeting'?posts[0]:null)));
   if(api.principal()&&protectedCategories.has(category))controls.append(button(trashView?'← 글 목록':'휴지통',()=>show(key,!trashView)));
   feedback.textContent=posts.length?'':category==='greeting'?'':trashView?'휴지통이 비어 있습니다.':'아직 등록된 글이 없습니다.';
   if(trashView&&posts.length)controls.append(button('현재 목록 휴지통 비우기',async()=>{if(busy||!api.principal()||!await api.confirm('현재 휴지통 목록 '+posts.length+'건과 첨부파일을 영구삭제할까요? 복구할 수 없습니다.','글 영구삭제'))return;const actor=api.profile();let count=0;for(const post of posts){if(actor!==api.profile()||!await removePermanently(post,null,true))break;count++;}$('siteStatus').textContent=count+'건 영구삭제 완료'+(count<posts.length?' · 나머지는 휴지통에서 확인해 주세요.':'.');}));
   const visible=posts.filter(p=>!!p.archived_at===trashView&&(p.state==='published'||api.principal()));
   if(category==='greeting'&&!visible.some(p=>p.body)){for(const paragraph of api.greeting().paragraphs)list.append(el('p',paragraph));}
   for(const post of visible){if(category==='greeting'&&!post.body)continue;const card=el('details');card.className='notice-form director-post-accordion';const heading=el('summary');heading.className='director-post-heading';const content=el('div');content.className='director-post-content';const formatPostTime=value=>value?new Date(value).toLocaleString('ko-KR',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}):'기록 없음';const created=post.created_at,updated=post.updated_at;const changed=created&&updated&&Math.abs(new Date(updated)-new Date(created))>=60000;const timestamp=el('small','작성 '+formatPostTime(created)+(changed?' · 수정 '+formatPostTime(updated):'')+(post.state==='draft'?' · 임시저장':''));heading.append(el('strong',post.title),timestamp);card.append(heading);
    const protectedContent=protectedCategories.has(category);
    const trackArticle=protectedContent&&!trashView;
    if(trackArticle){
     card.className+=' director-post-history';
     articleCards.set(post.id,card);
     card.open=openArticle===post.id;
     heading.addEventListener('click',event=>{
      event.preventDefault();
      if(card.open){closeArticle(key,post.id);return;}
      root.recordSiteView('public',key,post.id);
      displayArticle(post.id);
      root.CheonglaDetailNavigation?.align(heading);
     });
    }
    const photos=protectedContent?el('div'):null;
    if(photos){photos.className='director-post-photos';content.append(photos);shield(content);}
    content.append(postText(post.body));card.append(content);content.addEventListener('click',event=>{if(event.target.closest('a,button,input,textarea,select,video,audio,iframe,[contenteditable]'))return;if(trackArticle)closeArticle(key,post.id);else card.open=false;});if(api.principal()){if(!trashView)card.append(button('글 수정 · 첨부파일 추가',()=>edit(category,post)));if(protectedCategories.has(category)){if(!post.purge_requested_at)card.append(button(trashView?'글 복구':'글 삭제',()=>trash(post,trashView)));if(trashView){const purge=button(post.purge_requested_at?'영구삭제 계속':'글 영구삭제',()=>removePermanently(post));purge.className='danger';card.append(purge);}}}list.append(card);
    const f=await c.from('cheongla_director_files').select('id,filename,object_path,removal_requested_at,caption').eq('post_id',post.id).eq('state','ready').order('created_at');if(request!==sequence)return;if(f.error){card.append(el('p','첨부파일을 불러오지 못했습니다. 다시 확인해 주세요.'));continue;}
    const fileTools=el('div');fileTools.className='director-file-tools';
    if(post.purge_requested_at){content.append(el('p','영구삭제 진행 중입니다. 영구삭제 계속 버튼으로 마쳐 주세요.'));continue;}
    const previewHeading=protectedContent&&!trashView?heading:null;
    for(const file of f.data||[]){
     if(file.removal_requested_at)content.append(el('p','첨부파일 삭제 진행 중 · '+file.filename));
     else await attachment(photos&&isImageAttachment(file)?photos:content,file,request,protectedContent,previewHeading);
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
 return{show,reset,edit,tracksArticles,restoreView};
}
root.CheonglaDirectorSpaceFactory={mount};
})(globalThis);
