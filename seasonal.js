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
export function skipSeasonWelcome(url){const u=new URL(url);return ['push','page','notification','notification_id','destination','target','type','code','token_hash','error'].some(k=>u.searchParams.has(k))||!!u.hash;}
export function welcomeDay(now=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(now);}
export function welcomeAudience(p){if(p?.approval_status!=='approved'||p?.membership_state==='withdrawn')return 'guest';if(p.role==='student'||p.role==='parent')return p.role;return ['owner','english_director','math_director','manager','korean_teacher'].includes(p.role)?'staff':'guest';}
export const WELCOME_CARDS=[
 ['morning-desk','오늘의 한 걸음','햇살이 드는 책상과 노트','지금 할 수 있는 작은 공부부터 시작해요.\n그 한 걸음이면 충분합니다.','오늘도 아이의 작은 노력을 알아봐 주세요.\n따뜻한 한마디가 든든한 힘이 됩니다.','세심하게 살피는 한 번의 관심이\n학생의 하루를 단단하게 만듭니다.'],
 ['forest','나만의 속도로','아침 햇살이 비치는 숲길','다른 사람의 속도보다\n오늘 나의 한 걸음에 집중해요.','아이마다 자라는 속도는 다릅니다.\n곁에서 지켜보는 믿음을 전해주세요.','서두르지 않고 한 사람씩 살피는 일.\n그 꾸준함이 청라의 힘입니다.'],
 ['sea','다시 시작하는 마음','잔잔한 아침 바다','어제의 아쉬움은 잠시 내려두고\n오늘의 첫 문제를 만나봐요.','결과를 묻기 전에 오늘의 마음을 물어봐 주세요.\n그 대화에서 새로운 힘이 시작됩니다.','어제보다 조금 더 편안한 배움의 하루를\n오늘도 함께 만들어갑니다.'],
 ['seedling','보이지 않아도 자라요','작은 화분에서 자라는 새싹','잘 풀리지 않는 날에도\n쌓이고 있는 실력은 있습니다.','당장 보이지 않는 변화도 자라고 있습니다.\n아이의 시간을 믿고 응원해주세요.','눈에 띄지 않는 작은 도움도\n학생에게는 오래 남는 지지가 됩니다.'],
 ['mountain','한 걸음씩, 단단하게','아침 안개가 감도는 산 능선','큰 목표는 작은 실천으로 가까워집니다.\n오늘 할 수 있는 것부터 차근차근 해요.','먼 목표보다 오늘 해낸 한 가지를\n함께 기뻐해주세요.','작은 약속을 지키는 하루가 쌓여\n믿고 맡기는 청라를 만듭니다.'],
 ['spring','가능성이 피어나는 날','옅은 분홍빛 벚꽃이 핀 길','아직 피어나지 않은 가능성이 있어요.\n오늘의 배움으로 조금씩 펼쳐봐요.','아이의 가능성은 한 번의 점수보다 넓습니다.\n잘하는 것과 좋아하는 것도 함께 봐주세요.','서로 다른 가능성이 피어나는 공간.\n오늘도 그 곁을 함께 지킵니다.'],
 ['summer','잠깐 숨을 고르고','이슬이 반짝이는 초록 잎','마음이 복잡하면 잠깐 숨을 고르세요.\n다시 한 문제부터 시작하면 됩니다.','공부 이야기만큼 쉼과 일상도 소중합니다.\n오늘은 편안한 안부를 건네주세요.','바쁜 중에도 잠깐 숨을 고르세요.\n차분한 마음이 세심한 돌봄으로 이어집니다.'],
 ['autumn','차곡차곡 쌓이는 하루','노란 은행잎이 내려앉은 가을 길','완벽한 하루보다 꾸준한 하루.\n오늘 쌓은 공부를 소중히 여겨요.','성실하게 보낸 하루를 알아주는 말이\n내일도 이어갈 용기가 됩니다.','매일의 작은 기록과 확인이\n학생의 안정적인 하루를 받쳐줍니다.'],
 ['winter','따뜻하게, 꾸준하게','창밖으로 눈이 내리는 따뜻한 공간','춥고 긴 날에도 나의 시간은 자랍니다.\n오늘도 나를 위한 공부를 이어가요.','따뜻한 식사와 다정한 안부처럼\n익숙한 응원이 아이를 지켜줍니다.','공부에 집중할 수 있는 따뜻한 공간을\n오늘도 함께 지켜주셔서 감사합니다.'],
 ['library','질문에서 시작되는 배움','햇살이 드는 조용한 서가','모르는 것을 발견했다면 한 걸음 나아간 거예요.\n질문하고, 다시 이해해봐요.','무엇을 몰랐는지 말할 수 있도록\n판단보다 경청을 먼저 전해주세요.','편하게 질문할 수 있는 분위기가\n학생의 배움을 더 깊게 만듭니다.'],
 ['river','작은 흐름이 모이면','맑은 물이 흐르는 숲속 개울','짧은 집중도 모이면 큰 힘이 됩니다.\n지금 이 시간에 마음을 모아봐요.','작은 습관이 이어지도록\n꾸준히 응원하는 마음을 전해주세요.','각자의 자리에서 이어가는 수고가 모여\n청라의 하루를 움직입니다.'],
 ['sky','내일을 향한 오늘','푸른 하늘과 부드러운 구름','오늘의 나에게 성실했던 시간은 남습니다.\n나의 내일을 위해 다시 시작해요.','아이의 내일을 함께 바라보며\n오늘의 노력을 따뜻하게 안아주세요.','학생의 더 나은 내일을 위해\n오늘도 함께해주셔서 감사합니다.']
];
export function welcomeCard(now=new Date(),audience='guest'){const day=welcomeDay(now),index=((Math.floor(Date.parse(day+'T00:00:00Z')/86400000)%12)+12)%12,c=WELCOME_CARDS[index];return {index,day,image:'assets/daily-welcome/'+String(index+1).padStart(2,'0')+'-'+c[0]+'.webp',title:c[1],alt:c[2],body:audience==='parent'?c[4]:audience==='staff'?c[5]:audience==='student'?c[3]:'작은 배움이 쌓여 더 넓은 내일이 됩니다.\n청라와 함께 오늘의 한 걸음을 시작해요.'};}
function dailyWelcome(doc,dialog,start){
 if(!doc.head)return ()=>{};
 const link=doc.createElement('link');link.rel='stylesheet';link.href='daily-welcome.css?v=1.9.44';doc.head.append(link);
 const el=(tag,cls,text)=>{const n=doc.createElement(tag);n.className=cls;if(text)n.textContent=text;return n;};
 const card=el('article','daily-welcome-card'),brand=el('div','daily-welcome-brand','독학재수학원 청라'),image=el('img','daily-welcome-image'),copy=el('div','daily-welcome-copy'),date=el('p','daily-welcome-date'),title=el('h2','daily-welcome-title'),body=el('p','daily-welcome-message'),signature=el('p','daily-welcome-signature','청라가 당신의 오늘을 응원합니다.');
 title.id='seasonWelcomeTitle';body.id='seasonWelcomeDescription';image.decoding='async';image.fetchPriority='high';image.width=1200;image.height=800;image.addEventListener('error',()=>{image.hidden=true;});
 start.textContent='오늘도 시작하기';start.className='daily-welcome-start';start.type='button';copy.append(date,title,body,start,signature);card.append(brand,image,copy);dialog.replaceChildren(card);dialog.classList?.add('daily-welcome');
 let current='';return ()=>{let p;try{p=typeof currentProfile!=='undefined'?currentProfile:null;}catch{}const audience=welcomeAudience(p),c=welcomeCard(new Date(),audience),key=c.day+'|'+audience;if(key===current)return;current=key;date.textContent=c.day.replaceAll('-','. ')+' · 오늘의 응원';title.textContent=c.title;body.textContent=c.body;image.hidden=false;image.src=c.image;image.alt=c.alt;};
}

const shapes={
 autumn:'<path d="m12 1-3 6-4-2 1 6H2l5 5-1 3 5-1v5h2v-5l5 1-1-3 5-5h-4l1-6-4 2Z"/><path d="M12 7v12m-5-8 5 4 5-4" fill="none" stroke="#765139" stroke-width=".8"/>',
 winter:'<circle cx="12" cy="12" r="8"/>',
 spring:'<path d="M12 22C-2 15 0 2 8 2l4 4 4-4c8 0 10 13-4 20Z"/><path d="M12 7q-3 7 0 14" fill="none" stroke="#ce7394" stroke-width=".7" opacity=".65"/>',
 summer:'<path d="M12 1C10 6 4 12 4 16a8 8 0 0 0 16 0c0-4-6-10-8-15Z"/><path d="M8 12q-3 5 1 7" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><path d="M17 4v5m-2.5-2.5h5" fill="none" stroke="#edfaff" stroke-width="1.3"/>'
};
const autumnShapes=[shapes.autumn,
 '<path d="M12 15.5C10.8 12.6 7.8 12 3 12.2 1.4 12.3.4 11.4 1 9.7L2 7.7Q2.2 6.5 3.4 6.3 3.5 5.1 4.9 4.9 5.2 3.7 6.8 3.6 7.8 2.3 9.2 2.5 10.5 1.5 11.3 2.5L12 3.8 12.7 2.5Q13.5 1.5 14.8 2.5 16.2 2.3 17.2 3.6 18.8 3.7 19.1 4.9 20.5 5.1 20.6 6.3 21.8 6.5 22 7.7L23 9.7C23.6 11.4 22.6 12.3 21 12.2 16.2 12 13.2 12.6 12 15.5Z"/><path d="M12 14.8C12 18 11.3 20.8 10.7 23" fill="none" stroke="#c49108" stroke-width="1" stroke-linecap="round"/><path d="m12 14-8-6m8 6L6 5.5m6 8.5L9 4m3 10V5m0 9 3-10m-3 10 6-8.5m-6 8.5 8-6" fill="none" stroke="#c69b0c" stroke-width=".45" opacity=".75"/>',
 '<path d="M12 21C0 16 2 3 18 1c5 10 0 17-6 20Z"/><path d="m18 2-7 21m4-15-7 2m5 4 6-3" fill="none" stroke="#754c29" stroke-width=".8"/>'];
export function autumnParticle(index){const shape=index%3,palette=Math.floor(index/3)%4;return {kind:['maple','ginkgo','oval'][shape],svg:autumnShapes[shape],color:shape===1?['#ffda00','#ffc800'][Math.floor(index/3)%2]:['#f34435','#a96135','#ffca18','#ed3045'][palette],shade:shape===1?'#e9ae00':['#ce2530','#88502c','#eda609','#c91f38'][palette]};}
// Original botanical shapes and optical shading; no reference-photo pixels are used.
const petalOutlines=[
 'M8 23C3 20 .5 13 3 7 4.3 3.2 7.5 1 11 1.5L12.4 4 14.1 2C18.4 3.1 21.5 7 20.5 12 19.2 18 13.6 22.2 8 23Z',
 'M7 22C2.6 18.4 1.5 12 4.3 6.5 6.2 3 9 1.2 12 2L13.1 4.2 15.4 2.8C20.3 6 21.1 11.5 17.5 16.4 14.6 20.2 10.1 22.2 7 22Z',
 'M6.5 22.5C1.3 17.3 3.1 7 9 2.6 11 .9 13.4 1.5 14.7 3.1L15 5.2 17.2 4C22.4 9.1 19.2 16.8 12.6 20.8 10.7 22 8.5 22.8 6.5 22.5Z'];
export function naturalParticle(index,season,prefix='fx'){
 const id=prefix+'-'+season+'-'+index;
 if(season==='spring')return '<defs><radialGradient id="'+id+'" cx="30%" cy="20%" r="90%"><stop stop-color="#fffafc"/><stop offset=".42" stop-color="#fce3eb"/><stop offset=".8" stop-color="#efadc3"/><stop offset="1" stop-color="#d57f9e"/></radialGradient></defs><path d="'+petalOutlines[index%3]+'" fill="url(#'+id+')" stroke="#d78ca6" stroke-opacity=".45" stroke-width=".35"/><g fill="none" stroke="#cf7796" stroke-opacity=".25" stroke-width=".35"><path d="M8 22Q14 13 12.5 4M8 22Q5 11 6.5 6M8 22Q18 15 18 8"/></g><path d="M5 8Q3 15 7 19" fill="none" stroke="#fff" stroke-opacity=".65" stroke-width=".7"/>';
 if(season==='summer')return '<defs><radialGradient id="'+id+'" cx="32%" cy="28%" r="80%"><stop stop-color="#f7fdff" stop-opacity=".9"/><stop offset=".3" stop-color="#a6e5f5" stop-opacity=".2"/><stop offset=".68" stop-color="#53b7d6" stop-opacity=".4"/><stop offset=".9" stop-color="#268daf" stop-opacity=".7"/><stop offset="1" stop-color="#e3faff" stop-opacity=".9"/></radialGradient></defs><path d="M12 2C10.5 6 5 11 5 15.5a7 7 0 0 0 14 0C19 11 13.5 6 12 2Z" fill="url(#'+id+')" stroke="#55a9c6" stroke-width=".45"/><ellipse cx="9" cy="12" rx="1.4" ry="2.7" transform="rotate(30 9 12)" fill="#fff" opacity=".88"/><path d="M10 20q4 1 6-3" fill="none" stroke="#e7fcff" stroke-width=".8" opacity=".8"/>';
 if(season==='winter'){if(index%5===0)return '<g stroke="#bad8e7" stroke-width="1.1" stroke-linecap="round" fill="none"><path d="M12 2v20M3.3 7l17.4 10M3.3 17 20.7 7M9 4l3 3 3-3M9 20l3-3 3 3M4 10l4-1-1-4M17 19l-1-4 4-1M4 14l4 1-1 4M17 5l-1 4 4 1"/></g>';return '<defs><radialGradient id="'+id+'"><stop stop-color="#fff"/><stop offset=".6" stop-color="#f4fbff" stop-opacity=".95"/><stop offset="1" stop-color="#97bccf" stop-opacity=".35"/></radialGradient></defs><circle cx="12" cy="12" r="8" fill="url(#'+id+')" stroke="none"/>';}
 const leaf=autumnParticle(index);return '<defs><linearGradient id="'+id+'" x2=".9" y2="1"><stop stop-color="'+leaf.color+'"/><stop offset="1" stop-color="'+leaf.shade+'"/></linearGradient></defs>'+leaf.svg.replace('<path ','<path fill="url(#'+id+')" ');
}
export function particleSettings(index,season,options={}){
 const snow=season==='winter';return {x:((index*47+13)%101)+'%',size:(snow?7+(index%7)*1.2:season==='spring'?14+(index*7)%12:10+(index*7)%12)+'px',opacity:String(snow ? .4+(index%4)*.12 : season==='autumn' ? .78+(index%4)*.06 : .55+(index%4)*.1),duration:((14+(index*3)%13)*({slow:1.5,normal:1,fast:.7}[options.speed]||1))+'s',delay:-(index*1.7%25)+'s',spin:(4+index%6)+'s',sway:(index%2?1:-1)*(24+index*7%65)+'px',tilt:((index*53)%180-90)+'deg',aspect:String(season==='spring'?.65+(index%4)*.1:1)};
}
export function particleCount(options={},welcome=false){return Math.round((welcome?22:20)*({light:.55,normal:1,rich:1.6}[options.amount]||1));}
export function mountSeasonalUI(doc,win){
 const dialog=doc.getElementById('seasonWelcome'),open=doc.getElementById('seasonWelcomeOpen'),start=doc.getElementById('seasonWelcomeStart');
 if(!dialog||!start||dialog.dataset.ready)return;
 dialog.dataset.ready='true';
 const drawWelcome=dailyWelcome(doc,dialog,start);const surfaces=[...doc.querySelectorAll('[data-season-surface]')],buttons=[...doc.querySelectorAll('[data-season-motion]')].filter(b=>!dialog.contains?.(b));
 const reduced=win.matchMedia('(prefers-reduced-motion: reduce)');
 const read=(store,key)=>{try{return win[store].getItem(key);}catch{return null;}};
 const write=(store,key,value)=>{try{win[store].setItem(key,value);}catch{}};
 let season='',renderKey='',lastTrigger=null,off=read('localStorage','cheongla-season-motion')==='off';
 const homeVisible=()=>!doc.getElementById('homePanel')?.hidden;
 const pause=()=>{for(const surface of surfaces){const away=surface.id==='homeSeasonEffects'&&!homeVisible();surface.hidden=away;surface.dataset.paused=String(doc.hidden||away||(surface!==dialog&&dialog.open));}};
 const particles=()=>{
  const enabled=!off&&!reduced.matches;
  for(const surface of surfaces){
   surface.dataset.motion=enabled?'on':'off';
   const layer=surface.querySelector('[data-season-particles]');if(surface===dialog){layer?.replaceChildren();continue;}if(!layer)continue;layer.replaceChildren();if(!enabled)continue;
   const options=win.CheonglaSeasonOptions?.[season]||{};const count=particleCount(options,surface===dialog);
   for(let i=0;i<count;i++){
    const leaf=doc.createElement('span'),settings=particleSettings(i,season,options);leaf.className='season-particle';
    for(const [key,value] of Object.entries(settings))leaf.style.setProperty('--'+key,value);
    const autumn=season==='autumn'?autumnParticle(i):null;if(autumn){leaf.dataset.leaf=autumn.kind;leaf.style.setProperty('--particle-color',autumn.color);}
    leaf.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'+naturalParticle(i,season,surface===dialog?'welcome':'home')+'</svg>';
    layer.append(leaf);
   }
  }
  for(const button of buttons){button.disabled=reduced.matches;button.setAttribute('aria-pressed',String(enabled));button.textContent=reduced.matches?'기기 설정에 따라 효과 꺼짐':SEASONS[season].effect+' 효과 '+(enabled?'끄기':'켜기');}
  pause();
 };
 const updateSeason=()=>{
  const next=Object.hasOwn(SEASONS,win.CheonglaSeasonMode)?win.CheonglaSeasonMode:seasonForDate();const key=next+'|'+JSON.stringify(win.CheonglaSeasonOptions?.[next]||{});if(key===renderKey)return;renderKey=key;
  season=next;const copy=SEASONS[season];
  for(const surface of surfaces){surface.dataset.season=season;for(const [key,selector] of [['label','[data-season-label]'],['headline','[data-season-headline]'],['description','[data-season-description]']])for(const node of surface.querySelectorAll(selector))node.textContent=copy[key];}
  particles();
 };
 let shownDay='';const seenKey=day=>'cheongla-daily-welcome:v1:'+day;const wasSeen=day=>read('localStorage',seenKey(day))==='seen'||read('sessionStorage',seenKey(day))==='seen'||win.CheonglaWelcomeSeenDay===day;
 const show=trigger=>{
  if(dialog.open||doc.querySelector('dialog[open]'))return;
  lastTrigger=trigger;shownDay=welcomeDay();drawWelcome();
  try{dialog.showModal();doc.body.classList.add('season-welcome-open');pause();}catch{doc.body.classList.remove('season-welcome-open');}
 };
 const finished=()=>{const day=shownDay||welcomeDay();write('localStorage',seenKey(day),'seen');write('sessionStorage',seenKey(day),'seen');win.CheonglaWelcomeSeenDay=day;doc.body.classList.remove('season-welcome-open');pause();lastTrigger?.focus({preventScroll:true});};
 open?.addEventListener('click',()=>show(open));
 start.addEventListener('click',()=>dialog.close());
 dialog.addEventListener('close',finished);
 for(const button of buttons)button.addEventListener('click',()=>{if(reduced.matches)return;off=!off;write('localStorage','cheongla-season-motion',off?'off':'on');particles();});
 reduced.addEventListener('change',particles);
 doc.addEventListener('visibilitychange',()=>{if(!doc.hidden)updateSeason();pause();});
 win.addEventListener('pagehide',()=>{for(const surface of surfaces)surface.dataset.paused='true';});
 win.addEventListener('pageshow',()=>{updateSeason();pause();});
 win.setInterval(()=>{if(!doc.hidden)updateSeason();},60000);win.setInterval(()=>{if(dialog.open)drawWelcome();},750);
 win.CheonglaSeasonal={setSettings(value){win.CheonglaSeasonOptions=value.effect_options||{};this.setMode(value.mode);},setMode(mode){win.CheonglaSeasonMode=Object.hasOwn(SEASONS,mode)?mode:'auto';updateSeason();},getMode(){return win.CheonglaSeasonMode||'auto';}};
 updateSeason();
 const home=doc.getElementById('homePanel');if(home&&win.MutationObserver)new win.MutationObserver(pause).observe(home,{attributes:true,attributeFilter:['hidden']});
 const originalURL=win.performance?.getEntriesByType('navigation')?.[0]?.name||win.location.href;
 if(!skipSeasonWelcome(originalURL)&&!wasSeen(welcomeDay()))show(doc.getElementById('academyHome')||doc.getElementById('siteHomeLogo'));
}
if(typeof document!=='undefined')mountSeasonalUI(document,window);
