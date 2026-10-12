import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';

const APP_ORIGIN = 'https://logincj74-bit.github.io';
const APP_URL = APP_ORIGIN + '/cheongla-coaching/';
const cors = { 'Access-Control-Allow-Origin': APP_ORIGIN, 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin' };
const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), {status, headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
function permittedEndpoint(value: string) {
 try { const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&(!u.port||u.port==='443')&&(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||/^[a-z0-9-]+\.push\.apple\.com$/i.test(u.hostname)||/^[a-z0-9.-]+\.notify\.windows\.com$/i.test(u.hostname)); } catch {return false;}
}
function sameSecret(a: string, b: string) {if(!a||!b||a.length!==b.length)return false;let result=0;for(let i=0;i<a.length;i++)result|=a.charCodeAt(i)^b.charCodeAt(i);return result===0;}
Deno.serve(async (request: Request) => {
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(request.method!=='POST')return reply(405,{error:'POST required'});
 const url=Deno.env.get('SUPABASE_URL'),serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),anonKey=Deno.env.get('SUPABASE_ANON_KEY');
 if(!url||!serviceKey||!anonKey)return reply(503,{error:'Server configuration unavailable'});
 const server=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 try {
  const configResult=await server.rpc('cheongla_push_server_config');
  if(configResult.error)return reply(503,{error:'먼저 푸시 설정 SQL을 실행해 주세요.'});
  let config=configResult.data;
  const webhook=request.headers.get('x-cheongla-webhook')||'';
  const dispatch=sameSecret(webhook,config?.webhook_secret||'');
  if(dispatch) {
   if(!config?.enabled||!config.private_key||!config.public_key)return reply(503,{error:'Push is not enabled'});
   const batch=await server.rpc('cheongla_claim_push_deliveries');
   if(batch.error)return reply(503,{error:'Could not claim delivery batch'});
   let sent=0,failed=0;
   const work=batch.data||[];
   for(let offset=0;offset<work.length;offset+=4){
    await Promise.all(work.slice(offset,offset+4).map(async (item: Record<string,unknown>)=>{
     let status=0;
     try {
      if(!permittedEndpoint(String(item.endpoint)))status=410;
      else {
       const payload=JSON.stringify({notificationId:item.notification_id,body:String(item.title).slice(0,200)});
       const details=webpush.generateRequestDetails({endpoint:String(item.endpoint),keys:{p256dh:String(item.p256dh),auth:String(item.auth_key)}},payload,{TTL:300,vapidDetails:{subject:config.subject,publicKey:config.public_key,privateKey:config.private_key}});
       const result=await fetch(details.endpoint,{method:details.method,headers:details.headers,body:details.body,redirect:'manual',signal:AbortSignal.timeout(8000)});
       status=result.status;
      }
     } catch {/* Never log subscription keys or private payloads. */}
     const finish=await server.rpc('cheongla_finish_push_delivery',{delivery:item.delivery_id,response_status:status});
     if(status>=200&&status<300&&!finish.error)sent++;else failed++;
    }));
   }
   return reply(200,{sent,failed});
  }
  const authorization=request.headers.get('authorization')||'';
  if(!authorization.startsWith('Bearer '))return reply(401,{error:'Sign in required'});
  const token=authorization.slice(7),verified=await server.auth.getUser(token);
  if(verified.error||!verified.data.user)return reply(401,{error:'Sign in required'});
  const user=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const profile=await user.from('cheongla_profiles').select('approval_status,is_app_admin').eq('id',verified.data.user.id).single();
  if(profile.error||profile.data?.approval_status!=='approved')return reply(403,{error:'승인된 계정으로 이용해 주세요.'});
  const body=await request.json();
  if(body.action==='setup'){
   if(profile.data.is_app_admin!==true)return reply(403,{error:'앱 관리자만 서버를 연결할 수 있습니다.'});
   const keys=config?.public_key&&config?.private_key?{publicKey:config.public_key,privateKey:config.private_key}:webpush.generateVAPIDKeys();
   const initialized=await server.rpc('cheongla_initialize_web_push',{vapid_public:keys.publicKey,vapid_private:keys.privateKey,vapid_subject:APP_URL});
   if(initialized.error)return reply(503,{error:'푸시 서버 초기화에 실패했습니다.'});
   return reply(200,{enabled:true,public_key:initialized.data.public_key});
  }
  if(body.action==='test'){
   const test=await user.rpc('cheongla_request_push_test');
   if(test.error)return reply(400,{error:test.error.message});
   return reply(200,{requested:true});
  }
  return reply(400,{error:'Unknown action'});
 } catch {return reply(500,{error:'Push request failed'});}
});
