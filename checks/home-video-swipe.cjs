const fs=require('node:fs'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html,{runScripts:'outside-only',url:'https://example.invalid'}),w=dom.window,d=w.document;
Object.defineProperty(w.navigator,'userAgent',{value:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X)'});
w.matchMedia=()=>({matches:true});w.requestAnimationFrame=fn=>w.setTimeout(fn,0);w.cancelAnimationFrame=w.clearTimeout;
w.HTMLElement.prototype.scrollTo=function(o){this.scrollLeft=o.left;};w.HTMLElement.prototype.scrollIntoView=function(){};
w.eval(`var currentProfile={role:'owner',approval_status:'approved',membership_state:'active'};var allowedAccountSection=()=>false,canUseMBTIStudy=()=>false,canUseMealForms=()=>false,canUseExams=()=>false;var configureDeskMenu=()=>{},clearAccount=()=>{},recordSiteView=()=>{};`);
w.history.replaceState({cheonglaView:{view:'home',key:'',index:1}},'');let historyMoves=0;w.history.go=()=>historyMoves++;
w.eval(fs.readFileSync('detail-navigation.js','utf8'));w.eval(fs.readFileSync('swipe-navigation.js','utf8'));w.eval(fs.readFileSync('home-video-swipe.js','utf8'));
let owner=true,busy=false,trashed=0,played=0,clock=1000;w.Date.now=()=>clock;
const api=w.CheonglaHomeVideoSwipe.mount({document:d,allowed:()=>owner,isBusy:()=>busy});
function row(title){const node=d.createElement('article'),play=d.createElement('button'),controls=d.createElement('div');play.textContent=title;play.onclick=()=>played++;node.append(play,controls);d.getElementById('homeTourSection').append(node);api.attach(node,{label:title,controls,onTrash:async()=>{trashed++;}});return{node,play,toggle:node.querySelector('.home-video-delete-toggle'),action:node.querySelector('.home-video-trash-action')};}
function touch(node,type,points){const e=new w.Event(type,{bubbles:true,cancelable:true});Object.defineProperty(e,'touches',{value:type==='touchend'?[]:points});Object.defineProperty(e,'changedTouches',{value:points});node.dispatchEvent(e);return e;}
function swipe(node,x1,y1,x2,y2){touch(node,'touchstart',[{clientX:x1,clientY:y1}]);const moved=touch(node,'touchmove',[{clientX:x2,clientY:y2}]);touch(node,'touchend',[{clientX:x2,clientY:y2}]);return moved;}
const tick=()=>new Promise(setImmediate);
(async()=>{
 const first=row('첫 영상'),second=row('둘째 영상');assert(first.action.hidden);assert.equal(first.toggle.getAttribute('aria-expanded'),'false');
 const moved=swipe(first.play,220,200,100,205);assert(moved.defaultPrevented);assert(!first.action.hidden&&!first.action.disabled);assert.equal(first.toggle.getAttribute('aria-expanded'),'true');assert.equal(trashed,0,'swipe itself deleted content');assert.equal(historyMoves,0);
 first.play.click();assert.equal(played,0,'swipe also launched playback');assert(first.action.hidden);clock+=500;first.play.click();assert.equal(played,1);
 swipe(first.play,90,200,220,205);assert(first.action.hidden);assert.equal(historyMoves,0,'local right gesture navigated app history');
 const vertical=swipe(first.play,150,100,165,350);assert(!vertical.defaultPrevented);assert(first.action.hidden);
 swipe(first.play,200,200,191,202);assert(first.action.hidden,'tap opened a delete menu');swipe(first.play,10,200,-80,205);assert(first.action.hidden,'browser edge gesture opened deletion');
 touch(first.play,'touchstart',[{clientX:200,clientY:200},{clientX:220,clientY:200}]);touch(first.play,'touchmove',[{clientX:100,clientY:200}]);touch(first.play,'touchend',[{clientX:100,clientY:200}]);assert(first.action.hidden,'pinch opened deletion');
 touch(first.play,'touchstart',[{clientX:200,clientY:200}]);touch(first.play,'touchmove',[{clientX:130,clientY:200}]);touch(first.play,'touchcancel',[]);assert(first.action.hidden);assert.equal(first.node.style.getPropertyValue('--home-video-delete-offset'),'0px');
 first.toggle.click();assert(!first.action.hidden);second.toggle.click();assert(first.action.hidden&&!second.action.hidden,'multiple delete menus remained open');
 second.toggle.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));assert(second.action.hidden);assert.equal(d.activeElement,second.toggle);
 first.toggle.click();d.getElementById('siteStatus').click();assert(first.action.hidden,'outside click did not close deletion');
 first.toggle.click();swipe(first.play,90,200,200,205);assert(first.action.hidden,'right swipe did not close deletion');
 second.toggle.click();second.action.click();await tick();assert.equal(trashed,1);assert(second.action.hidden);
 busy=true;const duringSave=row('저장 중 생성된 카드');busy=false;duringSave.toggle.click();assert(!duringSave.action.hidden&&!duringSave.action.disabled,'refresh during a save lost the swipe binding');
 owner=false;duringSave.action.click();await tick();assert.equal(trashed,1,'viewer deleted via retained button');api.reset();assert(!d.querySelector('[data-home-video-swipe]'));assert(!d.querySelector('.home-video-trash-action'));assert(first.play.isConnected,'reset removed video content');
 owner=true;const outside=d.createElement('p');outside.textContent='일반 화면';d.getElementById('homePanel').append(outside);swipe(outside,90,200,220,205);await tick();assert.equal(historyMoves,1,'normal app back gesture stopped working');dom.window.close();
 const desktop=new JSDOM('<article><button>영상</button><div></div></article>',{runScripts:'outside-only'}),dw=desktop.window;dw.eval(fs.readFileSync('home-video-swipe.js','utf8'));let desktopDeletes=0;const dc=dw.document.querySelector('article'),dui=dw.CheonglaHomeVideoSwipe.mount({document:dw.document,allowed:()=>true});dui.attach(dc,{label:'영상',controls:dc.querySelector('div'),onTrash:async()=>desktopDeletes++});assert(!dc.hasAttribute('data-home-video-swipe'));assert(dc.querySelector('.home-video-trash-inline'));dc.querySelector('.home-video-trash-inline').click();await tick();assert.equal(desktopDeletes,1);dui.reset();desktop.window.close();
 console.log('PASS local swipe-to-trash: mobile reveal only, explicit button activation, playback suppression, right/vertical/tap/pinch/cancel/edge behavior, exclusive opening, keyboard/outside close, stale-role rejection, busy refresh rebinding, desktop button and app-history gesture isolation (touch events simulated)');
})().catch(e=>{console.error(e);dom.window.close();process.exit(1)});
