process.chdir(require('node:path').join(__dirname,'..'));
const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document,bar=d.getElementById('siteBackControls');
const vv=new w.EventTarget();Object.assign(vv,{width:390,height:844,pageTop:0,pageLeft:0,offsetTop:0,offsetLeft:0});Object.defineProperty(w,'visualViewport',{value:vv});
let coarse=true,frames=[],seq=0;w.matchMedia=()=>({matches:coarse});w.requestAnimationFrame=fn=>(frames.push(fn),++seq);
function flush(){const pending=frames;frames=[];for(const f of pending)f();}
bar.getBoundingClientRect=()=>({height:80,width:parseFloat(bar.style.width)||390});bar.hidden=false;
w.eval(fs.readFileSync('bottom-navigation.js','utf8'));
function check(top,width=390,left=0){flush();assert.equal(parseFloat(bar.style.top),top);assert.equal(parseFloat(bar.style.width),width);assert.equal(parseFloat(bar.style.left),left);assert.equal(d.documentElement.style.getPropertyValue('--nav-reserved-size'),'100px');}
(async()=>{
 assert.equal(bar.parentElement,d.body);check(764);
 vv.pageTop=1300;w.dispatchEvent(new w.Event('scroll'));check(2064);
 vv.height=600;vv.dispatchEvent(new w.Event('resize'));check(1820);
 Object.assign(vv,{width:844,height:390,pageTop:600});w.dispatchEvent(new w.Event('orientationchange'));check(910,800,22);
 Object.assign(vv,{width:390,height:500,offsetTop:100,pageTop:900});vv.dispatchEvent(new w.Event('scroll'));check(1320);
 const input=d.getElementById('password');d.getElementById('authPanel').hidden=false;input.focus();flush();assert(bar.hasAttribute('data-keyboard-hidden'));
 input.blur();Object.assign(vv,{width:390,height:844,offsetTop:0,pageTop:0});vv.dispatchEvent(new w.Event('resize'));check(764);assert(!bar.hasAttribute('data-keyboard-hidden'));
 coarse=false;input.focus();flush();assert(!bar.hasAttribute('data-keyboard-hidden'),'desktop focus should not hide bar');input.blur();
 Object.assign(vv,{width:1280,height:900,pageTop:0});w.dispatchEvent(new w.Event('resize'));check(820,800,240);
 assert(html.includes('viewport-fit=cover'));assert(html.includes('#siteBackControls[data-viewport-anchored]{position:absolute;bottom:auto;transform:none}'));
 bar.hidden=true;await new Promise(setImmediate);flush();assert(bar.hidden,'navigation state must remain owned by existing history logic');
 dom.window.close();console.log('PASS bottom navigation: direct body placement, visible-viewport coordinates, scrolling/orientation/offset changes, touch keyboard hide/restore, desktop focus, width cap and hidden-state preservation');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
