const fs=require('fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const seed=require('./mbti-fixtures.cjs').articles();
const dom=new JSDOM(fs.readFileSync('index.html','utf8'),{runScripts:'outside-only'}),w=dom.window,d=w.document;
for(const path of ['mbti-library.js','mbti-articles.js','drafts/mbti-preview-adapter.js'])w.eval(fs.readFileSync(path,'utf8'));
let profile={id:'fixture-owner'},use=true,edit=true,consent=true,prints=[],deferred;
const fake=w.CheonglaMBTIPreview.make(seed),rpc=(name,args)=>deferred||fake.rpc(name.replace('mbti_articles','mbti_library'),args);
w.CheonglaPrint={clear(){},open(title,build,filename){const out=d.implementation.createHTMLDocument(title);build(out.body,out);prints.push({title,out,filename});}};
const ui=w.CheonglaMBTIArticles.mountPages({document:d,profile:()=>profile,canUse:()=>use,canEdit:()=>edit,confirm:async()=>consent,readable:e=>e.message,rpc});
const tick=()=>new Promise(r=>setImmediate(r)),settle=async()=>{for(let i=0;i<6;i++)await tick();};
const host=()=>d.querySelector('[data-mbti-page]:not([hidden]) .mbti-library');
const click=text=>{const b=[...host().querySelectorAll('button')].find(b=>b.textContent===text);assert(b,'missing '+text);b.click();};
(async()=>{
 let total=0;
 for(const [page,collection]of Object.entries(w.CheonglaMBTIArticles.collections)){
  await ui.open(page);assert(d.querySelector('#mbtiIntroduction').hidden,'legacy introduction visible');
  assert.equal(host().querySelectorAll('[data-document]').length,collection.codes.length);
  for(const code of collection.codes){host().querySelector('[data-document="'+code+'"]').click();await settle();const content=seed.documents.find(x=>x.code===code);
   assert.equal(host().querySelectorAll('[data-section]').length,content.sections.length);
   for(const section of content.sections){host().querySelector('[data-section="'+section.id+'"]').click();await settle();assert(host().querySelector('[data-section-body]').textContent.includes(section.title));total++;}
   click('문서 전체 인쇄 / PDF');const out=prints.at(-1).out;assert.equal(out.querySelectorAll('section').length,content.sections.length);assert.equal(out.querySelector('h2').textContent,content.sections[0].title);assert(out.body.textContent.includes(content.frontmatter.split('\n')[0]));
  }
 }
 assert.equal(total,54);await ui.open('mbti_intro');host().querySelector('[data-document="intro_learning"]').click();await settle();click('이 항목 수정');let body=host().querySelector('[data-body]');body.value+='\n저장검증문장';body.dispatchEvent(new w.Event('input',{bubbles:true}));assert(ui.dirty);
 consent=false;await ui.open('mbti_parents');assert(!d.querySelector('[data-mbti-page="mbti_intro"]').hidden);assert(ui.dirty);consent=true;click('수정 내용 저장');await settle();assert(!ui.dirty);assert(host().textContent.includes('저장검증문장'));
 click('이 항목 삭제 · 휴지통');await settle();click('휴지통 (1)');await settle();click('복원');await settle();click('학습법으로 돌아가기');await settle();assert(host().textContent.includes('저장검증문장'));
 click('이 항목 삭제 · 휴지통');await settle();click('휴지통 (1)');await settle();click('영구삭제');await settle();assert.equal((await fake.rpc('cheongla_mbti_library_list')).find(x=>x.code==='intro_learning').content.sections[0].body,null);
 click('학습법으로 돌아가기');await settle();host().querySelector('[data-document="intro_letter"]').click();await settle();click('이 문서 전체 삭제 · 휴지통');await settle();click('휴지통 (1)');await settle();click('휴지통 비우기');await settle();assert.equal((await fake.rpc('cheongla_mbti_library_list')).find(x=>x.code==='intro_letter').content,null);
 await ui.open('mbti_groups');assert.equal(host().querySelectorAll('table').length,1);click('문서 전체 인쇄 / PDF');assert.equal(prints.at(-1).out.querySelectorAll('table').length,seed.documents.find(x=>x.code==='groups').sections.length);
 edit=false;ui.reset();await ui.open('mbti_parents');assert(![...host().querySelectorAll('button')].some(b=>b.textContent.includes('수정')||b.textContent.includes('휴지통')));
 let resolve;deferred=new Promise(r=>resolve=r);const pending=ui.open('mbti_groups');ui.reset();profile={id:'fixture-other'};resolve(await fake.rpc('cheongla_mbti_library_list'));await pending;assert.equal(host().children.length,0,'stale account data leaked');
 dom.window.close();console.log('PASS three revised menus/eight documents/54 sections: source navigation and safe tables, full/section exports, dirty-page guard, shared edit/save/trash/restore/purge/empty, read-only and stale-account isolation');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
