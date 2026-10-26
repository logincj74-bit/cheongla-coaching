/* Cheongla dictionary UI. Data attribution: assets/dictionary/ATTRIBUTION.txt. */
(()=>{
 'use strict';
 const posLabels={'n.':'명사','v.':'동사','adj.':'형용사','adv.':'부사','pron.':'대명사','prep.':'전치사','conj.':'접속사','interj.':'감탄사','det.':'한정사','num.':'수사','art.':'관사','phr.':'구'};
 const normalize=value=>String(value||'').normalize('NFKC').replace(/[’‘]/g,"'").replace(/[–—]/g,'-').trim().replace(/\s+/g,' ').toLowerCase();
 const valid=word=>/^[a-z][a-z0-9 .'-]{0,79}$/.test(word);
 const bucket=word=>String(Math.floor((word.charCodeAt(0)-97)/4));
 function createLookup(fetcher){
  const cache=new Map();let editorialPromise;
  async function editorial(){
   if(!editorialPromise)editorialPromise=(async()=>{const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);try{const r=await fetcher('assets/dictionary/editorial-senses.json?v=20261024-1',{signal:controller.signal,credentials:'omit'});if(!r.ok)throw Error('보강 사전 자료를 불러오지 못했습니다. 다시 찾아 주세요.');return (await r.json()).entries;}finally{clearTimeout(timer);}})().catch(e=>{editorialPromise=null;throw e;});return editorialPromise;
  }
  async function shard(id){
   if(!cache.has(id))cache.set(id,(async()=>{
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);
    try{const r=await fetcher('assets/dictionary/'+id+'.json?v=en-ko-v1.2.0-cheongla-2',{signal:controller.signal,credentials:'omit'});if(!r.ok)throw Error('사전 자료를 불러오지 못했습니다. 잠시 후 다시 찾아 주세요.');return await r.json();}
    finally{clearTimeout(timer);}
   })().catch(e=>{cache.delete(id);throw e;}));
   return cache.get(id);
  }
  async function lookup(value){
   const word=normalize(value);if(!valid(word))throw Error('영어 단어나 짧은 표현을 입력해 주세요. (최대 80자)');
   const [d,extra]=await Promise.all([shard(bucket(word)),editorial()]);const own=Object.hasOwn(d.entries,word)||Object.hasOwn(extra,word),refs=own?[word]:Object.hasOwn(d.aliases,word)?d.aliases[word].slice(0,4):[];
   const results=[];
   for(const ref of refs){const part=await shard(bucket(ref));let items=Object.hasOwn(part.entries,ref)?part.entries[ref]:[];if(Object.hasOwn(extra,ref))items=[{w:items[0]?.w||ref,p:items[0]?.p||'',s:extra[ref],editorial:true}];if(!items.length)continue;
    const pronunciations=[...new Set(items.map(x=>x.p).filter(Boolean))];const senses=[],seen=new Set();
    for(const item of items)for(const s of item.s){const k=JSON.stringify(s);if(!seen.has(k)){seen.add(k);senses.push({pos:posLabels[s[0]]||s[0],meaning:s[1]});}}
    results.push({word:ref,display:items[0].w,pronunciation:pronunciations.join(' · '),editorial:items.some(x=>x.editorial===true),senses});
   }
   return {query:word,results,suggestions:refs.length?[]:Object.keys(d.entries).filter(x=>x.startsWith(word.slice(0,Math.min(3,word.length)))).slice(0,5)};
  }
  return lookup;
 }
 function mount(adapter){
  const doc=adapter.document||document,$=id=>doc.getElementById(id),lookup=createLookup(adapter.fetch||fetch);
  let searchRequest=0,current=[];
  $('personalWordbook')?.remove();
  for(const item of doc.querySelectorAll('[data-public-page="dictionary"]'))item.textContent='영단어 찾기';
  if($('dictionaryHeading'))$('dictionaryHeading').textContent='영단어 찾기';
  const description=doc.querySelector('#homeDictionary .dictionary-description');if(description)description.textContent='궁금한 영어 단어의 뜻·품사·발음기호를 찾아보세요.';
  function node(tag,text,cls){const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
  function errorText(e){return e?.name==='AbortError'?'연결이 지연되고 있습니다. 다시 찾아 주세요.':e?.message||'처리하지 못했습니다. 다시 시도해 주세요.';}
  function renderResults(result){
   const list=$('dictionaryResults');list.replaceChildren();current=result.results;
   if(!current.length){$('dictionaryStatus').textContent='이 사전에 등록되지 않은 단어입니다. 철자나 기본형을 확인해 주세요.';
    if(result.suggestions.length){const box=node('div','비슷한 시작의 단어: ','dictionary-actions');for(const word of result.suggestions){const b=node('button',word,'secondary');b.type='button';b.addEventListener('click',()=>{$('dictionaryWord').value=word;void search();});box.append(b);}list.append(box);}return;}
   $('dictionaryStatus').textContent=result.query===current[0].word?'뜻을 찾았습니다.':'「'+result.query+'」의 기본형 뜻입니다.';
   for(const entry of current){const card=node('article',undefined,'dictionary-card');card.append(node('h3',entry.display));card.append(node('p','뜻 '+entry.senses.length+'개'+(entry.editorial?' · 청라 학습용 대표 뜻':''),'dictionary-source-note'));if(entry.pronunciation)card.append(node('p',entry.pronunciation,'dictionary-pronunciation'));
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
  function accountChanged(){}
  $('dictionaryForm').addEventListener('submit',e=>{e.preventDefault();void search();});
  $('dictionaryClear').addEventListener('click',()=>{searchRequest++;$('dictionaryResultsWrap').hidden=true;$('dictionaryResults').replaceChildren();$('dictionaryStatus').textContent='';$('dictionarySearchButton').disabled=false;current=[];});
  return {accountChanged,search};
 }
 globalThis.CheonglaDictionaryFactory={mount,createLookup,normalize,valid};
 if(typeof module!=='undefined'&&module.exports)module.exports={createLookup,normalize,valid,mount};
})();
