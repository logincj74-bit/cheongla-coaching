/* Anchor the navigation to the visible viewport, including iOS standalone mode.
   Document coordinates avoid WebKit's stale fixed-position viewport after input. */
(function(root){
 'use strict';
 const doc=root.document,bar=doc.getElementById('siteBackControls');
 if(!bar)return;
 if(bar.parentElement!==doc.body)doc.body.append(bar);
 let frame=0;
 const touch=()=>root.matchMedia?.('(pointer: coarse)').matches||root.navigator.maxTouchPoints>0;
 function editing(){
  const node=doc.activeElement;
  if(!touch()||!node)return false;
  if(node.isContentEditable||node.closest?.('[contenteditable="true"]'))return true;
  if(node.matches('textarea,select'))return true;
  return node.matches('input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="hidden"]):not([readonly]):not([disabled])');
 }
 function update(){
  frame=0;bar.toggleAttribute('data-keyboard-hidden',editing());
  if(bar.hidden||bar.hasAttribute('data-keyboard-hidden'))return;
  const vv=root.visualViewport;
  const width=vv?.width>0?vv.width:root.innerWidth;
  const height=vv?.height>0?vv.height:root.innerHeight;
  const pageTop=Number.isFinite(vv?.pageTop)?vv.pageTop:root.scrollY+(vv?.offsetTop||0);
  const pageLeft=Number.isFinite(vv?.pageLeft)?vv.pageLeft:root.scrollX+(vv?.offsetLeft||0);
  if(!(width>0&&height>0))return;
  bar.setAttribute('data-viewport-anchored','');
  const barWidth=Math.min(width,800);
  bar.style.width=barWidth+'px';bar.style.left=(pageLeft+(width-barWidth)/2)+'px';
  const barHeight=bar.getBoundingClientRect().height;
  bar.style.top=Math.max(0,pageTop+height-barHeight)+'px';
  doc.documentElement.style.setProperty('--nav-reserved-size',(barHeight+20)+'px');
 }
 function schedule(){if(!frame)frame=root.requestAnimationFrame(update);}
 for(const name of ['scroll','resize','orientationchange','pageshow'])root.addEventListener(name,schedule,{passive:true});
 for(const name of ['resize','scroll'])root.visualViewport?.addEventListener(name,schedule,{passive:true});
 doc.addEventListener('focusin',schedule);
 doc.addEventListener('focusout',()=>{schedule();for(const delay of [80,300,700])root.setTimeout(schedule,delay);});
 doc.addEventListener('visibilitychange',schedule);
 new MutationObserver(schedule).observe(bar,{attributes:true,attributeFilter:['hidden']});
 if(root.ResizeObserver)new ResizeObserver(schedule).observe(bar);
 schedule();root.CheonglaBottomNavigation={refresh:schedule};
})(globalThis);
