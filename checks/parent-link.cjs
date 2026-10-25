const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const h=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
class Node{constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.listeners={};this.isConnected=true;}append(...c){this.children.push(...c)}replaceChildren(){this.children=[]}setAttribute(){}addEventListener(k,f){this.listeners[k]=f}scrollIntoView(){}}
const nodes=n=>[n,...n.children.filter(x=>x instanceof Node).flatMap(nodes)];
function setup(link=true,auto=false){const actor={id:'admin'},member={id:'parent'},student={id:'student',full_name:'검증 학생'},item=new Node('details'),calls=[];
 const ctx=vm.createContext({currentProfile:actor,parentLinkJustConnected:auto?{parent:'parent',student:'student'}:null,canManageContacts:()=>true,document:{createElement:t=>new Node(t)},requestAnimationFrame:f=>f(),tuitionText:(parent,text,tag='p')=>{const n=new Node(tag);n.textContent=text;parent.append(n);return n;},normalizeContactPhone:p=>p,examFeeSMSURL:(p,t)=>'sms:'+p+'?body='+encodeURIComponent(t),copyFeeMessage:()=>{},readable:e=>e.message,getClient:async()=>({from(){return{select(){return this},eq(){return this},maybeSingle:async()=>({data:link?{student_id:'student'}:null})}},rpc:async n=>{calls.push(n);return {data:[{member_id:'parent',role:'parent',approval_status:'approved',full_name:'검증 보호자',phone:'010'+''.padStart(8,'0')}]}}})});
 vm.runInContext(h.slice(h.indexOf('function parentLinkSMSBody('),h.indexOf('async function loadNotices(')),ctx);ctx.renderParentLinkSMS(item,member,student);return{ctx,item,calls};}
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 let x=setup(true,true);await flush();assert(x.item.open);const all=nodes(x.item),a=all.find(n=>n.tagName==='A');assert(a);assert(decodeURIComponent(a.href).includes('검증 학생'));assert(decodeURIComponent(a.href).includes('검증 보호자'));assert(all.some(n=>n.textContent?.includes('전송을 눌러')));
 x=setup(false);nodes(x.item).find(n=>n.tagName==='BUTTON').listeners.click();await flush();assert(!nodes(x.item).some(n=>n.tagName==='A'));assert(nodes(x.item).some(n=>n.textContent?.includes('해제되었습니다')));
 x=setup();const button=nodes(x.item).find(n=>n.tagName==='BUTTON');x.ctx.currentProfile={id:'other'};button.listeners.click();await flush();assert.equal(x.calls.length,0);
 assert(h.includes("if(kind==='parent_link'){await loadChildren();"));assert(h.includes('renderParentLinkSMS(item,member,s)'));
 console.log('PASS fresh linked parent SMS recipient/child, immediate completion panel, native composer, revoked relation, account switch, fresh child notification route');
})().catch(e=>{console.error(e);process.exit(1)});
