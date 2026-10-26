export const SEASONS = Object.freeze({
 autumn:{label:'CHEONGLA · AUTUMN',headline:'차곡차곡 쌓은 하루,\n단단해지는 나의 내일.',description:'깊어지는 가을,\n청라에서 나의 공부를 이어갑니다.',effect:'낙엽'},
 winter:{label:'CHEONGLA · WINTER',headline:'따뜻한 공간에서,\n단단해지는 나의 겨울.',description:'추운 겨울,\n공부의 온기를 만나는 곳.',effect:'눈'},
 spring:{label:'CHEONGLA · SPRING',headline:'새롭게 피어나는 봄,\n나의 가능성도 함께.',description:'설레는 시작,\n청라에서 나만의 봄을 피웁니다.',effect:'벚꽃'},
 summer:{label:'CHEONGLA · SUMMER',headline:'푸르게 자라는 여름,\n꾸준함이 실력이 됩니다.',description:'초록빛 담쟁이처럼,\n하루하루 더 넓은 세상으로.',effect:'물방울'}
});
export function seasonForDate(now=new Date()){
 const month=Number(new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Seoul',month:'numeric'}).format(now));
 return month>=3&&month<=5?'spring':month>=6&&month<=8?'summer':month>=9&&month<=11?'autumn':'winter';
}
export function skipSeasonWelcome(url){const u=new URL(url);return u.searchParams.has('push')||u.searchParams.has('page')||!!u.hash;}
const shapes={
 autumn:'<path d="m12 1-3 6-4-2 1 6H2l5 5-1 3 5-1v5h2v-5l5 1-1-3 5-5h-4l1-6-4 2Z"/><path d="M12 7v12m-5-8 5 4 5-4" fill="none" stroke="#765139" stroke-width=".8"/>',
 winter:'<circle cx="12" cy="12" r="8"/>',
 spring:'<path d="M12 22C-2 15 0 2 8 2l4 4 4-4c8 0 10 13-4 20Z"/><path d="M12 7q-3 7 0 14" fill="none" stroke="#ce7394" stroke-width=".7" opacity=".65"/>',
 summer:'<path d="M12 1C10 6 4 12 4 16a8 8 0 0 0 16 0c0-4-6-10-8-15Z"/><path d="M8 12q-3 5 1 7" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><path d="M17 4v5m-2.5-2.5h5" fill="none" stroke="#edfaff" stroke-width="1.3"/>'
};
const autumnShapes=[shapes.autumn,
 '<path d="M12 15.5C10.8 12.6 7.8 12 3 12.2 1.4 12.3.4 11.4 1 9.7L2 7.7Q2.2 6.5 3.4 6.3 3.5 5.1 4.9 4.9 5.2 3.7 6.8 3.6 7.8 2.3 9.2 2.5 10.5 1.5 11.3 2.5L12 3.8 12.7 2.5Q13.5 1.5 14.8 2.5 16.2 2.3 17.2 3.6 18.8 3.7 19.1 4.9 20.5 5.1 20.6 6.3 21.8 6.5 22 7.7L23 9.7C23.6 11.4 22.6 12.3 21 12.2 16.2 12 13.2 12.6 12 15.5Z"/><path d="M12 14.8C12 18 11.3 20.8 10.7 23" fill="none" stroke="#c49108" stroke-width="1" stroke-linecap="round"/><path d="m12 14-8-6m8 6L6 5.5m6 8.5L9 4m3 10V5m0 9 3-10m-3 10 6-8.5m-6 8.5 8-6" fill="none" stroke="#c69b0c" stroke-width=".45" opacity=".75"/>',
 '<path d="M12 21C0 16 2 3 18 1c5 10 0 17-6 20Z"/><path d="m18 2-7 21m4-15-7 2m5 4 6-3" fill="none" stroke="#754c29" stroke-width=".8"/>'];
export function autumnParticle(index){const shape=index%3;return {kind:['maple','ginkgo','oval'][shape],svg:autumnShapes[shape],color:shape===1?['#f6c900','#eab600'][Math.floor(index/3)%2]:['#cb3929','#99502d','#dfa008','#b82f26'][Math.floor(index/3)%4]};}
export function particleSettings(index,season){
 const snow=season==='winter';return {x:((index*47+13)%101)+'%',size:(snow?5+index%5:10+(index*7)%12)+'px',opacity:String(snow ? .4+(index%4)*.12 : season==='autumn' ? .78+(index%4)*.06 : .55+(index%4)*.1),duration:(14+(index*3)%13)+'s',delay:-(index*1.7%25)+'s',spin:(4+index%6)+'s',sway:(index%2?1:-1)*(24+index*7%65)+'px'};
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
 const homeVisible=()=>!doc.getElementById('homePanel')?.hidden;
 const pause=()=>{for(const surface of surfaces){const away=surface.id==='homeSeasonEffects'&&!homeVisible();surface.hidden=away;surface.dataset.paused=String(doc.hidden||away||(surface!==dialog&&dialog.open));}};
 const particles=()=>{
  const enabled=!off&&!reduced.matches;
  for(const surface of surfaces){
   surface.dataset.motion=enabled?'on':'off';
   const layer=surface.querySelector('[data-season-particles]');layer.replaceChildren();if(!enabled)continue;
   const count=surface===dialog?22:20;
   for(let i=0;i<count;i++){
    const leaf=doc.createElement('span'),settings=particleSettings(i,season);leaf.className='season-particle';
    for(const [key,value] of Object.entries(settings))leaf.style.setProperty('--'+key,value);
    const autumn=season==='autumn'?autumnParticle(i):null;if(autumn){leaf.dataset.leaf=autumn.kind;leaf.style.setProperty('--particle-color',autumn.color);}
    leaf.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'+(autumn?.svg||shapes[season])+'</svg>';
    layer.append(leaf);
   }
  }
  for(const button of buttons){button.disabled=reduced.matches;button.setAttribute('aria-pressed',String(enabled));button.textContent=reduced.matches?'기기 설정에 따라 효과 꺼짐':SEASONS[season].effect+' 효과 '+(enabled?'끄기':'켜기');}
  pause();
 };
 const updateSeason=()=>{
  const next=Object.hasOwn(SEASONS,win.CheonglaSeasonMode)?win.CheonglaSeasonMode:seasonForDate();if(next===season)return;
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
 win.CheonglaSeasonal={setMode(mode){win.CheonglaSeasonMode=Object.hasOwn(SEASONS,mode)?mode:'auto';updateSeason();},getMode(){return win.CheonglaSeasonMode||'auto';}};
 updateSeason();
 const home=doc.getElementById('homePanel');if(home&&win.MutationObserver)new win.MutationObserver(pause).observe(home,{attributes:true,attributeFilter:['hidden']});
 const originalURL=win.performance?.getEntriesByType('navigation')?.[0]?.name||win.location.href;
 if(!skipSeasonWelcome(originalURL)&&!read('sessionStorage',seenKey()))show(doc.getElementById('siteHomeLogo'));
}
if(typeof document!=='undefined')mountSeasonalUI(document,window);
