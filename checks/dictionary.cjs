const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {createLookup,normalize,valid,mount}=require('../dictionary.js');
const dir=path.join(__dirname,'../assets/dictionary');let fetched=[];
async function dataFetch(url){assert(url.startsWith('assets/dictionary/'));fetched.push(url);return {ok:true,json:async()=>JSON.parse(fs.readFileSync(path.join(dir,url.match(/\/(\d+)\.json/)[1]+'.json'),'utf8'))};}
class N{constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.handlers={};this.hidden=false;this.disabled=false;this.open=false;this.value='';this.textContent='';}append(...x){this.children.push(...x)}replaceChildren(){this.children=[]}addEventListener(k,f){this.handlers[k]=f}setAttribute(k,v){this[k]=v}focus(){this.focused=true}querySelectorAll(sel){return this.children.flatMap(x=>[...(sel==='[data-save-word]'&&x.dataset?.saveWord?[x]:[]),...x.querySelectorAll(sel)])}}
const nodes={},$=id=>nodes[id]??=new N();const doc={getElementById:$,createElement:t=>new N(t)};
let actor={id:'first',approval_status:'approved',membership_state:'active'},confirm=false,fail=false,failLoad=false,db=[],pendingClient=null;
function query(){let filters=[],operation='select',payload=null,limit=Infinity;const q={select(){return q},eq(k,v){filters.push(x=>x[k]===v);return q},order(){return q},limit(n){limit=n;return q},upsert(row){operation='upsert';payload=row;return q},update(row){operation='update';payload=row;return q},delete(){operation='delete';return q},maybeSingle(){q.single=true;return q},then(ok,bad){if(fail||failLoad&&operation==='select')return Promise.resolve({error:{message:'검증 연결 오류'}}).then(ok,bad);let rows=db.filter(x=>filters.every(f=>f(x)));if(operation==='upsert'){if(!db.some(x=>x.user_id===payload.user_id&&x.word===payload.word))db.push({learned:false,...payload,created_at:new Date().toISOString()});rows=[];}if(operation==='update')for(const row of rows)Object.assign(row,payload);if(operation==='delete')db=db.filter(x=>!rows.includes(x));return Promise.resolve({data:q.single?rows[0]||null:rows.slice(0,limit)}).then(ok,bad)}};return q;}
const client={from:table=>{assert.equal(table,'cheongla_wordbook');return query()}};
const text=n=>[n.textContent,...n.children.map(text)].join(' ');
(async()=>{
 assert.equal(normalize('  STUDY  '),'study');assert.equal(normalize('it’s'),'it\'s');for(const s of ['','사과','../secret','<script>','a'.repeat(81)])assert(!valid(s));
 const lookup=createLookup(dataFetch);for(const [word,meaning]of [['study','공부'],['STUDIES','공부'],['went','가다'],['children','아이'],['bank','은행'],['beautiful','아름답다'],['photosynthesis','광합성']]){const r=await lookup(word);assert(r.results.length,word);assert(JSON.stringify(r).includes(meaning),word);}
 assert.equal((await lookup('qzxnonexistent')).results.length,0);await assert.rejects(()=>lookup('../secret'));const before=fetched.length;await lookup('study');assert.equal(fetched.length,before);
 let attempts=0;const retry=createLookup(async u=>{if(++attempts===1)throw Error('network');return dataFetch(u)});await assert.rejects(()=>retry('study'));assert((await retry('study')).results.length);
 const ui=mount({document:doc,fetch:dataFetch,profile:()=>actor,client:async()=>pendingClient?await pendingClient:client,confirm:async()=>confirm});
 $('dictionaryWord').value='study';await ui.search();assert(text($('dictionaryResults')).includes('공부'));const entry=(await lookup('study')).results[0];
 await ui.save(entry);await ui.save(entry);assert.equal(db.length,1);assert($('dictionaryStatus').textContent.includes('저장했습니다'));
 await ui.loadBook();assert(text($('wordbookList')).includes('study'));$('wordbookSearch').value='공부';$('wordbookSearch').handlers.input();assert(text($('wordbookList')).includes('study'));$('wordbookSearch').value='';
 await ui.setLearned(db[0]);assert.equal(db[0].learned,true);assert(text($('wordbookList')).includes('외운 단어'));
 $('wordbookFilter').value='review';await ui.loadBook();assert(!text($('wordbookList')).includes('study'));
 $('wordbookFilter').value='learned';await ui.loadBook();assert(text($('wordbookList')).includes('study'));
 await ui.setLearned(db[0]);assert.equal(db[0].learned,false);assert(!text($('wordbookList')).includes('study'));
 $('wordbookFilter').value='all';await ui.loadBook();fail=true;await ui.setLearned(db[0]);assert.equal(db[0].learned,false);assert($('wordbookStatus').textContent.includes('연결 오류'));fail=false;
 confirm=false;await ui.removeWord(db[0]);assert.equal(db.length,1);confirm=true;await ui.removeWord(db[0]);assert.equal(db.length,0);assert($('wordbookStatus').textContent.includes('삭제했습니다'));
 fail=true;await ui.save(entry);assert.equal(db.length,0);assert($('dictionaryStatus').textContent.includes('연결 오류'));fail=false;await ui.save(entry);assert.equal(db.length,1);
 failLoad=true;await ui.removeWord(db[0]);assert.equal(db.length,0);assert($('wordbookStatus').textContent.includes('삭제는 완료'));assert(!text($('wordbookList')).includes('study'));failLoad=false;
 await ui.save(entry);await ui.loadBook();actor={id:'second',approval_status:'approved',membership_state:'active'};ui.accountChanged();assert.equal($('wordbookList').children.length,0);await ui.loadBook();assert(!text($('wordbookList')).includes('study'));
 let release;pendingClient=new Promise(r=>release=r);const pending=ui.save(entry);actor=null;ui.accountChanged();release(client);await pending;pendingClient=null;assert.equal(db.filter(x=>x.user_id==='second').length,0);assert.equal($('wordbookList').children.length,0);
 actor={id:'first',approval_status:'pending',membership_state:'active'};ui.accountChanged();await ui.save(entry);assert.equal(db.length,1);
 $('dictionaryWord').value='<script>';await ui.search();assert.equal($('dictionaryResultsWrap').hidden,true);assert($('dictionaryWord').focused);
 console.log('PASS: real Korean dictionary data, normalization/inflections, misses, same-origin lazy caching and retry; personal save/read/dedup/search/delete confirmation; network failure, stale account/logout isolation, pending user blocked, no HTML rendering.');
})().catch(e=>{console.error(e);process.exit(1)});
