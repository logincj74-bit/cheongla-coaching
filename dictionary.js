/* Cheongla dictionary UI. Data attribution: assets/dictionary/ATTRIBUTION.txt. */
(()=>{
 'use strict';
 const posLabels={'n.':'명사','v.':'동사','adj.':'형용사','adv.':'부사','pron.':'대명사','prep.':'전치사','conj.':'접속사','interj.':'감탄사','det.':'한정사','num.':'수사','art.':'관사','phr.':'구'};
 const normalize=value=>String(value||'').normalize('NFKC').replace(/[’‘]/g,"'").replace(/[–—]/g,'-').trim().replace(/\s+/g,' ').toLowerCase();
 const valid=word=>/^[a-z][a-z0-9 .'-]{0,79}$/.test(word);
 const bucket=word=>String(Math.floor((word.charCodeAt(0)-97)/4));
 function inflectionCandidates(word){
  const candidates=[];
  if(word.endsWith('ies')&&word.length>4)candidates.push(word.slice(0,-3)+'y');
  if(word.endsWith('es'))candidates.push(word.slice(0,-2));
  if(word.endsWith('s')&&!word.endsWith('ss'))candidates.push(word.slice(0,-1));
  if(word.endsWith('ied'))candidates.push(word.slice(0,-3)+'y');
  for(const suffix of ['ed','ing'])if(word.endsWith(suffix)&&word.length>suffix.length+2){const stem=word.slice(0,-suffix.length);candidates.push(stem,stem+'e');if(/([b-df-hj-np-tv-z])\1$/.test(stem))candidates.push(stem.slice(0,-1));}
  return [...new Set(candidates)].filter(valid);
 }
 function createLookup(fetcher,options={}){
  const cache=new Map();
  function get(path){
   if(!cache.has(path))cache.set(path,(async()=>{const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);try{const r=await fetcher('assets/dictionary/'+path,{signal:controller.signal,credentials:'omit'});if(!r.ok)throw Error('사전 자료를 불러오지 못했습니다. 잠시 후 다시 찾아 주세요.');return await r.json();}finally{clearTimeout(timer);}})().catch(e=>{cache.delete(path);throw e;}));
   return cache.get(path);
  }
  async function bundle(word){
   const results=await Promise.allSettled([get(bucket(word)+'.json?v=en-ko-v1.2.0-cheongla-2'),get('supplement/'+word[0]+'.json?v=20261027-1'),get('editorial-senses.json?v=20261024-1'),get('coverage-core.json?v=20261027-coverage-2')]);
   if(results[0].status==='rejected'&&results[1].status==='rejected'&&results[3].status==='rejected')throw results[0].reason;
   const data=i=>results[i].status==='fulfilled'?results[i].value:{entries:{},aliases:{}};
   return {base:data(0),supp:data(1),extra:data(2),core:data(3),incomplete:results.some(x=>x.status==='rejected')};
  }
  const has=(data,word)=>Object.hasOwn(data?.entries||{},word);
  const owns=(b,word)=>has(b.base,word)||has(b.supp,word)||has(b.extra,word)||has(b.core,word);
  function itemsFor(b,word){
   if(has(b.core,word))return b.core.entries[word].map(x=>({...x,editorial:true}));
   const base=has(b.base,word)?b.base.entries[word]:[],supp=has(b.supp,word)?b.supp.entries[word]:[];
   if(has(b.extra,word))return [{w:base[0]?.w||word,p:base[0]?.p||supp[0]?.p||'',s:b.extra.entries[word],editorial:true}];
   if(supp.some(x=>x.reviewed))return supp.map(x=>({...x,p:base[0]?.p||x.p,editorial:true}));
   return [...base,...supp];
  }
  async function lookup(value){
   const word=normalize(value);if(!valid(word))throw Error('영어 단어나 짧은 표현을 입력해 주세요. (최대 80자)');
   const b=await bundle(word);let refs=[...new Set([...(owns(b,word)?[word]:[]),...(Object.hasOwn(b.base.aliases||{},word)?b.base.aliases[word]:[])])].slice(0,4);
   if(!refs.length)refs=inflectionCandidates(word).filter(ref=>owns(b,ref)).slice(0,4);
   const results=[];let incomplete=b.incomplete;
   for(const ref of refs){const part=ref[0]===word[0]?b:await bundle(ref);incomplete ||= part.incomplete;const items=itemsFor(part,ref);if(!items.length)continue;
    const pronunciations=[...new Set(items.map(x=>x.p).filter(Boolean))];const senses=[],seen=new Set();
    for(const item of items)for(const s of item.s){const k=s[0]+'|'+s[1].replace(/[。.,，;；\s]+$/g,'');if(!seen.has(k)){seen.add(k);senses.push({pos:posLabels[s[0]]||s[0],meaning:s[1]});}}
    results.push({word:ref,display:items[0].w,pronunciation:pronunciations.join(' · '),editorial:items.some(x=>x.editorial===true),senses});
   }
   if(!results.length&&incomplete)throw Error('일부 사전 자료를 불러오지 못했습니다. 연결 상태를 확인하고 다시 찾아 주세요.');
   const keys=[...new Set([...Object.keys(b.base.entries),...Object.keys(b.supp.entries),...Object.keys(b.extra.entries),...Object.keys(b.core.entries)])];
   return {query:word,results,incomplete,suggestions:results.length?[]:keys.filter(x=>x.startsWith(word.slice(0,Math.min(3,word.length)))).sort().slice(0,5)};
  }
  const baseLookup=lookup;
  async function withCustom(value){
   const word=normalize(value);if(!valid(word))return baseLookup(value);
   let base,error;try{base=await baseLookup(word);}catch(e){error=e;base={query:word,results:[],suggestions:[],incomplete:true};}
   let rows=[];try{if(options.custom)rows=await options.custom([...new Set([word,...base.results.map(x=>x.word),...inflectionCandidates(word)])]);}catch(e){if(error)throw error;if(!base.results.length)throw Error('원장 등록 사전을 확인하지 못했습니다. 연결 상태를 확인하고 다시 찾아 주세요.');base.incomplete=true;}
   const convert=row=>({word:row.word,display:row.word,pronunciation:row.pronunciation||'',custom:true,senses:row.senses.map(s=>({pos:posLabels[s.pos]||s.pos,meaning:s.meaning}))});
   const exact=rows.find(x=>x.word===word);
   if(exact)return {...base,results:[convert(exact)],suggestions:[]};
   const mapped=base.results.map(entry=>{const row=rows.find(x=>x.word===entry.word);return row?convert(row):entry;});
   if(!mapped.length)for(const ref of inflectionCandidates(word)){const row=rows.find(x=>x.word===ref);if(row)mapped.push(convert(row));if(mapped.length===4)break;}
   if(error&&!mapped.length)throw error;
   return {...base,results:mapped,suggestions:mapped.length?[]:base.suggestions};
  }
  withCustom.base=baseLookup;return withCustom;
 }
 function mount(adapter){
  const doc=adapter.document||document,$=id=>doc.getElementById(id),lookup=createLookup(adapter.fetch||fetch,{custom:adapter.client?async words=>{const c=await adapter.client(),r=await c.from('cheongla_dictionary_overrides').select('word,pronunciation,senses,updated_at').in('word',words);if(r.error)throw r.error;return r.data||[];}:null});
  let searchRequest=0,current=[];
  $('personalWordbook')?.remove();
  for(const item of doc.querySelectorAll('[data-public-page="dictionary"]'))item.textContent='영단어 찾기';
  if($('dictionaryHeading'))$('dictionaryHeading').textContent='영단어 찾기';
  if($('dictionaryHelp'))$('dictionaryHelp').textContent='32,720개 기본 표제어 · 한국어 뜻과 제공된 품사·발음기호를 확인합니다. 복수형·과거형·진행형도 기본형을 찾아봅니다. 원장님이 추가한 단어도 함께 검색합니다. 뜻의 수는 단어마다 다릅니다.';
  const credit=doc.querySelector('#homeDictionary .dictionary-credit');if(credit){const note=doc.createElement('span');note.textContent=' 한국어 위키낱말사전·Kaikki 자료와 청라 검토 핵심 어휘 154개를 추가했습니다.';credit.prepend(note);}
  const description=doc.querySelector('#homeDictionary .dictionary-description');if(description)description.textContent='궁금한 영어 단어의 뜻·품사·발음기호를 찾아보세요.';
  function node(tag,text,cls){const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
  function errorText(e){return e?.name==='AbortError'?'연결이 지연되고 있습니다. 다시 찾아 주세요.':e?.message||'처리하지 못했습니다. 다시 시도해 주세요.';}
  function renderResults(result){
   const list=$('dictionaryResults');list.replaceChildren();current=result.results;
   if(!current.length){$('dictionaryStatus').textContent='아직 수록되지 않은 단어입니다. 철자나 기본형을 확인해 주세요.';
    if(result.suggestions.length){const box=node('div','비슷한 시작의 단어: ','dictionary-actions');for(const word of result.suggestions){const b=node('button',word,'secondary');b.type='button';b.addEventListener('click',()=>{$('dictionaryWord').value=word;void search();});box.append(b);}list.append(box);}return;}
   $('dictionaryStatus').textContent=(result.query===current[0].word?'뜻을 찾았습니다.':'「'+result.query+'」의 기본형 뜻입니다.')+(result.incomplete?' 일부 보강 자료는 연결 후 다시 확인해 주세요.':'');
   for(const entry of current){const card=node('article',undefined,'dictionary-card');card.append(node('h3',entry.display));card.append(node('p','뜻 '+entry.senses.length+'개'+(entry.custom?' · 원장 등록·수정 뜻':entry.editorial?' · 청라 학습용 대표 뜻':''),'dictionary-source-note'));if(entry.pronunciation)card.append(node('p',entry.pronunciation,'dictionary-pronunciation'));
    const senses=node('ol',undefined,'dictionary-senses');for(const sense of entry.senses){const li=node('li');if(sense.pos)li.append(node('span',sense.pos,'dictionary-pos'));li.append(node('span',sense.meaning));senses.append(li);}card.append(senses);
    list.append(card);}

  }
  async function search(){
   const request=++searchRequest,value=$('dictionaryWord').value;
   if(!valid(normalize(value))){$('dictionaryResultsWrap').hidden=true;$('dictionaryResults').replaceChildren();current=[];$('dictionaryStatus').textContent='영어 단어나 짧은 표현을 입력해 주세요. (최대 80자)';$('dictionaryWord').focus();return;}
   $('dictionaryResultsWrap').hidden=false;$('dictionaryResults').replaceChildren();$('dictionaryStatus').textContent='단어 뜻을 찾는 중…';$('dictionarySearchButton').disabled=true;
   try{const result=await lookup(value);if(request!==searchRequest)return;renderResults(result);}
   catch(e){if(request===searchRequest)$('dictionaryStatus').textContent=errorText(e);}
   finally{if(request===searchRequest)$('dictionarySearchButton').disabled=false;}
  }
  let admin;function accountChanged(){searchRequest++;$('dictionarySearchButton').disabled=false;admin?.configure();}
  if(adapter.client&&adapter.profile)void import('./dictionary-admin.js?v=20261027-1').then(m=>{admin=m.mountDictionaryAdmin(adapter,{baseLookup:lookup.base,normalize,valid,onSaved:word=>{$('dictionaryWord').value=word;void search();}});admin.configure();}).catch(()=>{});
  $('dictionaryForm').addEventListener('submit',e=>{e.preventDefault();void search();});
  $('dictionaryClear').addEventListener('click',()=>{searchRequest++;$('dictionaryResultsWrap').hidden=true;$('dictionaryResults').replaceChildren();$('dictionaryStatus').textContent='';$('dictionarySearchButton').disabled=false;current=[];});
  return {accountChanged,search};
 }
 globalThis.CheonglaDictionaryFactory={mount,createLookup,normalize,valid,inflectionCandidates};
 if(typeof module!=='undefined'&&module.exports)module.exports={createLookup,normalize,valid,mount,inflectionCandidates};
})();
