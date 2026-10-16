const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');const crypto=require('node:crypto').webcrypto;
const source=fs.readFileSync(path.join(__dirname,'../supabase/functions/cheongla-account-recovery/index.ts'),'utf8');
const c=vm.createContext({crypto,fetch,TextEncoder,Uint8Array,Uint32Array,Array,JSON,Date,Request,Response,AbortSignal});vm.runInContext(source.replace('export function ','function '),c);
const vars={SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'server-test-only',SOLAPI_API_KEY:'provider-test-key',SOLAPI_API_SECRET:'provider-test-secret',SOLAPI_SENDER:'01012345678',RECOVERY_OTP_SECRET:'test-only-strong-random-pepper-123456789'};
let records=new Map(),calls=[],sms=[],providerOK=true,eligible=true;
const response=(d,status=200)=>new Response(JSON.stringify(d),{status});
async function network(url,o){const a=JSON.parse(o.body);calls.push({url,a});if(url.startsWith('https://api.solapi.com/')){sms.push(a.messages[0]);return response({groupInfo:{count:{registeredSuccess:providerOK?1:0}},failedMessageList:providerOK?[]:[{}]});}const op=url.split('/').at(-1);
 if(['cheongla_recovery_issue','cheongla_signup_issue'].includes(op)){records.set(a.challenge,{...a,recovery_purpose:a.recovery_purpose||'signup',sent:false,used:false,verified:false});return response({eligible});}
 const r=records.get(a.challenge);
 if(op==='cheongla_recovery_sent'){r.sent=a.accepted;return response(null);}
 if(['cheongla_recovery_verify','cheongla_signup_verify'].includes(op)){if(!r?.sent||r.used||r.verified||r.code_hash!==a.code_hash||!eligible)return response({ok:false});r.verified=true;r.ticket_hash=a.ticket_hash;return response({ok:true,purpose:r.recovery_purpose,emails:['student@example.invalid']});}
 if(op==='cheongla_recovery_consume'){if(!r?.verified||r.used||r.ticket_hash!==a.ticket_hash)return response(null);r.used=true;return response('00000000-0000-0000-0000-000000000001');}
 if(url.includes('/auth/v1/admin/users/'))return response({user:{id:'test'}});
 throw Error('unexpected request');}
const handler=c.createRecoveryHandler({get:k=>vars[k]},network,crypto);
async function send(body,origin='https://logincj74-bit.github.io'){const r=await handler(new Request('https://db.example/functions/v1/cheongla-account-recovery',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
(async()=>{
 const off=c.createRecoveryHandler({get:k=>['SOLAPI_API_KEY','SOLAPI_API_SECRET'].includes(k)?undefined:vars[k]},()=>{throw Error('must not call')},crypto);let r=await off(new Request('https://db.example',{method:'POST',body:'{"action":"status"}'}));assert.deepEqual(await r.json(),{ready:false});r=await off(new Request('https://db.example',{method:'POST',body:'{"action":"request"}'}));assert.equal(r.status,503);assert.equal((await r.json()).code,'SMS_NOT_CONFIGURED');
 assert.equal((await send({action:'request'},'https://hostile.example')).status,403);
 for(const purpose of ['find_id','reset_password','signup']){
 let a=await send({action:'request',purpose,phone:'010-1234-5678',email:'student@example.invalid'});assert.equal(a.status,200);assert.equal(a.body.expires_in,300);assert(!JSON.stringify(a.body).includes('student@'));assert(!('code'in a.body));const id=a.body.challenge,code=sms.at(-1).text.match(/\[(\d{6})\]/)[1];assert(!JSON.stringify(records.get(id)).includes(code));
 assert.equal((await send({action:'verify',purpose,challenge:id,code:code==='000000'?'999999':'000000'})).status,400);
 const verified=await send({action:'verify',purpose,challenge:id,code});assert.equal(verified.status,200);assert.equal((await send({action:'verify',purpose,challenge:id,code})).status,400);
 if(purpose==='signup'){assert(verified.body.ticket);assert(!verified.body.emails);}else if(purpose==='find_id'){assert.deepEqual(verified.body.emails,['student@example.invalid']);assert(!verified.body.ticket);}else{
  const request={action:'reset',challenge:id,ticket:verified.body.ticket,password:'Password123!',confirmation:'Password123!'};let n=calls.length;
  assert.equal((await send({...request,confirmation:'mismatch'})).status,400);assert.equal(calls.length,n);
  assert.equal((await send({...request,ticket:'a'.repeat(64)})).status,400);assert(!calls.some(x=>x.url.includes('/auth/v1/admin/users/')));
  assert.equal((await send(request)).status,200);assert.equal((await send(request)).status,400);assert.equal(calls.filter(x=>x.url.includes('/auth/v1/admin/users/')).length,1);
 }
 }
 providerOK=false;let n=sms.length;assert.equal((await send({action:'request',purpose:'find_id',phone:'01012345678'})).status,503);assert.equal(sms.length,n+1);assert.equal([...records.values()].at(-1).sent,false);
 eligible=false;n=sms.length;assert.equal((await send({action:'request',purpose:'find_id',phone:'01012345678'})).status,200);assert.equal(sms.length,n);
 console.log('PASS: Edge 미설정 실패, CORS, OTP 비노출·HMAC, 실제 provider 접수 검사, 인증 전 아이디 비노출, 잘못된/재사용 인증 차단, 비밀번호 일치·일회용 티켓·서버 전용 변경 API (모의 외부 호출)');
})().catch(e=>{console.error(e);process.exit(1)});
