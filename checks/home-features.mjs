import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {forecastSummary,localDate} from '../supabase/functions/cheongla-weather/forecast.mjs';
// Date boundaries use Korea's calendar even on a phone set to another timezone.
const code=fs.readFileSync(new URL('../home-clock.js',import.meta.url),'utf8');
const {koreaClockState,weatherAdvice,weatherAppearance}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
assert.equal(koreaClockState(new Date('2026-10-22T00:00:00Z')).countdown,'D-28');
assert.equal(koreaClockState(new Date('2026-11-18T14:59:59Z')).countdown,'D-1');
assert.equal(koreaClockState(new Date('2026-11-18T15:00:00Z')).countdown,'D-DAY');
assert.equal(koreaClockState(new Date('2026-11-19T15:00:00Z')).countdown,'D+1');
assert.equal(koreaClockState(new Date('2026-10-22T15:00:00Z')).period,'오전');
assert.equal(weatherAdvice({date:'2026-10-22',kind:'rain'},'2026-10-23'),'');
assert.match(weatherAdvice({date:'2026-10-22',kind:'snow'},'2026-10-22'),/눈/);
assert.equal(weatherAppearance('rain').text,'비');
assert.equal(weatherAppearance('<img src=x>').text,'예보 없음');
const now=new Date('2026-10-22T08:00:00Z');
const row=(time,temp,symbol)=>({time,data:{instant:{details:{air_temperature:temp}},next_1_hours:{summary:{symbol_code:symbol}}}});
const fixture={properties:{meta:{updated_at:now.toISOString()},timeseries:[row('2026-10-22T08:00:00Z',14.2,'clearsky_day'),row('2026-10-22T09:00:00Z',13.6,'rain'),row('2026-10-23T00:00:00Z',12,'cloudy'),row('2026-10-23T03:00:00Z',20.3,'fair_day')]}};
const summary=forecastSummary(fixture,now);assert.equal(summary.temperature,14);assert.equal(summary.daily[0].temperature,20);assert.equal(summary.advice.kind,'rain');assert.equal(localDate(new Date('2026-10-22T15:00:00Z')),'2026-10-23');
assert.throws(()=>forecastSummary(fixture,new Date('2026-11-22T08:00:00Z')),/Outdated/);
// Open, close, Escape, hidden-page playback and error behavior use actual module code.
const elements=Object.fromEntries(['homeTourDialog','homeTourVideo','homeTourOpen','homeTourClose','homeTourStatus'].map(id=>[id,{handlers:{},addEventListener(n,f){this.handlers[n]=f;},hasAttribute(){return !!this.src;},focus(){},getBoundingClientRect(){return {left:0,top:0,right:100,bottom:100};}}]));
const dialog=elements.homeTourDialog,video=elements.homeTourVideo;let plays=0,pauses=0;dialog.showModal=()=>dialog.open=true;dialog.close=()=>{dialog.open=false;dialog.handlers.close();};video.play=async()=>{plays++;};video.pause=()=>pauses++;
const doc={hidden:false,handlers:{},getElementById:id=>elements[id],addEventListener(n,f){this.handlers[n]=f;}};
vm.runInNewContext(fs.readFileSync(new URL('../home-tour.js',import.meta.url),'utf8'),{document:doc,window:{addEventListener(){}}});
assert.equal(video.src,undefined);await elements.homeTourOpen.handlers.click();assert.equal(dialog.open,true);assert.equal(plays,1);assert.match(video.src,/cheongla-tour.mp4$/);elements.homeTourClose.handlers.click();assert.equal(dialog.open,false);assert.equal(pauses,1);await elements.homeTourOpen.handlers.click();doc.hidden=true;doc.handlers.visibilitychange();assert.equal(pauses,2);video.handlers.error();assert.match(elements.homeTourStatus.textContent,/불러오지 못/);
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length);assert.match(html,/home-clock.js\?v=1.8.7/);assert.match(html,/controls muted playsinline preload="none"/);
console.log('Home clock, Korea date boundaries, weather validation and video lifecycle checks passed.');
