const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),{createLookup}=require('../dictionary.js');
const lists=JSON.parse(fs.readFileSync(path.join(root,'assets/dictionary/coverage-lists.json')));
const lookup=createLookup(async url=>({ok:true,json:async()=>JSON.parse(fs.readFileSync(path.join(root,url.split('?')[0])))}));
(async()=>{
 assert.equal(lists.moe2022.rows.length,3000);assert.equal(lists.moe2022.words.length,3282);
 assert.equal(lists.ngsl12.words.length,2809);assert.equal(lists.nawl12.words.length,957);
 for(const [id,list]of Object.entries(lists)){
  const missing=[];for(const word of list.words)if(!(await lookup(word)).results.length)missing.push(word);
  assert.deepEqual(missing,[],id);console.log('PASS',id,list.words.length,'searchable Korean meanings');
 }
})();
