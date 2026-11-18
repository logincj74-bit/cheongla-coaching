const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('index.html','utf8'),catalog=require('./mbti-fixtures.cjs').legacy();let allowed=false,calls=0,deferred;
const context=vm.createContext({currentProfile:{id:'fixture-owner'},mbtiBaseCatalog:null,mbtiTypes:Object.keys(catalog.types),canUseMBTIStudy:()=>allowed,getClient:async()=>({rpc:async name=>{assert.equal(name,'cheongla_mbti_legacy_catalog');calls++;return deferred?await deferred:{data:catalog};},from:name=>{assert.equal(name,'cheongla_mbti_guides');return{select:async()=>({data:[]})};}})});
vm.runInContext(html.slice(html.indexOf('async function fetchMBTICatalog(){'),html.indexOf('function appendMBTIGuideSection(')),context);
(async()=>{
 assert(!html.includes("fetch('assets/mbti-study-methods.json"));
 for(const p of ['assets/mbti-study-methods.json','data/mbti-library-2022.json','data/mbti-articles-2026.json','scripts/sources/mbti-intro-letter.json'])assert(!fs.existsSync(p),p+' must not be a public source file');
 await assert.rejects(context.fetchMBTICatalog(),/원장만/);assert.equal(calls,0);
 allowed=true;assert.equal(Object.keys((await context.fetchMBTICatalog()).types).length,16);
 context.mbtiBaseCatalog=null;let resolve;deferred=new Promise(r=>resolve=r);const pending=context.fetchMBTICatalog();await new Promise(setImmediate);context.currentProfile={id:'fixture-other'};allowed=false;resolve({data:catalog});await assert.rejects(pending,/로그인 상태/);assert.equal(context.mbtiBaseCatalog,null);
 assert(html.includes('mbtiCatalog=null;mbtiBaseCatalog=null;'));
 console.log('PASS legacy catalog uses authorized RPC only, no public document files, principal gate before fetch, logout cache clearing and stale-account response denial');
})().catch(e=>{console.error(e);process.exit(1)});
