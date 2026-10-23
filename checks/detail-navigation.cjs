const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const frames=[],events={},calls=[];
const document={addEventListener:(name,fn)=>events[name]=fn};
const c=vm.createContext({document,requestAnimationFrame:fn=>frames.push(fn)});
vm.runInContext(fs.readFileSync(require('path').join(__dirname,'../detail-navigation.js'),'utf8'),c);
function item(name,site=false){const d={tagName:'DETAILS',open:false,classList:{contains:s=>site&&s==='site-menu'}};const summary={tagName:'SUMMARY',parentElement:d,isConnected:true,contains:x=>x===summary,scrollIntoView:o=>calls.push({name,open:d.open,otherOpen:parent.children.filter(x=>x!==d).some(x=>x.open),o}),closest:s=>s==='summary'?summary:null};d.querySelector=()=>summary;return {d,summary};}
const parent={children:[]},a=item('previous'),b=item('selected'),z=item('rapid');parent.children=[a.d,b.d,z.d];for(const d of parent.children)d.parentElement=parent;
function click(summary){let prevented=false;events.click({target:summary,button:0,preventDefault(){prevented=true}});return prevented;}
function flush(){while(frames.length)frames.shift()();}
a.d.open=true;assert(click(b.summary));assert(!a.d.open&&b.d.open);assert.equal(calls.length,0);flush();assert.equal(calls.at(-1).name,'selected');assert.equal(calls.at(-1).otherOpen,false);assert.equal(calls.at(-1).o.block,'start');assert.equal(calls.at(-1).o.behavior,'instant');
assert(click(b.summary));flush();assert(!b.d.open);assert.equal(calls.length,1);
click(a.summary);click(z.summary);flush();assert.equal(calls.at(-1).name,'rapid');assert.equal(calls.length,2);
const button={closest:s=>s==='summary'?z.summary:button};z.summary.contains=x=>x===button;let canceled=false;events.click({target:button,button:0,preventDefault(){canceled=true}});assert(!canceled&&z.d.open);
const menu=item('main',true);assert(!click(menu.summary));
c.CheonglaDetailNavigation.open(b.d);flush();assert(b.d.open&&!z.d.open);assert.equal(calls.at(-1).name,'selected');
console.log('PASS: collapse preceding content before heading alignment; double-frame layout, rapid switching, close toggle, download button and main-menu preservation, guide hash entry');
