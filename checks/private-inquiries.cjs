const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const h=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
class N{constructor(){this.events={};this.value='';this.children=[];}addEventListener(k,f){this.events[k]=f;}reset(){$('newInquiryVisibility').value='private';}replaceChildren(){this.children=[];}append(...x){this.children.push(...x);}setAttribute(k,v){this[k]=v;}}
const nodes={},$=id=>nodes[id]??=new N(),calls=[];let fail=false;
const c=vm.createContext({$,crypto:require('node:crypto').webcrypto,currentProfile:null,appConfirm:()=>true,readable:e=>e.message,localStorage:{getItem:()=>null,setItem(){}},getClient:async()=>({rpc:async(name,args)=>{calls.push({name,args});return fail?{error:{message:'저장 실패'}}:{data:name==='cheongla_list_new_inquiries'?{can_manage:false,items:[]}:'id'};}}),showSiteHome(){},appendOfficialContacts(){},document:{createElement:()=>new N()},tuitionText:(box,text)=>box.append({text})});
vm.runInContext(h.slice(h.indexOf('let newInquiryRequest='),h.indexOf('let boardRequest=')),c);
(async()=>{
 assert(!h.includes('id="newInquiryPin"')&&!h.includes('id="boardPin"'));
 assert(h.includes('이 화면에서는 접수한 비공개 상담을 다시 조회할 수 없습니다.'));
 $('newInquiryVisibility').value='private';$('newInquiryConsent').checked=false;
 await $('newInquiryForm').events.submit({preventDefault(){}});assert.equal(calls.length,0);
 $('newInquiryConsent').checked=true;await $('newInquiryForm').events.submit({preventDefault(){}});
 assert.equal(calls[0].name,'cheongla_submit_new_inquiry_secure');assert.equal(calls[0].args.private_pin,null);assert.equal(calls[0].args.inquiry_visibility,'private');assert($('newInquirySubmitStatus').textContent.includes('연락처로 개별 회신'));
 $('newInquiryVisibility').value='public';fail=true;await $('newInquiryForm').events.submit({preventDefault(){}});
 assert.equal(calls.at(-1).args.private_pin,null);assert.equal(calls.at(-1).args.inquiry_visibility,'public');assert.equal($('newInquirySubmitStatus').textContent,'저장 실패');assert.equal($('submitNewInquiry').disabled,false);
 console.log('PASS no unused PIN controls; private submission, consent/public visibility, individual-reply guidance and error recovery');
})().catch(e=>{console.error(e);process.exit(1)});
