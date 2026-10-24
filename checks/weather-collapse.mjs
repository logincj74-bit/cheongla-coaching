import assert from 'node:assert/strict';
import {mountWeatherCollapse} from '../home-clock.js';
const scrolls=[];function node(){return {handlers:{},addEventListener(k,f){this.handlers[k]=f;},setAttribute(k,v){this[k]=v;},focus(options){assert.equal(options.preventScroll,true);}};}
const dialog=node(),toggle=node(),close=node(),win={scrollY:417,scrollX:0,scrollTo(p){scrolls.push(p);this.scrollY=p.top;}};
dialog.showModal=()=>dialog.open=true;dialog.close=()=>{dialog.open=false;dialog.handlers.close();};
const clock={querySelector:s=>({'#weatherForecastDialog':dialog,'#weatherForecastToggle':toggle,'#weatherForecastClose':close})[s]};
mountWeatherCollapse(clock,win);toggle.handlers.click();assert(dialog.open);assert.equal(toggle['aria-expanded'],'true');assert.equal(win.scrollY,417);
for(const target of ['icon','day','temperature','padding','close button','backdrop']){if(!dialog.open)toggle.handlers.click();let prevented=false;dialog.handlers.click({target,preventDefault(){prevented=true;}});assert(prevented&&!dialog.open);assert.equal(toggle['aria-expanded'],'false');assert.deepEqual(scrolls.at(-1),{top:417,left:0,behavior:'instant'});}
toggle.handlers.click();dialog.handlers.cancel({preventDefault(){}});assert(!dialog.open&&win.scrollY===417);
toggle.handlers.click();toggle.handlers.click();assert(!dialog.open);assert.equal(win.scrollY,417);
console.log('PASS weather modal: open keeps scroll; icons/day/padding/backdrop/Escape close; same toggle closes; original position and focus restored');
