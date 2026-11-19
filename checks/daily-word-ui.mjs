import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');const block=html.split('// DAILY_WORD_START')[1].split('// DAILY_WORD_END')[0];
function node(tag='div'){return {tag,dataset:{},children:[],value:'',textContent:'',hidden:false,open:false,disabled:false,handlers:{},append(...n){this.children.push(...n);},replaceChildren(...n){this.children=n;},getAttribute(key){return this[key]??null;},addEventListener(k,f){this.handlers[k]=f;},focus(){},scrollIntoView(){},querySelectorAll(){return [];},reset(){},get options(){return this.children;}};}
const ids=[...html.matchAll(/id="(dailyWord[^"]+)"/g)].map(m=>m[1]);const elements=Object.fromEntries(ids.map(id=>[id,node()]));elements.homePanel=node();elements.dailyWordVisibility.value='published';elements.dailyWordChoose.value='today';
let rows=[],rotationRows=[],rotationWrites=0,reads=0,saves=0,captured=null,readError=null,pendingRead=null,approveDiscard=true;
const ctx=vm.createContext({Date,console,document:{hidden:false,createElement:node,addEventListener(){}},window:{addEventListener(){}},setInterval(){},$:id=>elements[id],currentProfile:null,isContentOwner(){return ctx.currentProfile?.id==='owner';},scheduleKST:()=> '2026-10-22T12:00:00.000Z',appConfirm:async()=>approveDiscard,readable:e=>e.message||'저장 오류',tuitionText(parent,text,tag='p'){const n=node(tag);n.textContent=text;parent.append(n);return n;},getClient:async()=>({from(name){if(name==='cheongla_daily_rotation')return {select(){return this;},async limit(){return {data:rotationRows};}};assert.equal(name,'cheongla_daily_words');return {select(){return this;},order(){return this;},async limit(){reads++;if(pendingRead)return await pendingRead();return {data:rows,error:readError};}};},async rpc(name,args){if(name==='cheongla_save_daily_rotation'){rotationWrites++;assert.equal(args.expected_revision,null);const row={slot:args.target_slot,title:args.post_title,body:args.post_body,photo:args.post_photo,revision:1};rotationRows=[row];return {data:row};}saves++;captured=args;assert.equal(name,'cheongla_save_daily_word');const row={id:'saved',message_on:args.target_day,title:args.post_title,body:args.post_body,status:args.post_status,updated_at:'2026-10-22T10:00:00Z'};rows=[row];return {data:row};}})});
vm.runInContext(block,ctx);const run=code=>vm.runInContext(code,ctx),flush=()=>new Promise(setImmediate);await flush();assert.equal(elements.dailyWordManage.hidden,true);assert.equal(elements.dailyWordFeatured.hidden,false);assert.equal(elements.dailyWordStatus.textContent,'');
const firstImage=elements.dailyWordImage.src,firstBody=elements.dailyWordBody.textContent;
assert.match(firstImage,/assets\/daily-word\/.+\.webp$/);assert.ok(firstBody);
const nextDay=run('automaticDailyWord("2026-10-23")');assert.notEqual(nextDay.image,firstImage);assert.notEqual(nextDay.body,firstBody);
const gallery=run('dailyWordPhotos');assert.equal(gallery.length,86);assert.equal(new Set(gallery).size,86);for(const photo of gallery)assert.ok(fs.existsSync(new URL('../assets/daily-word/'+photo,import.meta.url)));
rows=[{id:'past',message_on:'2026-10-21',title:'어제 글',body:'꾸준히',status:'published',updated_at:'v1'},{id:'today',message_on:'2026-10-22',title:'오늘 글',body:'<img src=x onerror=bad()>',status:'published',updated_at:'v2'},{id:'private',message_on:'2026-10-22',title:'비공개',body:'보이면 안 됨',status:'draft'},{id:'future',message_on:'2026-10-23',title:'미래',body:'아직 아님',status:'published'}];
await run('loadDailyWord(true)');assert.equal(elements.dailyWordTitle.textContent,'오늘 글');assert.equal(elements.dailyWordBody.textContent,'<img src=x onerror=bad()>');assert.equal(elements.dailyWordHistory.children.length,1);assert.equal(elements.dailyWordArchive.hidden,false);assert.equal(elements.dailyWordManage.hidden,true);
for(const role of ['student','parent','manager','korean_teacher']){ctx.currentProfile={id:role,role,approval_status:'approved',membership_state:'active'};assert.equal(run('canManageDailyWord()'),false);await elements.dailyWordForm.handlers.submit({preventDefault(){}});assert.equal(saves,0);}
for(const role of ['owner','english_director','math_director']){ctx.currentProfile={id:role,role,approval_status:'approved',membership_state:'active'};assert.equal(run('canManageDailyWord()'),role==='owner');}
ctx.currentProfile={id:'owner',role:'english_director',approval_status:'approved',membership_state:'active'};await run('loadDailyWord(true)');assert.equal(elements.dailyWordManage.hidden,false);await run('openDailyWordEditor("2026-10-22")');assert.equal(elements.dailyWordInputTitle.value,'오늘 글');assert.equal(elements.dailyWordDay.max,'2026-10-22');elements.dailyWordInputBody.value='수정한 격려';elements.dailyWordVisibility.value='published';await elements.dailyWordForm.handlers.submit({preventDefault(){}});assert.equal(saves,1);assert.equal(captured.expected_updated_at,'v2');assert.equal(elements.dailyWordBody.textContent,'수정한 격려');assert.equal(elements.dailyWordEditor.open,false);
await run('openDailyWordEditor("2026-10-22")');elements.dailyWordInputBody.value='';await elements.dailyWordForm.handlers.submit({preventDefault(){}});assert.equal(saves,1);assert.match(elements.dailyWordSaveStatus.textContent,/본문/);
elements.dailyWordInputBody.value='작성 중';elements.dailyWordInputBody.handlers.input();approveDiscard=false;elements.dailyWordDay.value='2026-10-21';await elements.dailyWordDay.handlers.change();assert.equal(elements.dailyWordDay.value,'2026-10-22');assert.equal(elements.dailyWordInputBody.value,'작성 중');approveDiscard=true;
let release;pendingRead=()=>new Promise(resolve=>release=resolve);const request=run('loadDailyWord(true)');await flush();ctx.currentProfile=null;run('resetDailyWord()');release({data:rows});await request;assert.equal(elements.dailyWordManage.hidden,true);assert.equal(elements.dailyWordFeatured.hidden,true);assert.equal(elements.dailyWordBody.textContent,'');pendingRead=null;readError={message:'offline'};await run('loadDailyWord(true)');assert.match(elements.dailyWordStatus.textContent,/불러오지 못/);
ctx.currentProfile={id:'owner',role:'english_director',approval_status:'approved',membership_state:'active'};
await run('loadDailyWord(true)');
elements.dailyWordRotationEditor.open=true;
elements.dailyWordRotationEditor.handlers.toggle();
assert.equal(elements.dailyWordRotationPhoto.children.length,86);
elements.dailyWordRotationTitle.value='새 자동 제목';
elements.dailyWordRotationBody.value='새 자동 문구';
elements.dailyWordRotationPhoto.value=gallery.find(photo=>photo!==run('dailyRotationSlot.photo'));
elements.dailyWordRotationPhoto.handlers.change();
assert.match(elements.dailyWordRotationPreview.src,/assets\/daily-word/);
await elements.dailyWordRotationForm.handlers.submit({preventDefault(){}});
assert.equal(rotationWrites,1);
assert.equal(run('automaticDailyWord(dailyWordToday()).body'),'새 자동 문구');
assert.equal(elements.dailyWordImage.src,'assets/daily-word/'+rotationRows[0].photo);
ctx.currentProfile={id:'staff',role:'manager'};
await elements.dailyWordRotationForm.handlers.submit({preventDefault(){}});
assert.equal(rotationWrites,1);
assert.ok(html.indexOf('id="dailyWordPanel"')<html.indexOf('id="homeSchedule"'));assert.match(html,/<section id="homeSchedule"[^>]* hidden/);assert.match(html,/data-daily-dday/);assert.ok(!block.includes('innerHTML'));
console.log('PASS daily word UI: public/latest/history, private/future filtering, principal-only editor/save, version token, validation, dirty edit cancellation, logout/stale reply, load error and placement.');
