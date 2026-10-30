const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto').webcrypto;
class N{constructor(tag='div'){this.tag=tag;this.children=[];this.events={};this.value='';this.open=false;this.hidden=false;this.style={};this.files=[];}append(...n){this.children.push(...n);}replaceChildren(...n){this.children=n;}setAttribute(k,v){this[k]=v;}addEventListener(k,f){this.events[k]=f;}reportValidity(){return true;}reset(){}showModal(){this.open=true;}close(){this.open=false;}get textContent(){return(this.text||'')+this.children.map(n=>n.textContent||'').join('');}set textContent(t){this.text=t;this.children=[];}}
const nodes={},$=id=>nodes[id]??=new N(),doc={getElementById:$,createElement:t=>new N(t),body:new N('body'),head:new N('head'),events:{},addEventListener(k,f){this.events[k]=f;},getSelection(){return null;}},flat=n=>[n,...n.children.flatMap(flat)];
let profile={id:'principal',role:'owner'},posts=[],attachments=[],calls=[],uploads=0,notifications=0,fail=false,signedCalls=[],removeCalls=[],removeFail=false,finishFail=false,allowConfirm=true;
function query(table){let filters=[];const q={select(){return this;},eq(k,v){filters.push(r=>r[k]===v);return this;},is(k,v){filters.push(r=>r[k]===v);return this;},not(k,op,v){filters.push(r=>r[k]!==v);return this;},order(){return this;},limit(){return this;},maybeSingle(){return Promise.resolve({data:null});},then(resolve,reject){return Promise.resolve({data:(table==='cheongla_director_posts'?posts:attachments).filter(r=>filters.every(f=>f(r)))}).then(resolve,reject);}};return q;}
const client={from:query,storage:{from:()=>({upload:async()=>{uploads++;return{};},remove:async paths=>{removeCalls.push(paths);return removeFail?{error:Error('storage offline')}:{data:paths};},createSignedUrl:async(...args)=>{signedCalls.push(args);return{data:{signedUrl:'https://db.example/file'}};}})},rpc:async(name,a)=>{
 calls.push({name,a});if(name==='cheongla_prepare_director_post'){let row=posts.find(p=>p.id===a.target_post);if(!row){row={id:crypto.randomUUID(),category:a.post_category,title:'새 글',body:'',state:'draft',updated_at:'v1',created_at:'2026-10-29',archived_at:null};posts.push(row);}return{data:{...row}};}
 if(name==='cheongla_begin_director_removal'){const p=posts.find(p=>p.id===a.target_post);assert.equal(p.updated_at,a.expected_updated_at);const f=attachments.find(f=>f.id===a.target_file);if(f)f.removal_requested_at='pending';else p.purge_requested_at='pending';p.updated_at='remove'+calls.length;return{data:{post_id:p.id,file_id:a.target_file,updated_at:p.updated_at,paths:attachments.filter(f=>f.post_id===p.id&&(!a.target_file||f.id===a.target_file)).map(f=>f.object_path)}};}
 if(name==='cheongla_finish_director_removal'){if(finishFail)return{error:Error('finish offline')};const p=posts.find(p=>p.id===a.target_post);assert.equal(p.updated_at,a.expected_updated_at);assert(removeCalls.length);attachments=attachments.filter(f=>a.target_file?f.id!==a.target_file:f.post_id!==a.target_post);if(!a.target_file)posts=posts.filter(p=>p.id!==a.target_post);return{data:true};}
 if(name==='cheongla_trash_director_post'){if(fail)return{error:Error('글이 변경되었습니다')};const row=posts.find(p=>p.id===a.target_post);Object.assign(row,{archived_at:a.restore_post?null:'2026-10-30',state:a.restore_post?'draft':row.state,updated_at:'v'+calls.length});return{data:{...row}};}
 if(name==='cheongla_stage_director_file'){const f={id:crypto.randomUUID(),post_id:a.target_post,object_path:a.object_name,filename:a.original_name,state:'pending'};attachments.push(f);return{data:f.id};}
 if(name==='cheongla_save_director_post'){if(fail)return{error:Error('다른 원장이 변경했습니다')};const row=posts.find(p=>p.id===a.target_post);Object.assign(row,{title:a.post_title,body:a.post_body,state:a.post_state,updated_at:'2026-10-29T00:00:00Z'});for(const f of attachments)if(a.file_ids.includes(f.id))f.state='ready';return{data:{...row}};}return{data:true};}};
const ctx=vm.createContext({document:doc,crypto,Date,URL,location:{assign(){}},showPublicPage:()=>{$('publicContentPanel').hidden=false;},showSiteHome:()=>{$('publicContentPanel').hidden=true;},navigateNotification:async()=>{}});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../director-space.js'),'utf8'),ctx);
const ui=ctx.CheonglaDirectorSpaceFactory.mount({document:doc,profile:()=>profile,principal:()=>profile?.role==='owner',client:async()=>client,confirm:async()=>allowConfirm,readable:e=>e.message,greeting:()=>({title:'원장 인사말',paragraphs:['기존 인사말 보존']}),notifyReload:()=>{notifications++;}});
(async()=>{
 await ui.show('greeting');assert($('publicContentBody').textContent.includes('기존 인사말 보존'));
 for(const[key,label]of[['director_thoughts','원장의 단상'],['director_photos','사진에게 말을 걸다'],['director_objects','사물로 읽는 사람']]){await ui.show(key);assert.equal($('publicContentTitle').textContent,label);assert($('publicContentBody').textContent.includes('새 글 작성'));}
 await ui.edit('objects');const dialog=doc.body.children[0],form=dialog.children[1],all=()=>flat(form),title=all().find(n=>n.tag==='input'&&n.type==='text'),body=all().find(n=>n.tag==='textarea'),files=all().find(n=>n.type==='file');assert(dialog.open);title.value='사물과 사람';body.value='<script>문자 그대로</script>';files.files=[{name:'사진.png',size:4,lastModified:1,type:'image/png'}];await Promise.all([form.events.submit({preventDefault(){}}),form.events.submit({preventDefault(){}})]);assert.equal(uploads,1);assert.equal(calls.filter(c=>c.name==='cheongla_save_director_post').length,1);assert.equal(attachments[0].state,'ready');assert($('publicContentBody').textContent.includes('<script>문자 그대로</script>'));assert(!flat($('publicContentBody')).some(n=>n.tag==='script'));assert.equal(notifications,1);assert(!dialog.open);
 await ui.edit('objects',posts[0]);fail=true;title.value='보관할 초안';files.files=[];await form.events.submit({preventDefault(){}});assert(dialog.open);assert(form.textContent.includes('다른 원장'));assert.equal(title.value,'보관할 초안');ui.reset();fail=false;
 for(const role of ['manager','student']){profile={id:role,role};const before=calls.length;await ui.edit('thoughts');assert.equal(calls.length,before);}
 profile=null;await ui.show('director_objects');assert(!$('publicContentBody').textContent.includes('새 글 작성'));assert(!$('publicContentBody').textContent.includes('글 수정 · 첨부파일 추가'));assert($('publicContentBody').textContent.includes('사물과 사람'));assert(!$('publicContentBody').textContent.includes('첨부파일 내려받기'));assert($('publicContentBody').textContent.includes('저작권 보호 콘텐츠'));
 const root=$('publicContentBody'),protectedNode=flat(root).find(n=>n.className?.includes('director-protected')&&n.tag==='div');
 assert(protectedNode);assert(flat(protectedNode).some(n=>n.tag==='h3'));assert(doc.head.textContent.includes('@media print'));
 const event=extra=>({blocked:false,preventDefault(){this.blocked=true;},stopPropagation(){},...extra});
 for(const name of ['copy','cut','contextmenu','dragstart','selectstart']){const e=event();protectedNode.events[name](e);assert(e.blocked,name);}
 const image=flat(root).find(n=>n.tag==='img');assert.equal(String(image.draggable),'false');
 for(const key of ['s','p']){const e=event({ctrlKey:true,key});doc.events.keydown(e);assert(e.blocked);}
 const copy=event({target:{closest:()=>protectedNode}});doc.events.copy(copy);assert(copy.blocked);
 attachments.push({id:'pdf',post_id:posts[0].id,object_path:posts[0].id+'/protected.pdf',filename:'원본.pdf',state:'ready'});
 for(const [key,category]of [['director_thoughts','thoughts'],['director_photos','photos'],['director_objects','objects']]){
  posts[0].category=category;signedCalls=[];await ui.show(key);assert(root.textContent.includes('원본 파일 제공 제한'));assert(!root.textContent.includes('첨부파일 내려받기'));assert(!signedCalls.some(a=>a[0]===posts[0].id+'/protected.pdf'));
 }
 profile={id:'principal',role:'owner'};await ui.show('director_objects');assert(root.textContent.includes('글 수정 · 첨부파일 추가'));await ui.edit('objects',posts[0]);
 const editingSave=event({ctrlKey:true,key:'s'});doc.events.keydown(editingSave);assert(!editingSave.blocked);ui.reset();
 for(const category of ['thoughts','photos','objects']){
  posts[0].category=category;await ui.show('director_'+category);const find=text=>flat(root).find(n=>n.tag==='button'&&n.textContent===text);
  assert(find('글 삭제'));fail=true;await find('글 삭제').events.click();assert.equal(posts[0].archived_at,null);assert($('siteStatus').textContent.includes('변경'));fail=false;
  await find('글 삭제').events.click();assert(posts[0].archived_at);assert(!root.textContent.includes('사물과 사람'));
  await find('휴지통').events.click();assert(root.textContent.includes('사물과 사람'));assert(find('글 복구'));assert(!find('글 수정 · 첨부파일 추가'));
  await find('글 복구').events.click();assert.equal(posts[0].archived_at,null);assert.equal(posts[0].state,'draft');assert(root.textContent.includes('사물과 사람'));
 }
 const findButton=text=>flat(root).find(n=>n.tag==='button'&&n.textContent===text);
 for(const category of ['thoughts','photos','objects']){
  const p={...posts[0],id:crypto.randomUUID(),category,archived_at:null,state:'published'};posts.push(p);
  const first={id:crypto.randomUUID(),post_id:p.id,object_path:p.id+'/photo.png',filename:'지울사진.png',state:'ready'},second={id:crypto.randomUUID(),post_id:p.id,object_path:p.id+'/keep.pdf',filename:'남길문서.pdf',state:'ready'};attachments.push(first,second);
  await ui.show('director_'+category);const fileButton=()=>flat(root).find(n=>n['aria-label']==='지울사진.png 첨부 삭제');
  const before=calls.length;allowConfirm=false;await fileButton().events.click();assert.equal(calls.length,before);allowConfirm=true;
  removeFail=true;await fileButton().events.click();assert(first.removal_requested_at);assert(attachments.includes(first));assert($('siteStatus').textContent.includes('완료하지 못했습니다'));assert(findButton('삭제 계속'));removeFail=false;
  await findButton('삭제 계속').events.click();assert(!attachments.includes(first));assert(attachments.includes(second));assert(posts.includes(p));assert.equal(p.body,'<script>문자 그대로</script>');assert(!removeCalls.flat().includes(second.object_path));
  const card=flat(root).find(n=>n.tag==='article'&&flat(n).some(x=>x['aria-label']==='남길문서.pdf 첨부 삭제'));await flat(card).find(n=>n.textContent==='글 삭제').events.click();await findButton('휴지통').events.click();
  const purgeCard=flat(root).find(n=>n.tag==='article'&&n.textContent.includes('남길문서.pdf'));const purge=flat(purgeCard).find(n=>n.tag==='button'&&n.textContent==='글 영구삭제');assert(purge);
  allowConfirm=false;const beforePurge=calls.length;await purge.events.click();assert.equal(calls.length,beforePurge);allowConfirm=true;
  finishFail=true;await purge.events.click();assert(posts.includes(p));assert(p.purge_requested_at);assert(findButton('영구삭제 계속'));const pendingCard=flat(root).find(n=>n.tag==='article'&&n.textContent.includes('영구삭제 계속'));assert(!flat(pendingCard).some(n=>n.textContent==='글 복구'));finishFail=false;
  await findButton('영구삭제 계속').events.click();assert(!posts.includes(p));assert(!attachments.includes(second));assert.equal(calls.filter(c=>c.name==='cheongla_begin_director_removal'&&c.a.target_post===p.id&&c.a.target_file===first.id).length,2);
 }
 for(const role of ['manager','student']){profile={id:role,role};await ui.show('director_objects');assert(!flat(root).some(n=>n.tag==='button'&&['글 삭제','휴지통','글 복구','첨부 삭제','삭제 계속','글 영구삭제','영구삭제 계속'].includes(n.textContent)));}
 profile={id:'principal',role:'owner'};posts[0].category='greeting';await ui.show('greeting');assert(root.textContent.includes('첨부파일 내려받기'));assert(!flat(root).some(n=>n.className?.includes('director-protected')));
 const ordinarySave=event({ctrlKey:true,key:'s'});doc.events.keydown(ordinarySave);assert(!ordinarySave.blocked);
 console.log('PASS director UI: all three protected categories, copy/cut/contextmenu/drag/selection, print/save shortcuts, image drag, document signing denied; owner editing and greeting downloads preserved; file-only removal preserves post/other files; cancelled deletes make no calls; storage/finish failures resume; post purge removes all files and cannot restore during purge');
})().catch(e=>{console.error(e);process.exit(1);});
