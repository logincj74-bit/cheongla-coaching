const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class N{constructor(){this.value='';this.type='password';this.events={};}addEventListener(k,f){this.events[k]=f;}reportValidity(){return true;}setAttribute(){}}
const nodes={},$=id=>nodes[id]??=new N(),document={getElementById:$},ctx=vm.createContext({document});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../auth-methods.js'),'utf8'),ctx);
let profile={id:'member'},calls=[],success=true,clears=0,homes=0,messages=[],logout=0;
const ui=ctx.CheonglaAuth.mountPasswordChange({document,profile:()=>profile,
 pairError:(a,b)=>a.length<8?'too short':a!==b?'mismatch':'',
 call:async args=>{calls.push(args);if(!success)throw Error('wrong current password');return{ok:true};},
 client:async()=>({auth:{signOut:async()=>{logout++;}}}),clear:()=>{clears++;},home:()=>{homes++;},message:s=>messages.push(s),readable:e=>e.message});
const submit=()=>$('passwordChangeForm').events.submit({preventDefault(){}});
function values(){for(const [id,value]of Object.entries({currentPassword:'oldPassword!',newPassword:'newPassword!',newPasswordConfirm:'newPassword!'}))$(id).value=value;}
(async()=>{
 values();$('newPasswordConfirm').value='bad';await submit();assert.equal(calls.length,0);
 values();$('newPassword').value='oldPassword!';$('newPasswordConfirm').value='oldPassword!';await submit();assert.equal(calls.length,0);
 values();success=false;await submit();assert.equal(calls.length,1);assert.equal(logout,0);assert.equal($('passwordChangeStatus').textContent,'wrong current password');assert.equal($('currentPassword').value,'');
 values();success=true;await Promise.all([submit(),submit()]);assert.equal(calls.length,2);assert.equal(calls[1].action,'change');assert.equal(logout,1);assert.equal(clears,1);assert.equal(homes,1);assert(messages[0].includes('다시 로그인'));assert.equal($('newPassword').value,'');
 values();ui.reset();assert.equal($('newPasswordConfirm').value,'');assert.equal($('passwordChangeDetails').open,false);
 profile=null;values();await submit();assert.equal(calls.length,2);
 console.log('PASS self password UI: mismatch/reuse rejection, error handling, double-submit guard, secret clearing, signout and logged-out denial');
})().catch(e=>{console.error(e);process.exit(1);});
