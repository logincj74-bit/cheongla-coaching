// Standalone Edge Function. No OTP, password, phone, email, or provider body is logged.
export function createRecoveryHandler(env, fetcher=fetch, crypt=crypto) {
 const allowed=(env.get('RECOVERY_ALLOWED_ORIGINS')||'https://logincj74-bit.github.io').split(',').map(x=>x.trim());
 const base=env.get('SUPABASE_URL'),service=env.get('SUPABASE_SERVICE_ROLE_KEY');
 const key=env.get('SOLAPI_API_KEY'),secret=env.get('SOLAPI_API_SECRET'),sender=env.get('SOLAPI_SENDER'),pepper=env.get('RECOVERY_OTP_SECRET');
 const ready=!!(base&&service&&key&&secret&&/^0\d{8,10}$/.test(sender||'')&&pepper?.length>=32);
 const encoder=new TextEncoder();
 const hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
 async function sha(text){return hex(await crypt.subtle.digest('SHA-256',encoder.encode(text)));}
 async function hmac(secret,text){const k=await crypt.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return hex(await crypt.subtle.sign('HMAC',k,encoder.encode(text)));}
 const token=()=>hex(crypt.getRandomValues(new Uint8Array(32)));
 function otp(){let n;do{n=crypt.getRandomValues(new Uint32Array(1))[0];}while(n>=4294000000);return String(n%1000000).padStart(6,'0');}
 async function backend(path,body,method='POST'){const response=await fetcher(base+path,{method,headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});if(!response.ok)throw Error('backend');if(response.status===204)return null;return await response.json();}
 const rpc=(name,args)=>backend('/rest/v1/rpc/'+name,args);
 return async function handler(req){
  const origin=req.headers.get('Origin'),cors={'Access-Control-Allow-Origin':origin&&allowed.includes(origin)?origin:allowed[0],'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
  const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json; charset=utf-8'}});
  if(origin&&!allowed.includes(origin))return reply({error:true,message:'허용되지 않은 요청입니다.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return reply({error:true,message:'요청 방법을 확인해 주세요.'},405);
  try{
   if(Number(req.headers.get('Content-Length')||0)>4096)return reply({error:true,message:'요청이 너무 큽니다.'},413);
   const text=await req.text();if(text.length>4096)return reply({error:true,message:'요청이 너무 큽니다.'},413);
   let input;try{input=JSON.parse(text);}catch{return reply({error:true,message:'입력 내용을 확인해 주세요.'},400);}
   if(!input||typeof input!=='object')return reply({error:true,message:'입력 내용을 확인해 주세요.'},400);
   if(input.action==='status')return reply({ready});
   if(!ready)return reply({error:true,code:'SMS_NOT_CONFIGURED',message:'휴대폰 문자 인증은 발송 서비스 연결 준비 중입니다.'},503);
   const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
   if(input.action==='request'){
    const phone=typeof input.phone==='string'?input.phone.replace(/[-\s]/g,''):'',email=typeof input.email==='string'?input.email.trim().toLowerCase():'';
    if(!/^01[016789][0-9]{7,8}$/.test(phone)||!['find_id','reset_password','signup'].includes(input.purpose)||['reset_password','signup'].includes(input.purpose)&&(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254))return reply({error:true,message:'가입한 이메일과 휴대전화번호를 확인해 주세요.'},400);
    const challenge=crypt.randomUUID(),code=otp(),codeHash=await hmac(pepper,'code:'+challenge+':'+code);
    const ip=(req.headers.get('x-forwarded-for')||'unknown').split(',')[0].trim();
    const signup=input.purpose==='signup';
    const issued=await rpc(signup?'cheongla_signup_issue':'cheongla_recovery_issue',{challenge,...(signup?{}:{recovery_purpose:input.purpose}),phone,email,phone_hash:await hmac(pepper,'phone:'+phone),ip_hash:await hmac(pepper,'ip:'+ip),code_hash:codeHash});
    if(issued?.limited)return reply({error:true,message:'요청 횟수를 초과했습니다. 잠시 후 다시 시도해 주세요.'},429);
    if(issued?.eligible){
     const date=new Date().toISOString(),salt=token(),signature=await hmac(secret,date+salt);
     let accepted=false;
     try{const r=await fetcher('https://api.solapi.com/messages/v4/send-many/detail',{method:'POST',headers:{Authorization:`HMAC-SHA256 apiKey=${key}, date=${date}, salt=${salt}, signature=${signature}`,'Content-Type':'application/json'},body:JSON.stringify({messages:[{to:phone,from:sender,type:'SMS',text:'[청라] '+(input.purpose==='signup'?'회원가입':input.purpose==='find_id'?'아이디 찾기':'비밀번호 찾기')+' 인증번호 ['+code+'] (5분간 유효)'}]}),redirect:'error',signal:AbortSignal.timeout(10000)});if(r.ok){const d=await r.json();accepted=d.groupInfo?.count?.registeredSuccess===1&&!d.failedMessageList?.length;}}catch{}
     await rpc('cheongla_recovery_sent',{challenge,accepted});
     if(!accepted)return reply({error:true,message:'인증 문자를 접수하지 못했습니다. 잠시 후 다시 요청해 주세요.'},503);
    }else await rpc('cheongla_recovery_sent',{challenge,accepted:true});
    return reply({challenge,expires_in:300});
   }
   if(input.action==='verify'){
    if(!uuid(input.challenge)||typeof input.code!=='string'||!/^\d{6}$/.test(input.code))return reply({error:true,message:'인증번호 6자리를 확인해 주세요.'},400);
    const ticket=token(),signup=input.purpose==='signup',r=await rpc(signup?'cheongla_signup_verify':'cheongla_recovery_verify',{challenge:input.challenge,code_hash:await hmac(pepper,'code:'+input.challenge+':'+input.code),ticket_hash:signup?await sha(ticket):await hmac(pepper,'ticket:'+ticket)});
    if(!r?.ok)return reply({error:true,message:'인증번호가 일치하지 않거나 만료되었습니다. 새 인증번호를 요청해 주세요.'},400);
    return reply(r.purpose==='find_id'?{emails:r.emails}:{ticket,expires_in:300});
   }
   if(input.action==='reset'){
    if(!uuid(input.challenge)||typeof input.ticket!=='string'||!/^[0-9a-f]{64}$/.test(input.ticket)||typeof input.password!=='string'||input.password.length<8||input.password.length>128||input.password!==input.confirmation)return reply({error:true,message:'비밀번호는 8자 이상으로 두 번 동일하게 입력해 주세요.'},400);
    const id=await rpc('cheongla_recovery_consume',{challenge:input.challenge,ticket_hash:await hmac(pepper,'ticket:'+input.ticket)});
    if(!id)return reply({error:true,message:'인증 시간이 만료되었거나 이미 사용되었습니다. 다시 인증해 주세요.'},400);
    // No email_confirm/phone_confirm flags: account verification state is preserved.
    await backend('/auth/v1/admin/users/'+id,{password:input.password},'PUT');
    return reply({ok:true});
   }
   return reply({error:true,message:'요청 내용을 확인해 주세요.'},400);
  }catch{return reply({error:true,message:'인증 처리를 완료하지 못했습니다. 휴대전화 인증을 다시 진행해 주세요.'},503);}
 };
}
if(typeof Deno!=='undefined')Deno.serve(createRecoveryHandler(Deno.env));
