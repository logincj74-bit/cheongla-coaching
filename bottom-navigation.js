/* Keep navigation in the fixed viewport layer, never in document scroll coordinates. */
(function(root){
 'use strict';
 const doc=root.document,bar=doc.getElementById('siteBackControls');
 if(!bar)return;
 if(bar.parentElement!==doc.body)doc.body.append(bar);
 // Clear geometry left by the former absolute-position workaround.
 bar.removeAttribute('data-viewport-anchored');
 for(const name of ['top','left','width','bottom','transform'])bar.style.removeProperty(name);
 let frame=0,keyboardSession=false,normalHeight=0,layoutWidth=0;
 const touch=()=>root.matchMedia?.('(any-pointer: coarse)').matches||root.navigator.maxTouchPoints>0;
 function editing(){
  const node=doc.activeElement;
  if(!touch()||!node||node.closest?.('[hidden],.account-section-inactive'))return false;
  if(node.isContentEditable||node.closest?.('[contenteditable="true"],.lr-document-toolbar,.lr-writing-tools'))return true;
  if(node.matches('textarea,select'))return true;
  return node.matches('input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="hidden"]):not([readonly]):not([disabled])');
 }
 function update(){
  frame=0;
  const vv=root.visualViewport,coarse=touch(),focused=editing();
  const width=root.innerWidth||doc.documentElement.clientWidth;
  const height=Math.max(root.innerHeight||0,doc.documentElement.clientHeight||0);
  const visibleHeight=vv?.height>0?vv.height:height;
  const zoomed=coarse&&(vv?.scale||1)>1.05;
  if(width!==layoutWidth){layoutWidth=width;normalHeight=height;}
  if(!zoomed)normalHeight=Math.max(normalHeight,height,focused?0:visibleHeight);
  if(focused)keyboardSession=true;
  // WebKit can retain the keyboard's smaller/panned viewport after focusout.
  // Keep the bar hidden until that transition completes, instead of placing it mid-page.
  const settling=coarse&&keyboardSession&&!zoomed&&(
   normalHeight-visibleHeight>Math.max(140,normalHeight*.2)||(vv?.offsetTop||0)>3);
  const hidden=focused||settling||zoomed;
  if(!focused&&!settling&&!zoomed)keyboardSession=false;
  bar.toggleAttribute('data-keyboard-hidden',hidden);
  if(bar.hidden||hidden)return;
  const barHeight=bar.getBoundingClientRect().height;
  if(barHeight>0)doc.documentElement.style.setProperty('--nav-reserved-size',(barHeight+20)+'px');
 }
 function schedule(){if(!frame)frame=root.requestAnimationFrame(update);}
 for(const name of ['resize','orientationchange','pageshow'])root.addEventListener(name,schedule,{passive:true});
 for(const name of ['resize','scroll'])root.visualViewport?.addEventListener(name,schedule,{passive:true});
 doc.addEventListener('focusin',schedule);
 doc.addEventListener('focusout',()=>{schedule();for(const delay of [100,300,700,1200])root.setTimeout(schedule,delay);});
 doc.addEventListener('touchend',schedule,{passive:true});
 doc.addEventListener('visibilitychange',schedule);
 new MutationObserver(schedule).observe(bar,{attributes:true,attributeFilter:['hidden']});
 if(root.ResizeObserver)new root.ResizeObserver(schedule).observe(bar);
 schedule();root.CheonglaBottomNavigation={refresh:schedule};
})(globalThis);
