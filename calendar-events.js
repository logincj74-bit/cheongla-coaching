// 한국천문연구원 달력자료, 한국 표준시. 2028년은 발표 전 참고자료.
// https://astro.kasi.re.kr/kor/life/post/calendarData
const names=['소한','대한','입춘','우수','경칩','춘분','청명','곡우','입하','소만','망종','하지','소서','대서','입추','처서','백로','추분','한로','상강','입동','소설','대설','동지'];
const days={
 2026:[5,20,4,19,5,20,5,20,5,21,6,21,7,23,7,23,7,23,8,23,7,22,7,22],
 2027:[5,20,4,19,6,21,5,20,6,21,6,21,7,23,8,23,8,23,8,24,8,22,7,22],
 2028:[6,20,4,19,5,20,4,19,5,20,5,21,6,22,7,22,7,22,8,23,7,22,6,21]
};
const art=['❄️','❄️','🌱','🌧️','🐸','🌷','🌿','🌧️','🌿','🌾','🌾','☀️','🌤️','☀️','🍃','🍃','🌾','🍂','🍂','🍁','❄️','🌨️','❄️','🌅'];
const holidays={'03-01':['3·1절','🇰🇷'],'07-17':['제헌절','📜'],'08-15':['광복절','🇰🇷'],'10-03':['개천절','dangun'],'10-09':['한글날','한']};
export function calendarEvents(date){
 if(!/^\d{4}-\d\d-\d\d$/.test(date))return [];
 const year=Number(date.slice(0,4)),month=Number(date.slice(5,7)),day=Number(date.slice(8,10)),items=[];
 const h=holidays[date.slice(5)];if(h)items.push({kind:'국경일',name:h[0],art:h[1]});
 const dates=days[year];if(dates)for(let i=(month-1)*2;i<month*2;i++)if(dates[i]===day)items.push({kind:'24절기',name:names[i],art:art[i]});
 return items;
}
export function renderCalendarEvents(container,date){
 if(!container)return;
 const items=calendarEvents(date);container.replaceChildren();container.hidden=!items.length;
 for(const item of items){
  const row=document.createElement('span');row.className='calendar-event';
  if(item.art==='dangun'){
   const img=document.createElement('img');img.className='calendar-event-art';img.src='assets/dangun.webp';img.alt='단군을 상상해 그린 그림';img.width=36;img.height=36;row.append(img);
  }else{const pic=document.createElement('span');pic.className='calendar-event-symbol';pic.textContent=item.art;pic.setAttribute('aria-hidden','true');row.append(pic);}
  const text=document.createElement('span');text.className='calendar-event-copy';
  const kind=document.createElement('small');kind.textContent=item.kind;
  const label=document.createElement('strong');label.textContent=item.name;text.append(kind,label);row.append(text);container.append(row);
 }
}
