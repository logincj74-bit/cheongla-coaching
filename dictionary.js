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
  let owner=null,epoch=0,searchRequest=0,bookRequest=0,bookRows=[],bookLimit=50,hasMore=false,saved=new Set(),saveBusy=false,bookBusy=false,current=[];
  const profile=()=>adapter.profile(),eligible=()=>{const p=profile();return !!p&&p.approval_status==='approved'&&p.membership_state==='active';};
  function active(user,version){return eligible()&&profile().id===user&&epoch===version;}
  function node(tag,text,cls){const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
  function errorText(e){return e?.name==='AbortError'?'연결이 지연되고 있습니다. 다시 찾아 주세요.':e?.message||'처리하지 못했습니다. 다시 시도해 주세요.';}
  function controls(){
   for(const b of $('dictionaryResults').querySelectorAll('[data-save-word]')){const exists=saved.has(b.dataset.saveWord);b.disabled=!eligible()||saveBusy||exists;b.textContent=exists?'✓ 저장됨':'내 단어장에 저장';}
   $('wordbookReload').disabled=!eligible()||bookBusy;$('wordbookMore').disabled=!eligible()||bookBusy;
  }
  function meaningOf(entry){return entry.senses.map(s=>(s.pos?'['+s.pos+'] ':'')+s.meaning).join('\n').slice(0,8000);}
  function renderResults(result){
   const list=$('dictionaryResults');list.replaceChildren();current=result.results;
   if(!current.length){$('dictionaryStatus').textContent='이 사전에 등록되지 않은 단어입니다. 철자나 기본형을 확인해 주세요.';
    if(result.suggestions.length){const box=node('div','비슷한 시작의 단어: ','dictionary-actions');for(const word of result.suggestions){const b=node('button',word,'secondary');b.type='button';b.addEventListener('click',()=>{$('dictionaryWord').value=word;void search();});box.append(b);}list.append(box);}return;}
   $('dictionaryStatus').textContent=result.query===current[0].word?'뜻을 찾았습니다.':'「'+result.query+'」의 기본형 뜻입니다.';
   for(const entry of current){const card=node('article',undefined,'dictionary-card');card.append(node('h3',entry.display));card.append(node('p','뜻 '+entry.senses.length+'개'+(entry.editorial?' · 청라 학습용 대표 뜻':''),'dictionary-source-note'));if(entry.pronunciation)card.append(node('p',entry.pronunciation,'dictionary-pronunciation'));
    const senses=node('ol',undefined,'dictionary-senses');for(const sense of entry.senses){const li=node('li');if(sense.pos)li.append(node('span',sense.pos,'dictionary-pos'));li.append(node('span',sense.meaning));senses.append(li);}card.append(senses);
    const b=node('button','내 단어장에 저장');b.type='button';b.dataset.saveWord=entry.word;b.addEventListener('click',()=>void save(entry));card.append(b);list.append(card);}
   if(!eligible())list.append(node('p','단어장 저장은 로그인하고 학원 이용 승인을 받은 후 사용할 수 있습니다.','dictionary-help'));controls();
  }
  async function search(){
   const request=++searchRequest,value=$('dictionaryWord').value;
   if(!valid(normalize(value))){$('dictionaryResultsWrap').hidden=true;$('dictionaryResults').replaceChildren();current=[];$('dictionaryStatus').textContent='영어 단어나 짧은 표현을 입력해 주세요. (최대 80자)';$('dictionaryWord').focus();return;}
   $('dictionaryResultsWrap').hidden=false;$('dictionaryResults').replaceChildren();$('dictionaryStatus').textContent='단어 뜻을 찾는 중…';$('dictionarySearchButton').disabled=true;
   try{const result=await lookup(value);if(request!==searchRequest)return;renderResults(result);}
   catch(e){if(request===searchRequest)$('dictionaryStatus').textContent=errorText(e);}
   finally{if(request===searchRequest)$('dictionarySearchButton').disabled=false;}
  }
  async function save(entry){
   if(!eligible()||saveBusy)return;const user=profile().id,version=epoch;saveBusy=true;controls();$('dictionaryStatus').textContent='내 단어장에 저장 중…';
   try{const c=await adapter.client();if(!active(user,version))return;
    const r=await c.from('cheongla_wordbook').upsert({user_id:user,word:entry.word,meaning:meaningOf(entry),pronunciation:entry.pronunciation.slice(0,200)},{onConflict:'user_id,word',ignoreDuplicates:true});if(r.error)throw r.error;if(!active(user,version))return;
    const check=await c.from('cheongla_wordbook').select('word').eq('user_id',user).eq('word',entry.word).maybeSingle();if(check.error)throw check.error;if(!active(user,version))return;if(!check.data)throw Error('저장 결과를 확인하지 못했습니다. 단어장을 새로고침해 주세요.');
    saved.add(entry.word);$('dictionaryStatus').textContent='「'+entry.display+'」을 내 단어장에 저장했습니다.';if($('personalWordbook').open)await loadBook();
   }catch(e){if(active(user,version))$('dictionaryStatus').textContent=errorText(e);}
   finally{if(epoch===version){saveBusy=false;controls();}}
  }
  function renderBook(){
   const q=$('wordbookSearch').value.trim().toLowerCase(),rows=bookRows.filter(x=>[x.word,x.meaning].some(t=>t.toLowerCase().includes(q))),list=$('wordbookList');list.replaceChildren();
   for(const row of rows){const li=node('li',undefined,'dictionary-card'),header=node('div',undefined,'dictionary-actions'),title=node('h3',row.word);header.append(title);header.append(node('span',row.learned?'외운 단어':'복습할 단어','wordbook-state'+(row.learned?' is-learned':'')));
    const remove=node('button','삭제','text-button');remove.type='button';remove.disabled=bookBusy;remove.setAttribute('aria-label',row.word+' 단어장 삭제');remove.addEventListener('click',()=>void removeWord(row));header.append(remove);li.append(header);const toggle=node('button',row.learned?'다시 복습하기':'외운 단어로 표시','secondary');toggle.type='button';toggle.disabled=bookBusy;toggle.setAttribute('aria-label',row.word+' '+(row.learned?'다시 복습하기':'외운 단어로 표시'));toggle.addEventListener('click',()=>void setLearned(row));li.append(toggle);if(row.pronunciation)li.append(node('p',row.pronunciation,'dictionary-pronunciation'));li.append(node('p',row.meaning,'dictionary-meaning'));list.append(li);}
   if(!rows.length)list.append(node('li',q?'불러온 단어 중 검색 결과가 없습니다.':$('wordbookFilter').value==='all'?'아직 저장한 단어가 없습니다. 위에서 단어를 찾아 저장해 보세요.':'이 학습 상태에 해당하는 단어가 없습니다.','dictionary-help'));
   $('wordbookCount').textContent='불러온 단어 '+bookRows.length+'개'+(q?' · 검색 결과 '+rows.length+'개':'');$('wordbookMore').hidden=!hasMore;controls();
  }
  async function loadBook(){
   if(!eligible())return;const user=profile().id,version=epoch,request=++bookRequest;bookBusy=true;controls();$('wordbookStatus').textContent='내 단어장 확인 중…';
   try{const c=await adapter.client();if(!active(user,version))return;let query=c.from('cheongla_wordbook').select('word,meaning,pronunciation,created_at,learned').eq('user_id',user);const filter=$('wordbookFilter').value;if(filter==='review'||filter==='learned')query=query.eq('learned',filter==='learned');const r=await query.order('created_at',{ascending:false}).order('word').limit(bookLimit+1);if(r.error)throw r.error;if(!active(user,version)||request!==bookRequest)return;
    bookRows=(r.data||[]).slice(0,bookLimit);hasMore=(r.data||[]).length>bookLimit;saved=new Set(bookRows.map(x=>x.word));renderBook();$('wordbookStatus').textContent=hasMore?'검색은 불러온 단어에 적용됩니다. 더 보기를 눌러 나머지 단어를 확인하세요.':'';return true;
   }catch(e){if(active(user,version)&&request===bookRequest)$('wordbookStatus').textContent=errorText(e);return false;}
   finally{if(epoch===version&&request===bookRequest){bookBusy=false;renderBook();}}
  }
  async function setLearned(row){
   if(!eligible()||bookBusy)return;const user=profile().id,version=epoch,target=!row.learned;bookBusy=true;renderBook();$('wordbookStatus').textContent='학습 상태 저장 중…';
   try{const c=await adapter.client();if(!active(user,version))return;const r=await c.from('cheongla_wordbook').update({learned:target}).eq('user_id',user).eq('word',row.word).select('word,learned');if(r.error)throw r.error;if(!active(user,version))return;if(!r.data?.some(x=>x.word===row.word&&x.learned===target))throw Error('저장 결과를 확인하지 못했습니다. 단어장을 새로고침해 주세요.');
    row.learned=target;bookBusy=false;const refreshed=await loadBook();if(active(user,version))$('wordbookStatus').textContent=refreshed?(target?'외운 단어로 표시했습니다.':'복습할 단어로 옮겼습니다.'):'상태는 저장되었습니다. 목록을 새로고침해 주세요.';
   }catch(e){if(active(user,version))$('wordbookStatus').textContent=errorText(e);}
   finally{if(epoch===version){bookBusy=false;renderBook();}}
  }
  async function removeWord(row){
   if(!eligible()||bookBusy)return;const user=profile().id,version=epoch;if(!await adapter.confirm('「'+row.word+'」을 내 단어장에서 삭제할까요?\n사전 검색에서 다시 저장할 수 있습니다.','단어장 삭제'))return;if(!active(user,version)||bookBusy)return;
   bookBusy=true;renderBook();$('wordbookStatus').textContent='단어장에서 삭제 중…';
   try{const c=await adapter.client();if(!active(user,version))return;const r=await c.from('cheongla_wordbook').delete().eq('user_id',user).eq('word',row.word).select('word');if(r.error)throw r.error;if(!active(user,version))return;
    if(!r.data?.some(x=>x.word===row.word))throw Error('삭제 결과를 확인하지 못했습니다. 단어장을 새로고침해 주세요.');saved.delete(row.word);bookRows=bookRows.filter(x=>x.word!==row.word);bookBusy=false;const refreshed=await loadBook();if(active(user,version))$('wordbookStatus').textContent=refreshed?'단어장에서 삭제했습니다.':'삭제는 완료되었습니다. 목록을 새로고침해 주세요. '+$('wordbookStatus').textContent;
   }catch(e){if(active(user,version))$('wordbookStatus').textContent=errorText(e);}
   finally{if(epoch===version){bookBusy=false;renderBook();}}
  }
  function accountChanged(){
   const id=eligible()?profile().id:null;if(id===owner){controls();return;}owner=id;epoch++;bookRequest++;bookRows=[];saved=new Set();bookLimit=50;hasMore=false;bookBusy=false;saveBusy=false;$('wordbookFilter').value='all';$('wordbookSearch').value='';$('wordbookList').replaceChildren();$('wordbookCount').textContent='';$('wordbookMore').hidden=true;$('wordbookStatus').textContent=id?'':'로그인과 학원 이용 승인 후 내 단어장을 사용할 수 있습니다.';$('wordbookControls').hidden=!id;
   // Do not retain another account's saved indicators or displayed wordbook.
   controls();if(current.length)renderResults({query:normalize($('dictionaryWord').value),results:current,suggestions:[]});if(id&&$('personalWordbook').open)void loadBook();
  }
  $('dictionaryForm').addEventListener('submit',e=>{e.preventDefault();void search();});
  $('dictionaryClear').addEventListener('click',()=>{searchRequest++;$('dictionaryResultsWrap').hidden=true;$('dictionaryResults').replaceChildren();$('dictionaryStatus').textContent='';$('dictionarySearchButton').disabled=false;current=[];});
  $('wordbookFilter').addEventListener('change',()=>{bookLimit=50;bookRows=[];renderBook();void loadBook();});
  $('wordbookReload').addEventListener('click',()=>void loadBook());$('wordbookMore').addEventListener('click',()=>{bookLimit+=50;void loadBook();});$('wordbookSearch').addEventListener('input',renderBook);
  $('personalWordbook').addEventListener('toggle',()=>{if($('personalWordbook').open)void loadBook();});
  accountChanged();return {accountChanged,search,loadBook,save,removeWord,setLearned};
 }
 globalThis.CheonglaDictionaryFactory={mount,createLookup,normalize,valid};
 if(typeof module!=='undefined'&&module.exports)module.exports={createLookup,normalize,valid,mount};
})();
