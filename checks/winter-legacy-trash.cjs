const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'../winter-school.js'),'utf8');
class Node{constructor(tag,text){this.tag=tag;this.textContent=text;this.children=[];this.disabled=false;}append(...items){this.children.push(...items);}setAttribute(){}}
const el=(tag,text)=>new Node(tag,text),calls=[];let choice=false,fail=false,refreshes=0,afterConfirm=()=>{};
const ctx=vm.createContext({currentProfile:{role:'owner'},request:1,el,
 button:(text,fn)=>{const b=el('button',text);b.click=fn;return b;},
 section:(parent,title,text)=>{const n=el('section',title);n.append(el('p',text));parent.append(n);return n;},
 isPrincipal:()=>['owner','english_director','math_director'].includes(ctx.currentProfile?.role),
 manager:()=>['owner','english_director','math_director','manager'].includes(ctx.currentProfile?.role),
 appConfirm:async()=>{afterConfirm();return choice;},leave:async()=>true,
 rpc:async(name,args)=>{calls.push({name,args});if(fail)throw Error('connection failed');},
 manage:async()=>{refreshes++;},readable:e=>e.message});
vm.runInContext(source.slice(source.indexOf(' function renderLegacy('),source.indexOf(' async function manage(')),ctx);
const row={source_id:'fixture',student_name:'검증 학생',amount:100000,deleted_at:'2026-10-21T01:00:00Z'};
function render(trash=false){const p=el('div');ctx.renderLegacy(p,[{...row,...(trash?{deleted_at:'version'}:{})}],trash);return p;}
function action(p){return p.children[0].children.find(n=>n.tag==='section').children.find(n=>n.tag==='button');}
(async()=>{
 let p=render(),b=action(p);assert.equal(b.textContent,'삭제 · 휴지통으로');await b.click();assert.equal(calls.length,0);
 choice=true;await Promise.all([b.click(),b.click()]);assert.equal(calls.length,1);assert.equal(calls[0].args.target_source_id,'fixture');assert.equal(calls[0].args.restore_record,false);assert.equal(calls[0].args.expected_deleted_at,null);assert.equal(refreshes,1);
 p=render(true);await action(p).click();assert.equal(calls[1].args.restore_record,true);assert.equal(calls[1].args.expected_deleted_at,'version');
 fail=true;p=render();await action(p).click();assert.equal(refreshes,2);assert.equal(action(p).disabled,false);assert.equal(p.children[0].children.find(n=>n.tag==='section').children.at(-1).textContent,'connection failed');fail=false;
 p=render();afterConfirm=()=>{ctx.currentProfile={role:'manager'};};await action(p).click();assert.equal(calls.length,3);afterConfirm=()=>{};
 assert.equal(action(render()),undefined);assert.equal(render(true).children.length,0);
 for(const role of ['english_director','math_director']){ctx.currentProfile={role};assert(action(render()));}
 console.log('PASS: principal delete/restore, cancellation, double-click, error display, account switch, manager denial');
})().catch(e=>{console.error(e);process.exit(1);});
