const dateFormat = new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'});
export function localDate(date) {
 const p=Object.fromEntries(dateFormat.formatToParts(date).map(x=>[x.type,x.value]));
 return `${p.year}-${p.month}-${p.day}`;
}
function symbol(row) { return row.data?.next_1_hours?.summary?.symbol_code || row.data?.next_6_hours?.summary?.symbol_code || row.data?.next_12_hours?.summary?.symbol_code || 'unknown'; }
export function forecastSummary(body, now=new Date()) {
 const rows=body?.properties?.timeseries;
 if(!Array.isArray(rows)||!rows.length||!Number.isFinite(Date.parse(body.properties.meta?.updated_at)))throw Error('Invalid forecast');
 const valid=rows.filter(r=>Number.isFinite(Date.parse(r.time))&&Number.isFinite(r.data?.instant?.details?.air_temperature));
 const current=valid.reduce((best,r)=>!best||Math.abs(Date.parse(r.time)-now.getTime())<Math.abs(Date.parse(best.time)-now.getTime())?r:best,null);
 if(!current||Math.abs(Date.parse(current.time)-now.getTime())>3*3600000)throw Error('Outdated forecast');
 const today=localDate(now),days=new Map();
 for(const r of valid){
  const day=localDate(new Date(r.time));if(day<=today)continue;
  const noon=Date.parse(day+'T12:00:00+09:00');
  if(!days.has(day)||Math.abs(Date.parse(r.time)-noon)<Math.abs(Date.parse(days.get(day).time)-noon))days.set(day,r);
 }
 const daily=[...days].sort(([a],[b])=>a.localeCompare(b)).slice(0,7).map(([date,r])=>({date,temperature:Math.round(r.data.instant.details.air_temperature),symbol:symbol(r)}));
 const remaining=valid.filter(r=>localDate(new Date(r.time))===today&&Date.parse(r.time)>=now.getTime()-3600000);
 let kind=null;
 for(const r of remaining){const code=symbol(r);if(code.includes('sleet')){kind='sleet';break;}if(code.includes('snow'))kind=kind==='rain'?'sleet':'snow';else if(code.includes('rain'))kind=kind==='snow'?'sleet':kind||'rain';}
 return {city:'전주',temperature:Math.round(current.data.instant.details.air_temperature),symbol:symbol(current),forecastAt:current.time,updatedAt:body.properties.meta.updated_at,daily,advice:kind?{date:today,kind}:null};
}
