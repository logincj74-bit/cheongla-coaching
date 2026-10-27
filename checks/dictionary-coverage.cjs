const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createLookup,normalize,valid}=require('../dictionary.js');
const root=path.join(__dirname,'..');
const fetched=[];
async function dataFetch(url){assert(url.startsWith('assets/dictionary/'));fetched.push(url);return {ok:true,json:async()=>JSON.parse(fs.readFileSync(path.join(root,url.split('?')[0]),'utf8'))};}
(async()=>{
 const lookup=createLookup(dataFetch);
 for(const [word,meaning]of [['alternative','대안'],['available','이용'],['consistent','일관'],['contribute','기여'],['metaphor','은유'],['nevertheless','불구'],['sustainability','지속'],['likely','가능성'],['range','범위'],['particular','특정'],['due','예정'],['affect','영향'],['involve','포함'],['requirement','조건'],['photosynthesis','광합성'],['went','가다'],['children','아이'],['beautiful','아름답다']]){
  const result=await lookup(word);assert(result.results.length,word);assert(JSON.stringify(result).includes(meaning),word+' Korean sense');
 }
 for(const [word,lemma]of [['alternatives','alternative'],['contributed','contribute'],['contributing','contribute'],['studying','study'],['stopped','stop'],['tried','try'],['ANALYSED','analyse']]){
  assert((await lookup(word)).results.some(x=>x.word===lemma),word+' -> '+lemma);
 }
 assert((await lookup('alternative')).results[0].senses.length>=5);
 assert((await lookup('alternative')).results[0].senses.some(x=>x.pos==='형용사'));
 const editorial=JSON.parse(fs.readFileSync(path.join(root,'assets/dictionary/editorial-senses.json')));
 for(const word of Object.keys(editorial.entries)){const result=await lookup(word);assert(result.results[0].editorial);assert(result.results[0].senses.length>=5);}
 const custom=createLookup(dataFetch,{custom:async words=>[{word:'cheonglaword',pronunciation:'',senses:[{pos:'n.',meaning:'원장 추가 단어'}]},{word:'alternative',pronunciation:'',senses:[{pos:'n.',meaning:'원장 수정 뜻'}]}].filter(x=>words.includes(x.word))});
 assert.equal((await custom('alternative')).results[0].senses[0].meaning,'원장 수정 뜻');
 assert.equal((await custom('cheonglawords')).results[0].word,'cheonglaword');
 const serverDown=createLookup(dataFetch,{custom:async()=>{throw Error('offline')}});assert((await serverDown('alternative')).results.length);assert((await serverDown('alternative')).incomplete);await assert.rejects(()=>serverDown('cheonglaword'),/원장 등록 사전/);
 const before=fetched.length;await lookup('alternative');assert.equal(fetched.length,before,'cache repeat');
 assert.equal(normalize('  ALTERNATIVE  '),'alternative');assert(!valid('<script>'));await assert.rejects(()=>lookup('../secret'));
 assert.equal((await lookup('qzxnonexistentword')).results.length,0);
 const oneLetter=[];const small=createLookup(async url=>{oneLetter.push(url);return dataFetch(url)});await small('alternative');assert.equal(oneLetter.length,4,'base, letter supplement, editorial, coverage');
 let fail=true;const retry=createLookup(async url=>{if(fail&&url.includes('supplement/'))throw Error('network');return dataFetch(url)});
 await assert.rejects(()=>retry('alternative'),/일부 사전/,'network failure must not say missing word');fail=false;assert((await retry('alternative')).results.length);
 const partial=createLookup(async url=>{if(url.includes('/0.json'))throw Error('base offline');return dataFetch(url)});const r=await partial('alternative');assert(r.results.length&&r.incomplete);
 const all=new Set();for(let i=0;i<7;i++)for(const w of Object.keys(JSON.parse(fs.readFileSync(path.join(root,'assets/dictionary',i+'.json'))).entries))all.add(w);
 for(let c=97;c<=122;c++)for(const [w,items]of Object.entries(JSON.parse(fs.readFileSync(path.join(root,'assets/dictionary/supplement',String.fromCharCode(c)+'.json'))).entries)){
  all.add(w);assert.equal(w[0],String.fromCharCode(c));assert(valid(w));assert(items.length);for(const item of items)for(const [pos,meaning]of item.s){assert(meaning.length&&meaning.length<=600);assert(/[가-힣]/.test(meaning));assert(!/[<>]/.test(meaning));}
 }
 for(const w of Object.keys(JSON.parse(fs.readFileSync(path.join(root,'assets/dictionary/coverage-core.json'))).entries))all.add(w);assert.equal(all.size,32720);
 console.log('PASS: 32,720 unique headwords; key missing vocabulary, Korean senses, plural/past/progressive lookup, unchanged 40 editorial entries, lazy cache, retry and partial-failure handling.');
})().catch(e=>{console.error(e);process.exit(1)});
