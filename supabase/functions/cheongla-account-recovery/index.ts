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
   if(!['issue','finish','change'].includes(input?.action))return reply({error:true,message:'문자 인증 대신 학원에 계정 복구를 문의해 주세요.'},400);
   const token=req.headers.get('Authorization')||'';if(!/^Bearer \S+$/.test(token))return reply({error:true,message:'로그인 후 이용해 주세요.'},401);
   const auth=await fetcher(base+'/auth/v1/user',{headers:{apikey:service,Authorization:token},redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!auth.ok)return reply({error:true,message:'로그인 상태를 다시 확인해 주세요.'},401);
   const user=await auth.json();if(!user?.id)return reply({error:true},401);
   async function backend(path,body,method='POST'){
    const r=await fetcher(base+path,{method,headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});
    if(!r.ok){const d=await r.json().catch(()=>({}));throw Error(path.includes('/rpc/')?d.message||'계정 상태를 확인해 주세요.':'계정 인증 정보를 저장하지 못했습니다. 관리자에게 문의해 주세요.');}return r.status===204?null:r.json();
   }
   async function userRequest(path,body,bearer,method='POST'){
    return fetcher(base+path,{method,headers:{apikey:service,Authorization:bearer,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});
   }
   async function updateOwnPassword(bearer,password,current){
    const r=await userRequest('/auth/v1/user',{password,...(current?{current_password:current}:{})},bearer,'PUT');
    if(!r.ok){const d=await r.json().catch(()=>({}));throw Error(d.code==='same_password'?'기존 비밀번호와 다른 새 비밀번호를 입력해 주세요.':d.code==='weak_password'?'비밀번호가 보안 기준에 맞지 않습니다. 더 길고 복잡하게 입력해 주세요.':'비밀번호를 변경하지 못했습니다. 다시 로그인한 뒤 시도해 주세요.');}
   }
   if(input.action==='change'){
    if(typeof input.current_password!=='string'||!input.current_password||input.current_password.length>128||typeof input.password!=='string'||input.password.length<8||input.password.length>128||input.password!==input.confirmation)return reply({error:true,message:'현재 비밀번호와 새 비밀번호를 확인하고 새 비밀번호를 두 번 동일하게 입력해 주세요.'},400);
    if(input.password===input.current_password)return reply({error:true,message:'기존 비밀번호와 다른 새 비밀번호를 입력해 주세요.'},400);
    const recovery=await userRequest('/rest/v1/rpc/cheongla_account_recovery_state',{},token);
    if(!recovery.ok||await recovery.json()!==false)return reply({error:true,message:'임시 비밀번호 로그인 후 새 비밀번호 설정 화면을 이용해 주세요.'},403);
    // Verify the old password independently; never trust a caller-supplied member ID.
    const verified=await userRequest('/auth/v1/token?grant_type=password',{email:user.email,password:input.current_password},'Bearer '+service);
    if(!verified.ok)return reply({error:true,message:'현재 비밀번호가 일치하지 않거나 로그인 확인이 제한되었습니다. 잠시 후 다시 확인해 주세요.'},400);
    const session=await verified.json();
    if(session.user?.id!==user.id||typeof session.access_token!=='string')return reply({error:true,message:'본인 계정 정보를 확인하지 못했습니다.'},403);
    let changed=false;
    try{await updateOwnPassword('Bearer '+session.access_token,input.password,input.current_password);changed=true;}
    finally{await fetcher(base+'/auth/v1/logout?scope='+(changed?'global':'local'),{method:'POST',headers:{apikey:service,Authorization:'Bearer '+session.access_token},redirect:'error',signal:AbortSignal.timeout(10000)}).catch(()=>{});}
    return reply({ok:true,sign_out:true});
   }
   const operation=crypt.randomUUID();
   const target=input.action==='finish'?user.id:input.target;
   if(typeof target!=='string'||!(/^[0-9a-f-]{36}$/i.test(target)))return reply({error:true,message:'회원을 선택해 주세요.'},400);
   const job=step=>backend('/rest/v1/rpc/cheongla_manual_recovery_job',{actor:user.id,target_member:target,operation,step,reason:input.reason||'',expected_version:input.version||null});
   if(input.action==='issue'){
    if(input.identity_confirmed!==true||typeof input.reason!=='string'||input.reason.trim().length<2)return reply({error:true,message:'가입 당시 번호로 본인 확인 후 사유를 입력해 주세요.'},400);
    const email=typeof input.email==='string'?input.email.trim().toLowerCase():'';
    if(email&&(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||email.endsWith('@phone.cheongla.invalid')))return reply({error:true,message:'새 이메일을 확인해 주세요.'},400);
    await job('issue');
    const password='Cl!'+Array.from(crypt.getRandomValues(new Uint8Array(18)),x=>x.toString(16).padStart(2,'0')).join('');
    await backend('/auth/v1/admin/users/'+target,{password,...(email?{email}:{} )},'PUT');
    await job('issued');
    return reply({ok:true,temporary_password:password});
   }
   if(typeof input.password!=='string'||input.password.length<8||input.password.length>128||input.password!==input.confirmation)return reply({error:true,message:'비밀번호를 8자 이상으로 두 번 동일하게 입력해 주세요.'},400);
   let claims;try{claims=JSON.parse(atob(token.slice(7).split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));}catch{return reply({error:true,message:'다시 로그인해 주세요.'},401);}
   if(claims.sub!==user.id||typeof claims.session_id!=='string'||!await backend('/rest/v1/rpc/cheongla_manual_recovery_login',{actor:user.id,login_session:claims.session_id}))return reply({error:true,message:'발급된 임시 비밀번호로 다시 로그인해 주세요. 발급 후 24시간이 지났다면 원장·실장에게 재발급을 요청해 주세요.'},403);
   await job('finish_begin');await updateOwnPassword(token,input.password);await job('finish');return reply({ok:true});
  }catch(e){return reply({error:true,message:e?.message?.startsWith('계정')||/[가-힣]/.test(e?.message||'')?e.message:'계정 처리를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.'},400);}
 };
}
if(typeof Deno!=='undefined')Deno.serve(createRecoveryHandler(Deno.env));
