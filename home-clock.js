const dateFormat = new Intl.DateTimeFormat('ko-KR', {
  timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short',
});
const timeFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});
const examDay = Date.UTC(2026, 10, 19);

export function koreaClockState(now = new Date()) {
  const parts = Object.fromEntries(timeFormat.formatToParts(now).map(p => [p.type, p.value]));
  const today = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
  const days = Math.round((examDay - today) / 86400000);
  return {
    hours: String(Number(parts.hour)%12||12).padStart(2,'0'), period:Number(parts.hour)<12?'오전':'오후', minutes: parts.minute, seconds: parts.second,
    date: dateFormat.format(now),localDate:`${parts.year}-${parts.month}-${parts.day}`, iso: now.toISOString(), days,
    countdown: days === 0 ? 'D-DAY' : days > 0 ? `D-${days}` : `D+${Math.abs(days)}`,
    cheer: days === 0 ? '차분하게, 자신 있게. 청라가 응원합니다.' : days < 0
      ? '수고했어요. 여러분의 새로운 시작을 응원합니다.' : '오늘의 한 걸음, 더 나은 내일로.',
  };
}

export function weatherAdvice(advice,today=koreaClockState().localDate){
 if(!advice||advice.date!==today||!['rain','snow','sleet'].includes(advice.kind))return '';
 return {rain:'☔ 오늘 비 예보가 있어요. 우산 챙기세요!',snow:'🌨️ 오늘 눈 예보가 있어요. 등원길 조심하세요!',sleet:'🌨️ 오늘 비·눈 예보가 있어요. 우산 챙기고 등원길 조심하세요!'}[advice.kind]||'';
}
// Original line icons match the home's mint palette; no external image requests.
export function weatherAppearance(code){
 const base=String(code).split('_')[0],night=String(code).endsWith('_night');
 let text='예보 없음',shape='<path d="M9 9a3 3 0 0 1 6 0c0 2-3 2-3 4m0 4h.01"/>';
 const sun='<circle cx="12" cy="12" r="4"/><path d="M12 1v2m0 18v2M1 12h2m18 0h2M4.2 4.2l1.5 1.5m12.6 12.6 1.5 1.5M4.2 19.8l1.5-1.5M18.3 5.7l1.5-1.5"/>',cloud='<path d="M5 17a4 4 0 0 1-.7-7.9A6 6 0 0 1 16 7.5a4.8 4.8 0 0 1 2 9.5Z"/>';
 if(base==='clearsky'){text='맑음';shape=night?'<path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5Z"/>':sun;}
 else if(base==='fair'||base==='partlycloudy'){text=base==='fair'?'대체로 맑음':'구름 조금';shape='<path d="M6 3v2M1 9h2m.5-5.5L5 5m6-1.5L9.5 5"/><path d="M4 10a4 4 0 1 1 7-3"/>'+cloud;}
 else if(base==='cloudy'){text='흐림';shape=cloud;}
 else if(base==='fog'){text='안개';shape='<path d="M3 7h18M1 12h22M4 17h16"/>';}
 else if(base.includes('thunder')){text='뇌우';shape=cloud+'<path d="m12 13-3 6h4l-2 4"/>';}
 else if(base.includes('sleet')){text='진눈깨비';shape=cloud+'<path d="m7 20-1 2m6-2h.01m6-1-1 3"/>';}
 else if(base.includes('snow')){text=base.includes('heavy')?'강한 눈':'눈';shape=cloud+'<path d="M7 21h.01M12 20h.01M17 21h.01"/>';}
 else if(base.includes('rain')){text=base.includes('heavy')?'강한 비':base.includes('light')?'약한 비':'비';shape=cloud+'<path d="m8 19-1 3m6-3-1 3m6-3-1 3"/>';}
 return {text,svg:`<svg class="home-weather-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${shape}</svg>`};
}
if (typeof document !== 'undefined') {
  const clock = document.querySelector('.home-clock');
  if (clock && !clock.dataset.ready) {
    clock.dataset.ready = 'true';
    const update = () => {
      const state = koreaClockState();
      for (const key of ['period', 'hours', 'minutes', 'seconds', 'date', 'cheer']) {
        const element = clock.querySelector(`[data-clock-${key}]`);
        if (element.textContent !== state[key]) element.textContent = state[key];
      }
      const countdown = clock.querySelector('[data-clock-dday]');
      if (countdown.textContent !== state.countdown) countdown.textContent = state.countdown;
      clock.querySelector('[data-clock-time]').setAttribute('aria-label', `한국시간 ${state.period} ${state.hours}시 ${state.minutes}분 ${state.seconds}초`);
      const advice=clock.querySelector('[data-weather-advice]');
      if(advice?.dataset.date&&advice.dataset.date!==state.localDate){advice.hidden=true;advice.textContent='';delete advice.dataset.date;}
    };
    let timer,weatherTimer,lastWeatherAttempt=0,weatherBusy=false;
    const refreshWeather=async()=>{
      if(document.hidden||weatherBusy||Date.now()-lastWeatherAttempt<5*60000)return;
      weatherBusy=true;lastWeatherAttempt=Date.now();
      const target=clock.querySelector('[data-weather-current]'),week=clock.querySelector('[data-weather-week]'),updated=clock.querySelector('[data-weather-updated]'),advice=clock.querySelector('[data-weather-advice]');
      try{
        const r=await fetch(window.CHEONGLA_CONFIG.supabaseUrl+'/functions/v1/cheongla-weather',{headers:{apikey:window.CHEONGLA_CONFIG.supabasePublishableKey},signal:AbortSignal.timeout(12000)});if(!r.ok)throw new Error('Weather unavailable');
        const b=await r.json();if(!Number.isFinite(b.temperature)||!Array.isArray(b.daily)||!Number.isFinite(Date.parse(b.updatedAt))||!Number.isFinite(Date.parse(b.forecastAt))||Math.abs(Date.now()-Date.parse(b.forecastAt))>3*3600000)throw new Error('Invalid weather');
        const appearance=weatherAppearance(b.symbol);
        target.innerHTML=appearance.svg;
        const value=document.createElement('div');value.className='home-weather-value';
        const label=document.createElement('span');label.textContent='전주 · '+appearance.text;
        const temperature=document.createElement('strong');temperature.textContent=b.temperature+'°C';value.append(label,temperature);target.append(value);
        target.setAttribute('aria-label',`전주 지역 예보 ${appearance.text}, ${b.temperature}도`);
        const guidance=weatherAdvice(b.advice);advice.textContent=guidance;advice.hidden=!guidance;
        if(guidance)advice.dataset.date=b.advice.date;else delete advice.dataset.date;
        week.replaceChildren();
        for(const day of b.daily.slice(0,7)){
          if(!/^20\d{2}-\d{2}-\d{2}$/.test(day.date)||!Number.isFinite(day.temperature))continue;
          const date=new Date(day.date+'T12:00:00+09:00');if(Number.isNaN(date.getTime()))continue;
          const icon=weatherAppearance(day.symbol),item=document.createElement('div');item.className='home-weather-day';
          item.innerHTML=icon.svg;
          const weekday=document.createElement('span');weekday.textContent=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',weekday:'short'}).format(date);item.prepend(weekday);
          const temp=document.createElement('strong');temp.textContent=day.temperature+'°';
          const description=document.createElement('small');description.textContent=icon.text;item.append(temp,description);
          item.setAttribute('aria-label',day.date+' 낮 예보 '+icon.text+', '+day.temperature+'도');week.append(item);
        }
        updated.textContent=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',hour:'numeric',minute:'2-digit',hour12:true}).format(new Date(b.forecastAt))+' 예보';
        updated.title='자료 갱신: '+new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',month:'numeric',day:'numeric',hour:'numeric',minute:'2-digit'}).format(new Date(b.updatedAt));
      }catch{
        advice.hidden=true;advice.textContent='';delete advice.dataset.date;
        target.replaceChildren();target.removeAttribute('aria-label');
        const label=document.createElement('span');label.className='home-clock-label';label.textContent='전주 날씨';
        const error=document.createElement('span');error.className='home-weather-loading';error.textContent='잠시 확인 불가';target.append(label,error);week.replaceChildren();updated.textContent='연결 후 자동 갱신';
      }finally{weatherBusy=false;}
    };
    const stop=()=>{clearInterval(timer);clearInterval(weatherTimer);};
    const start = () => { stop(); update(); timer = setInterval(update, 1000);refreshWeather();weatherTimer=setInterval(refreshWeather,15*60000+Math.random()*60000); };
    start();
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stop(); else start();
    });
    window.addEventListener('pagehide', stop);
    window.addEventListener('pageshow', start);
  }
}
