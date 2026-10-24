import assert from 'node:assert/strict';import fs from 'node:fs';
import {SEASONS,seasonForDate,particleSettings,skipSeasonWelcome,mountSeasonalUI,autumnParticle} from '../seasonal.js';
for(const [iso,season] of [['2026-02-28T14:59:59Z','winter'],['2026-02-28T15:00:00Z','spring'],['2026-05-31T15:00:00Z','summer'],['2026-08-31T15:00:00Z','autumn'],['2026-11-30T15:00:00Z','winter']])assert.equal(seasonForDate(new Date(iso)),season);
for(const season of Object.keys(SEASONS))for(let i=0;i<22;i++){const p=particleSettings(i,season);assert.ok(parseFloat(p.duration)>=14);assert.ok(parseFloat(p.x)>=0&&parseFloat(p.x)<=100);assert.ok(parseFloat(p.opacity)<=1);}
assert.equal(skipSeasonWelcome('https://example.com/?push=1'),true);assert.equal(skipSeasonWelcome('https://example.com/?page=resources'),true);assert.equal(skipSeasonWelcome('https://example.com/#access_token=test'),true);assert.equal(skipSeasonWelcome('https://example.com/'),false);
function element(){return {dataset:{},handlers:{},children:[],style:{setProperty(){}},textContent:'',setAttribute(k,v){this[k]=v;},replaceChildren(){this.children=[];},append(n){this.children.push(n);},addEventListener(k,fn){this.handlers[k]=fn;},focus(){this.focused=true;}};}
function fixture({reduced=false,savedOff=false,url='https://example.com/',blocked=false,noOpen=false}={}){
 const dialog=element(),brand=element(),open=element(),start=element(),logo=element(),button1=element(),button2=element(),bodyClass=new Set(),local=new Map(),session=new Map();
 if(savedOff)local.set('cheongla-season-motion','off');
 for(const surface of [dialog,brand]){surface.layer=element();surface.copy={label:element(),headline:element(),description:element()};surface.querySelector=()=>surface.layer;surface.querySelectorAll=s=>{const k=s.match(/data-season-(\w+)/)?.[1];return k?[surface.copy[k]]:[];};}
 const doc={hidden:false,body:{classList:{add:k=>bodyClass.add(k),remove:k=>bodyClass.delete(k)}},handlers:{},getElementById:id=>({seasonWelcome:dialog,seasonWelcomeOpen:noOpen?null:open,seasonWelcomeStart:start,siteHomeLogo:logo})[id],querySelector:()=>dialog.open?dialog:null,querySelectorAll:s=>s==='[data-season-surface]'?[brand,dialog]:[button1,button2],createElement:element,addEventListener(k,f){this.handlers[k]=f;}};
 dialog.showModal=()=>dialog.open=true;dialog.close=()=>{dialog.open=false;dialog.handlers.close();};
 const media={matches:reduced,addEventListener(k,f){this.changed=f;}};
 const storage=map=>({getItem(k){if(blocked)throw Error('blocked');return map.get(k)||null;},setItem(k,v){if(blocked)throw Error('blocked');map.set(k,v);}});
 const win={matchMedia:()=>media,localStorage:storage(local),sessionStorage:storage(session),handlers:{},location:{href:url},performance:{getEntriesByType:()=>[{name:url}]},setInterval(){},addEventListener(k,f){this.handlers[k]=f;}};
 mountSeasonalUI(doc,win);return {doc,win,brand,dialog,open,start,logo,button1,media,session,bodyClass};
}
let f=fixture();assert.equal(f.dialog.open,true);assert.equal(f.dialog.layer.children.length,22);assert.equal(f.brand.layer.children.length,20);assert.equal(f.brand.dataset.paused,'true');f.start.handlers.click();assert.equal(f.dialog.open,false);assert.equal(f.bodyClass.size,0);assert.equal(f.logo.focused,true);assert.equal(f.session.size,1);f.open.handlers.click();assert.equal(f.dialog.open,true);f.dialog.close();assert.equal(f.open.focused,true);f.button1.handlers.click();assert.equal(f.brand.dataset.motion,'off');assert.equal(f.brand.layer.children.length,0);f.button1.handlers.click();assert.equal(f.brand.dataset.motion,'on');f.doc.hidden=true;f.doc.handlers.visibilitychange();assert.equal(f.brand.dataset.paused,'true');f.doc.hidden=false;f.doc.handlers.visibilitychange();assert.equal(f.brand.dataset.paused,'false');
f=fixture({reduced:true});assert.equal(f.brand.layer.children.length,0);assert.equal(f.button1.disabled,true);assert.equal(f.brand.dataset.motion,'off');f.media.matches=false;f.media.changed();assert.equal(f.brand.layer.children.length,20);
f=fixture({savedOff:true});assert.equal(f.brand.layer.children.length,0);
f=fixture({url:'https://example.com/?page=resources'});assert.ok(!f.dialog.open);assert.equal(f.brand.layer.children.length,20);
f=fixture({noOpen:true});assert.equal(f.dialog.open,true);f.start.handlers.click();assert.equal(f.dialog.open,false);
f=fixture({blocked:true});assert.equal(f.dialog.open,true);f.start.handlers.click();assert.equal(f.bodyClass.size,0);
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');assert.equal((html.match(/id="seasonWelcome"/g)||[]).length,1);assert.match(html,/id="seasonWelcomeStart"[^>]*autofocus/);assert.ok(html.indexOf('class="home-today"')<html.indexOf('id="homeSeasonEffects"'));assert.match(fs.readFileSync(new URL('../seasonal.css',import.meta.url),'utf8'),/prefers-reduced-motion:reduce/);
console.log('PASS seasonal welcome: Korea season boundaries, all four effects, entry skip, start/reopen, saved choice, reduced motion, hidden-page pause, blocked storage and existing top clock.');

assert.ok(!html.includes('<header class="brand season-home'));assert.ok(!html.includes('id="siteHomeLogo"'));assert.match(html,/class="home-motion-controls"/);
const leaves=Array.from({length:20},(_,i)=>autumnParticle(i));assert.equal(new Set(leaves.map(x=>x.kind)).size,3);for(const x of leaves.filter(x=>x.kind==='ginkgo'))assert(['#f6c900','#eab600'].includes(x.color));
const css=fs.readFileSync(new URL('../seasonal.css',import.meta.url),'utf8');assert.match(css,/home-season-effects\{position:fixed/);assert.match(css,/z-index:12;pointer-events:none/);
console.log('PASS: full-home leaf overlay, three leaf shapes, yellow ginkgo, no identity strip, motion control retained');
