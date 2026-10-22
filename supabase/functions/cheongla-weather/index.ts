import { forecastSummary } from './forecast.mjs';
// Fixed public city forecast only. No database or member information is accessed.
let cached: {body: unknown; until: number} | null = null;
let inflight: Promise<unknown> | null = null;
const headers = {'Access-Control-Allow-Origin':'https://logincj74-bit.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'GET, OPTIONS','Vary':'Origin','Content-Type':'application/json','Cache-Control':'public, max-age=300'};
const publicAppKey = "sb_publishable_Mib0bjTMcfdmMFXhAx2dGg_gKT52-Oe";
Deno.serve(async req => {
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.headers.get('apikey')!==publicAppKey)return new Response(JSON.stringify({error:'Invalid app key'}),{status:401,headers});
 if(req.method!=='GET')return new Response(JSON.stringify({error:'Method not allowed'}),{status:405,headers});
 try{
  if(!cached||Date.now()>cached.until){
   if(!inflight)inflight=(async()=>{
    const r=await fetch('https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=35.8242&lon=127.1480',{headers:{'User-Agent':'CheonglaCoaching/1.8.7 https://logincj74-bit.github.io/cheongla-coaching/'},signal:AbortSignal.timeout(9000)});
    if(!r.ok)throw Error('Forecast unavailable');
    const body=await r.json();forecastSummary(body);
    const expires=Date.parse(r.headers.get('expires')||'');
    cached={body,until:Math.max(Date.now()+5*60000,Number.isFinite(expires)?expires:0)};
    return body;
   })().finally(()=>{inflight=null;});
   await inflight;
  }
  return new Response(JSON.stringify(forecastSummary(cached!.body)),{headers});
 }catch{return new Response(JSON.stringify({error:'Weather temporarily unavailable'}),{status:503,headers:{...headers,'Cache-Control':'no-store'}});}
});
