// Korean lunar date; calculated on-device without transmitting user data.
let lunarFormatter;
export function koreanLunarDate(now=new Date()){
 try{
  lunarFormatter??=new Intl.DateTimeFormat('ko-KR-u-ca-dangi',{timeZone:'Asia/Seoul',month:'numeric',day:'numeric'});
  if(lunarFormatter.resolvedOptions().calendar!=='dangi')return '';
  const p=Object.fromEntries(lunarFormatter.formatToParts(now).map(x=>[x.type,x.value]));
  return p.month&&p.day?'음력 '+p.month+'월 '+p.day+'일':'';
 }catch{return '';}
}
