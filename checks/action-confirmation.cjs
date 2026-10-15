const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');const h=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
class N{constructor(){this.events={};this.isConnected=true;this.children=[];this.open=false}addEventListener(k,f){(this.events[k]??=new Set()).add(f)}removeEventListener(k,f){this.events[k]?.delete(f)}emit(k,e={}){for(const f of [...this.events[k]||[]])f(e)}focus(){focused=this}showModal(){this.open=true}close(){this.open=false;this.emit('close')}append(...a){this.children.push(...a)}setAttribute(k,v){this[k]=v}}
let focused;const nodes={},$=id=>nodes[id]??=new N(),previous=new N();const ctx=vm.createContext({$,document:{activeElement:previous,createElement:()=>new N()},currentProfile:{id:'principal',role:'owner',approval_status:'approved'},Promise});
vm.runInContext(h.slice(h.indexOf('let pendingActionConfirmation='),h.indexOf('const audiences=')),ctx);
(async()=>{
 let result,mutations=0;const pending=ctx.appConfirm('정말 탈퇴하시겠습니까?').then(yes=>{result=yes;if(yes)mutations++});assert.equal($('actionConfirm').open,true);assert.equal(focused,$('actionConfirmNo'));assert.equal(result,undefined);assert.equal(mutations,0);assert.equal(await ctx.appConfirm('중복 요청'),false);$('actionConfirmNo').emit('click');await pending;assert.equal(result,false);assert.equal(mutations,0);assert.equal(focused,previous);
 const yes=ctx.appConfirm('삭제하시겠습니까?').then(ok=>{if(ok)mutations++});$('actionConfirmYes').emit('click');$('actionConfirmYes').emit('click');await yes;assert.equal(mutations,1);assert.equal($('actionConfirm').open,false);
 const esc=ctx.appConfirm('확인');let prevented=false;$('actionConfirm').emit('cancel',{preventDefault(){prevented=true}});assert.equal(await esc,false);assert(prevented);
 const changed=ctx.appConfirm('처리');ctx.currentProfile={id:'other'};$('actionConfirmYes').emit('click');assert.equal(await changed,false);
 const closed=ctx.appConfirm('처리');$('actionConfirm').close();assert.equal(await closed,false);
 const signedOut=ctx.appConfirm('처리');vm.runInContext('pendingActionConfirmation.cancel()',ctx);assert.equal(await signedOut,false);
 assert(!/\bconfirm\(/.test(h));assert(h.includes('정말 탈퇴하시겠습니까?'));assert(h.includes('id="actionConfirmYes" type="button">네'));assert(h.includes('id="actionConfirmNo" type="button" class="secondary" autofocus>아니오'));
 console.log('PASS: 네·아니오 동시 표시, 선택 전 미실행, 아니오·Esc·닫기·로그아웃 취소, 네 한 번 실행, 중복 창 및 계정 변경 차단');
})().catch(e=>{console.error(e);process.exit(1)});
