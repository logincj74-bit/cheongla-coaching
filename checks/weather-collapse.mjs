import assert from 'node:assert/strict';
import {mountWeatherCollapse} from '../home-clock.js';
const handlers={},summary={focus(o){this.focused=o.preventScroll;}},details={open:false,querySelector:()=>summary},card={addEventListener:(k,f)=>handlers[k]=f},clock={querySelector:()=>details,closest:()=>card};
mountWeatherCollapse(clock);
function tap(inSummary=false){let prevented=false;handlers.click({target:{closest:()=>inSummary?summary:null},preventDefault(){prevented=true;}});return prevented;}
assert(!tap());assert(!details.open);
details.open=true;assert(!tap(true));assert(details.open);
for(const target of ['weather SVG','temperature','weekday','empty card padding','credit']){details.open=true;assert(tap(),target);assert(!details.open,target);assert(summary.focused);}
details.open=true;let prevented=false;handlers.keydown({key:'Escape',preventDefault(){prevented=true;}});assert(prevented&&!details.open);
console.log('PASS weather collapse: collapsed card unchanged; summary does not double-toggle; SVG/text/weekday/padding close; Escape and focus return');
