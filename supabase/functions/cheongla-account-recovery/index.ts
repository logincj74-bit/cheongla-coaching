// Manual recovery only. Never log tokens, passwords, email, phone or provider bodies.
export function createRecoveryHandler(env, fetcher=fetch, crypt=crypto) {
 const base=env.get('SUPABASE_URL'),service=env.get('SUPABASE_SERVICE_ROLE_KEY');
 const allowed=(env.get('RECOVERY_ALLOWED_ORIGINS')||'https://logincj74-bit.github.io').split(',').map(x=>x.trim());
 return async req=>{
  const origin=req.headers.get('Origin'),cors={'Access-Control-Allow-Origin':origin&&allowed.includes(origin)?origin:allowed[0],'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
  const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json; charset=utf-8'}});
  if(origin&&!allowed.includes(origin))return reply({error:true,message:'허용되지 않은 요청입니다.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return reply({error:true},405);
  try{
   const text=await req.text();if(text.length>4096)return reply({error:true},413);let input;try{input=JSON.parse(text);}catch{return reply({error:true},400);}
   if(input?.action==='status')return reply({ready:false,manual:true});
   if(!['issue','finish'].includes(input?.action))return reply({error:true,message:'문자 인증 대신 학원에 계정 복구를 문의해 주세요.'},400);
   const token=req.headers.get('Authorization')||'';if(!/^Bearer \S+$/.test(token))return reply({error:true,message:'로그인 후 이용해 주세요.'},401);
   const auth=await fetcher(base+'/auth/v1/user',{headers:{apikey:service,Authorization:token},redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!auth.ok)return reply({error:true,message:'로그인 상태를 다시 확인해 주세요.'},401);
   const user=await auth.json();if(!user?.id)return reply({error:true},401);
   async function backend(path,body,method='POST'){
    const r=await fetcher(base+path,{method,headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});
    if(!r.ok){const d=await r.json().catch(()=>({}));throw Error(path.includes('/rpc/')?d.message||'계정 상태를 확인해 주세요.':'계정 인증 정보를 저장하지 못했습니다. 관리자에게 문의해 주세요.');}return r.status===204?null:r.json();
   }
   const operation=crypt.randomUUID();
   const target=input.action==='finish'?user.id:input.target;
   if(typeof target!=='string'||!(/^[0-9a-f-]{36}$/i.test(target)))return reply({error:true,message:'회원을 선택해 주세요.'},400);
   const job=step=>backend('/rest/v1/rpc/cheongla_manual_recovery_job',{actor:user.id,target_member:target,operation,step,reason:input.reason||'',expected_version:input.version||null});
   if(input.action==='issue'){
    if(input.identity_confirmed!==true||typeof input.reason!=='string'||input.reason.trim().length<2)return reply({error:true,message:'가입 당시 번호로 본인 확인 후 사유를 입력해 주세요.'},400);
    const email=typeof input.email==='string'?input.email.trim().toLowerCase():'';
    if(email&&(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254))return reply({error:true,message:'새 이메일을 확인해 주세요.'},400);
    await job('issue');
    const password='Cl!'+Array.from(crypt.getRandomValues(new Uint8Array(18)),x=>x.toString(16).padStart(2,'0')).join('');
    await backend('/auth/v1/admin/users/'+target,{password,...(email?{email}:{} )},'PUT');
    await job('issued');
    return reply({ok:true,temporary_password:password});
   }
   if(typeof input.password!=='string'||input.password.length<8||input.password.length>128||input.password!==input.confirmation)return reply({error:true,message:'비밀번호를 8자 이상으로 두 번 동일하게 입력해 주세요.'},400);
   await job('finish_begin');await backend('/auth/v1/admin/users/'+target,{password:input.password},'PUT');await job('finish');return reply({ok:true});
  }catch(e){return reply({error:true,message:e?.message?.startsWith('계정')||/[가-힣]/.test(e?.message||'')?e.message:'계정 처리를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.'},400);}
 };
}
if(typeof Deno!=='undefined')Deno.serve(createRecoveryHandler(Deno.env));
