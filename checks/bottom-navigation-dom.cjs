process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document,bar=d.getElementById('siteBackControls');
const vv=new w.EventTarget();Object.assign(vv,{width:390,height:844,pageTop:0,pageLeft:0,offsetTop:0,offsetLeft:0,scale:1});Object.defineProperty(w,'visualViewport',{value:vv});
Object.defineProperty(w,'innerWidth',{value:390,writable:true});Object.defineProperty(w,'innerHeight',{value:844,writable:true});Object.defineProperty(w,'scrollY',{value:0,writable:true});
let coarse=true,frames=[],seq=0;w.matchMedia=()=>({matches:coarse});w.requestAnimationFrame=fn=>(frames.push(fn),++seq);
function flush(){const pending=frames;frames=[];for(const f of pending)f();}
bar.getBoundingClientRect=()=>({height:80,width:390});bar.hidden=false;
// Simulate stale geometry retained by the previous workaround before remounting.
bar.dataset.viewportAnchored='';bar.style.top='1300px';bar.style.left='90px';bar.style.width='200px';d.querySelector('main').append(bar);
w.eval(fs.readFileSync('bottom-navigation.js','utf8'));
function fixed(){flush();assert.equal(bar.parentElement,d.body);assert(!bar.hasAttribute('data-viewport-anchored'));for(const p of ['top','left','width','bottom','transform'])assert.equal(bar.style[p],'','document geometry leaked into '+p);const css=w.getComputedStyle(bar);assert.equal(css.position,'fixed');assert.equal(css.bottom,'0px');assert.equal(css.top,'auto');assert.equal(d.documentElement.style.getPropertyValue('--nav-reserved-size'),'100px');}
const hidden=()=>bar.hasAttribute('data-keyboard-hidden');
(async()=>{
 fixed();assert(!hidden());
 // A stale visualViewport.pageTop must never pin the bar to a document paragraph.
 w.scrollY=2600;vv.pageTop=0;w.dispatchEvent(new w.Event('scroll'));vv.dispatchEvent(new w.Event('scroll'));fixed();assert(!hidden());
 Object.assign(vv,{pageTop:8000,pageLeft:70,offsetLeft:70,height:740});vv.dispatchEvent(new w.Event('resize'));fixed();assert(!hidden(),'normal browser-chrome height change hid navigation');
 d.getElementById('authPanel').hidden=false;const input=d.getElementById('password');input.focus();flush();assert(hidden());
 Object.assign(vv,{height:420,pageTop:5000,offsetTop:100});vv.dispatchEvent(new w.Event('resize'));flush();assert(hidden());
 input.blur();flush();assert(hidden(),'keyboard dismissal showed a bar in the old keyboard viewport');
 vv.height=844;vv.dispatchEvent(new w.Event('resize'));flush();assert(hidden(),'panned keyboard viewport was treated as settled');
 vv.offsetTop=0;vv.dispatchEvent(new w.Event('scroll'));fixed();assert(!hidden());
 // The color toolbar can retain focus after the editing keyboard disappears.
 const toolbar=d.createElement('div');toolbar.className='lr-document-toolbar';const color=d.createElement('button');color.textContent='빨강';toolbar.append(color);d.body.append(toolbar);color.focus();flush();assert(hidden());color.blur();fixed();assert(!hidden());toolbar.remove();
 const editor=d.createElement('div');editor.setAttribute('contenteditable','true');d.body.append(editor);editor.focus();flush();assert(hidden());editor.blur();fixed();assert(!hidden());editor.remove();
 Object.assign(vv,{scale:2,width:195,height:422});vv.dispatchEvent(new w.Event('resize'));flush();assert(hidden(),'navigation obscured pinch-zoomed reading');Object.assign(vv,{scale:1,width:390,height:844});vv.dispatchEvent(new w.Event('resize'));fixed();assert(!hidden());
 w.innerWidth=844;w.innerHeight=390;Object.assign(vv,{width:844,height:390,pageTop:600});w.dispatchEvent(new w.Event('orientationchange'));fixed();assert(!hidden(),'orientation retained portrait keyboard baseline');
 coarse=false;w.innerWidth=1280;w.innerHeight=900;Object.assign(vv,{width:1280,height:900});input.focus();flush();assert(!hidden(),'desktop input focus hid navigation');fixed();input.blur();
 assert(html.includes('viewport-fit=cover'));assert(html.includes('width:min(100%,800px)'));assert(!html.includes('position:absolute;bottom:auto;transform:none'));assert(!html.includes('body:has(#staffJournalPanel'));
 bar.hidden=true;await new Promise(setImmediate);flush();assert(bar.hidden,'history visibility was overwritten');dom.window.close();
 console.log('PASS fixed bottom navigation: stale document coordinates removed; long scrolling, delayed keyboard resize/pan recovery, color toolbar/contenteditable focus, pinch zoom, rotation, desktop input, safe-area/width CSS and history visibility (viewport metrics simulated)');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
