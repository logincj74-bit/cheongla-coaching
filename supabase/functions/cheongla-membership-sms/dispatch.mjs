export function messageFor(kind){
 if(kind==='request')return '[청라] 새 가입신청이 접수됐습니다. 앱에서 확인해 주세요.';
 if(kind==='approved')return '[청라] 가입승인이 완료됐습니다. 청라앱에 로그인해 주세요.';
 throw new Error('Unknown membership event');
}
export function sameSecret(a,b){if(!a||!b||a.length!==b.length)return false;let d=0;for(let i=0;i<a.length;i++)d|=a.charCodeAt(i)^b.charCodeAt(i);return d===0;}
export async function authorization(apiKey,secret,date=new Date().toISOString(),salt=crypto.randomUUID()){
 const encoder=new TextEncoder(),key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const bytes=await crypto.subtle.sign('HMAC',key,encoder.encode(date+salt));
 const signature=Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
 return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`;
}
export async function sendMembershipSms(job,config,transport=fetch){
 if(!/^01[016789][0-9]{7,8}$/.test(job.to)||!/^0[0-9]{8,10}$/.test(config.from))throw new Error('Invalid phone');
 const text=messageFor(job.kind);
 try{
  const response=await transport('https://api.solapi.com/messages/v4/send-many/detail',{method:'POST',headers:{'Content-Type':'application/json',Authorization:await authorization(config.key,config.secret)},body:JSON.stringify({messages:[{to:job.to,from:config.from,text,type:'SMS',autoTypeDetect:false,customFields:{jobId:job.id}}],allowDuplicates:false,showMessageList:true}),redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!response.ok)return {result:response.status>=500?'unknown':'failed',message_id:null};
  const body=await response.json(),entry=body.messageList?.find(x=>x.customFields?.jobId===job.id);
  if(entry?.statusCode==='2000'&&typeof entry.messageId==='string')return {result:'accepted',message_id:entry.messageId};
  if(body.failedMessageList?.some(x=>x.customFields?.jobId===job.id))return {result:'failed',message_id:null};
  return {result:'unknown',message_id:null};
 }catch{return {result:'unknown',message_id:null};}
}
