import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {sameSecret,sendMembershipSms} from './dispatch.mjs';
Deno.serve(async request=>{
 const reply=(status,ok)=>new Response(JSON.stringify({ok}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 if(request.method!=='POST')return reply(405,false);
 const url=Deno.env.get('SUPABASE_URL'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const key=Deno.env.get('SOLAPI_API_KEY'),secret=Deno.env.get('SOLAPI_API_SECRET'),from=Deno.env.get('SOLAPI_FROM');
 if(!url||!service||!key||!secret||!from)return reply(503,false);
 const server=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const config=await server.rpc('cheongla_membership_sms_server_config');
  if(config.error||!sameSecret(request.headers.get('x-cheongla-webhook')||'',config.data?.webhook_secret||''))return reply(401,false);
  if(!config.data?.enabled)return reply(503,false);
  const batch=await server.rpc('cheongla_claim_membership_sms');if(batch.error)return reply(503,false);
  for(const job of batch.data||[]){
   let result;try{result=await sendMembershipSms(job,{key,secret,from});}catch{result={result:'failed',message_id:null};}
   const done=await server.rpc('cheongla_finish_membership_sms',{job:job.id,token:job.token,...result});
   if(done.error)return reply(503,false);
  }
  return reply(200,true);
 }catch{return reply(503,false);}
});
