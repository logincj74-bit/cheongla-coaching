export const SEASONS = Object.freeze({
 autumn:{label:'CHEONGLA · AUTUMN',headline:'차곡차곡 쌓은 하루,\n단단해지는 나의 내일.',description:'깊어지는 가을,\n청라에서 나의 공부를 이어갑니다.',effect:'낙엽'},
 winter:{label:'CHEONGLA · WINTER',headline:'따뜻한 공간에서,\n단단해지는 나의 겨울.',description:'추운 겨울,\n공부의 온기를 만나는 곳.',effect:'눈'},
 spring:{label:'CHEONGLA · SPRING',headline:'새롭게 피어나는 봄,\n나의 가능성도 함께.',description:'설레는 시작,\n청라에서 나만의 봄을 피웁니다.',effect:'벚꽃'},
 summer:{label:'CHEONGLA · SUMMER',headline:'푸르게 자라는 여름,\n꾸준함이 실력이 됩니다.',description:'초록빛 담쟁이처럼,\n하루하루 더 넓은 세상으로.',effect:'담쟁이 잎'}
});
export function seasonForDate(now=new Date()){
 const month=Number(new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Seoul',month:'numeric'}).format(now));
 return month>=3&&month<=5?'spring':month>=6&&month<=8?'summer':month>=9&&month<=11?'autumn':'winter';
}
export function skipSeasonWelcome(url){const u=new URL(url);return u.searchParams.has('push')||u.searchParams.has('page')||!!u.hash;}
const shapes={
 autumn:'<path d="m12 1-3 6-4-2 1 6H2l5 5-1 3 5-1v5h2v-5l5 1-1-3 5-5h-4l1-6-4 2Z"/><path d="M12 7v12m-5-8 5 4 5-4" fill="none" stroke="#765139" stroke-width=".8"/>',
 winter:'<circle cx="12" cy="12" r="8"/>',
 spring:'<path d="M12 5C5-3-3 6 4 14c3 3 6 5 8 7 2-2 5-4 8-7 7-8-1-17-8-9Z"/>',
 summer:'<path d="M12 2 8 8 3 6l1 7-3 2 7 4 4 3 4-3 7-4-3-2 1-7-5 2Z"/><path d="M12 5v16m-7-9 7 4 7-4" fill="none" stroke="#487959" stroke-width=".8"/>'
};
export function particleSettings(index,season){
 const snow=season==='winter';return {x:((index*47+13)%101)+'%',size:(snow?3+index%5:10+(index*7)%12)+'px',opacity:String(snow ? .4+(index%4)*.12 : season==='autumn' ? .78+(index%4)*.06 : .25+(index%4)*.09),duration:(14+(index*3)%13)+'s',delay:-(index*1.7%25)+'s',spin:(4+index%6)+'s',sway:(index%2?1:-1)*(24+index*7%65)+'px'};
}
export function mountSeasonalUI(doc,win){
 const dialog=doc.getElementById('seasonWelcome'),open=doc.getElementById('seasonWelcomeOpen'),start=doc.getElementById('seasonWelcomeStart');
 if(!dialog||!start||dialog.dataset.ready)return;
 dialog.dataset.ready='true';
 const surfaces=[...doc.querySelectorAll('[data-season-surface]')],buttons=[...doc.querySelectorAll('[data-season-motion]')];
 const reduced=win.matchMedia('(prefers-reduced-motion: reduce)');
 const read=(store,key)=>{try{return win[store].getItem(key);}catch{return null;}};
 const write=(store,key,value)=>{try{win[store].setItem(key,value);}catch{}};
 let season='',lastTrigger=null,off=read('localStorage','cheongla-season-motion')==='off';
 const pause=()=>{for(const surface of surfaces)surface.dataset.paused=String(doc.hidden||(surface!==dialog&&dialog.open));};
 const particles=()=>{
  const enabled=!off&&!reduced.matches;
  for(const surface of surfaces){
   surface.dataset.motion=enabled?'on':'off';
   const layer=surface.querySelector('[data-season-particles]');layer.replaceChildren();if(!enabled)continue;
   const count=surface===dialog?22:12;
   for(let i=0;i<count;i++){
    const leaf=doc.createElement('span'),settings=particleSettings(i,season);leaf.className='season-particle';
    for(const [key,value] of Object.entries(settings))leaf.style.setProperty('--'+key,value);
    if(season==='autumn')leaf.style.setProperty('--particle-color',['#e4aa00','#c4382c','#85452c','#efbe16','#ad2928','#a25c32'][i%6]);
    leaf.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'+shapes[season]+'</svg>';
    layer.append(leaf);
   }
  }
  for(const button of buttons){button.disabled=reduced.matches;button.setAttribute('aria-pressed',String(enabled));button.textContent=reduced.matches?'기기 설정에 따라 효과 꺼짐':SEASONS[season].effect+' 효과 '+(enabled?'끄기':'켜기');}
  pause();
 };
 const updateSeason=()=>{
  const next=seasonForDate();if(next===season)return;
  season=next;const copy=SEASONS[season];
  for(const surface of surfaces){surface.dataset.season=season;for(const [key,selector] of [['label','[data-season-label]'],['headline','[data-season-headline]'],['description','[data-season-description]']])for(const node of surface.querySelectorAll(selector))node.textContent=copy[key];}
  particles();
 };
 const seenKey=()=> 'cheongla-welcome:light:'+season;
 const show=trigger=>{
  if(dialog.open||doc.querySelector('dialog[open]'))return;
  lastTrigger=trigger;
  try{dialog.showModal();doc.body.classList.add('season-welcome-open');pause();}catch{doc.body.classList.remove('season-welcome-open');}
 };
 const finished=()=>{write('sessionStorage',seenKey(),'seen');doc.body.classList.remove('season-welcome-open');pause();lastTrigger?.focus({preventScroll:true});};
 open?.addEventListener('click',()=>show(open));
 start.addEventListener('click',()=>dialog.close());
 dialog.addEventListener('close',finished);
 for(const button of buttons)button.addEventListener('click',()=>{if(reduced.matches)return;off=!off;write('localStorage','cheongla-season-motion',off?'off':'on');particles();});
 reduced.addEventListener('change',particles);
 doc.addEventListener('visibilitychange',()=>{if(!doc.hidden)updateSeason();pause();});
 win.addEventListener('pagehide',()=>{for(const surface of surfaces)surface.dataset.paused='true';});
 win.addEventListener('pageshow',()=>{updateSeason();pause();});
 win.setInterval(()=>{if(!doc.hidden)updateSeason();},60000);
 updateSeason();
 const originalURL=win.performance?.getEntriesByType('navigation')?.[0]?.name||win.location.href;
 if(!skipSeasonWelcome(originalURL)&&!read('sessionStorage',seenKey()))show(doc.getElementById('siteHomeLogo'));
}
if(typeof document!=='undefined')mountSeasonalUI(document,window);
