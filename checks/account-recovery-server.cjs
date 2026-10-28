const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path'),crypto=require('node:crypto').webcrypto;
const source=fs.readFileSync(path.join(__dirname,'../supabase/functions/cheongla-account-recovery/index.ts'),'utf8');const c=vm.createContext({crypto,fetch,atob,TextEncoder,Uint8Array,Array,JSON,Date,Request,Response,AbortSignal});vm.runInContext(source.replace('export function ','function '),c);
let calls=[],validToken=true,authorized=true,updateOK=true,freshLogin=true,recovering=false,oldPasswordOK=true;const uid='00000000-0000-0000-0000-000000000001',target='00000000-0000-0000-0000-000000000002';
const userToken='Bearer x.'+Buffer.from(JSON.stringify({sub:uid,session_id:'00000000-0000-0000-0000-000000000003'})).toString('base64url')+'.x';
const resp=(d,status=200)=>new Response(JSON.stringify(d),{status});
async function network(url,o){assert(url.startsWith('https://db.example/'));calls.push({url,...o,body:o.body?JSON.parse(o.body):null});if(url.endsWith('/auth/v1/user')){if(o.method==='PUT')return resp(updateOK?{id:uid}:{code:'same_password'},updateOK?200:422);return resp({id:uid,email:'fixture@example.invalid'},validToken?200:401);}if(url.endsWith('/cheongla_manual_recovery_login'))return resp(freshLogin);if(url.endsWith('/cheongla_account_recovery_state'))return resp(recovering);if(url.includes('/rpc/'))return authorized?resp({ok:true}):resp({message:'관리자만 처리할 수 있습니다.'},403);if(url.includes('/auth/v1/admin/users/'))return resp({ok:true},updateOK?200:500);if(url.includes('/token?grant_type=password'))return resp(oldPasswordOK?{user:{id:uid},access_token:'verified-own-session'}:{},oldPasswordOK?200:400);if(url.includes('/logout?scope='))return resp({});throw Error('unexpected destination');}
const handler=c.createRecoveryHandler({get:k=>({SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'test-server-key'})[k]},network,crypto);
async function send(body,token=userToken,origin='https://logincj74-bit.github.io'){const r=await handler(new Request('https://db.example/function',{method:'POST',headers:{Origin:origin,Authorization:token},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
(async()=>{
 assert.deepEqual((await send({action:'status'})).body,{ready:false,manual:true});assert.equal(calls.length,0);
 assert.equal((await send({action:'request',purpose:'signup'})).status,400);assert.equal(calls.length,0);
 assert.equal((await send({action:'issue'},'','https://hostile.example')).status,403);
 assert.equal((await send({action:'issue'},'')).status,401);
 validToken=false;assert.equal((await send({action:'issue',target})).status,401);validToken=true;
 assert.equal((await send({action:'issue',target,reason:'검증'})).status,400);
 authorized=false;calls=[];assert.equal((await send({action:'issue',target,reason:'본인 통화 확인',identity_confirmed:true,version:'synthetic'})).status,400);assert(!calls.some(x=>x.url.includes('/admin/users')));authorized=true;
 calls=[];let r=await send({action:'issue',target,reason:'본인 통화 확인',identity_confirmed:true,version:'synthetic',actor:'forged'});assert.equal(r.status,200);assert(r.body.temporary_password.length>=32);assert.deepEqual(calls.filter(x=>x.url.includes('/rpc/')).map(x=>x.body.step),['issue','issued']);assert(calls.filter(x=>x.url.includes('/rpc/')).every(x=>x.body.actor===uid));assert(!JSON.stringify(calls.filter(x=>x.url.includes('/rpc/'))).includes(r.body.temporary_password));
 calls=[];r=await send({action:'finish',password:'abcdefgh',confirmation:'bad',target});assert.equal(r.status,400);assert(!calls.some(x=>x.url.includes('/admin/users')));
 calls=[];r=await send({action:'finish',password:'abcdefgh',confirmation:'abcdefgh',target});assert.equal(r.status,200);assert(!calls.some(x=>x.url.includes('/admin/users')));assert(calls.find(x=>x.method==='PUT').headers.Authorization===userToken);assert.deepEqual(calls.filter(x=>x.body?.step).map(x=>x.body.step),['finish_begin','finish']);assert(!JSON.stringify(r.body).includes('abcdefgh'));
 freshLogin=false;calls=[];r=await send({action:'finish',password:'abcdefgh',confirmation:'abcdefgh'});assert.equal(r.status,403);assert(!calls.some(x=>x.method==='PUT'));freshLogin=true;
 calls=[];updateOK=false;r=await send({action:'issue',target,reason:'본인 확인',identity_confirmed:true,version:'synthetic'});assert.equal(r.status,400);assert(!calls.some(x=>x.body?.step==='issued'));assert(!('temporary_password'in r.body));
 updateOK=true;const change={action:'change',current_password:'oldPassword!',password:'newPassword!',confirmation:'newPassword!',target};
 calls=[];oldPasswordOK=false;r=await send(change);assert.equal(r.status,400);assert(!calls.some(x=>x.method==='PUT'));oldPasswordOK=true;
 calls=[];recovering=true;r=await send(change);assert.equal(r.status,403);assert(!calls.some(x=>x.url.includes('/token?')));recovering=false;
 calls=[];r=await send({...change,confirmation:'mismatch'});assert.equal(r.status,400);assert(!calls.some(x=>x.method==='PUT'));
 calls=[];r=await send(change);assert.equal(r.status,200);assert.equal(r.body.sign_out,true);assert(!calls.some(x=>x.url.includes('/admin/users')));assert.equal(calls.find(x=>x.method==='PUT').headers.Authorization,'Bearer verified-own-session');assert(calls.some(x=>x.url.endsWith('/logout?scope=global')));assert(!JSON.stringify(r.body).includes(change.password));
 updateOK=false;calls=[];r=await send(change);assert.equal(r.status,400);assert(calls.some(x=>x.url.endsWith('/logout?scope=local')));
 console.log('PASS recovery Edge: verified identity, staff authorization, no secret audit, fresh temporary login gate, self-only finish, old password verification, same/mismatch rejection, self change and session logout');
})().catch(e=>{console.error(e);process.exit(1)});
