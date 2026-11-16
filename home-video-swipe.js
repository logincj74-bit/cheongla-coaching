/* Principal-only local swipe actions. A gesture reveals a button; it never deletes. */
(function(root){'use strict';
function mobile(){const n=root.navigator;return n.userAgentData?.mobile===true||/Android|iPhone|iPad|iPod/i.test(n.userAgent)||(/Mac/i.test(n.platform||'')&&n.maxTouchPoints>1);}
function mount({document:doc,allowed,enabled=mobile,isBusy=()=>false}){
 const entries=new Set();let opened=null,sequence=0;
 function close(){opened?.show(false);}
 function attach(node,{label,controls,onTrash}){
  if(!allowed())return;
  const action=doc.createElement('button');action.type='button';action.className='home-video-trash-action';
  action.setAttribute('aria-label',label+' 휴지통으로 이동');
  const icon=doc.createElementNS('http://www.w3.org/2000/svg','svg');icon.setAttribute('viewBox','0 0 24 24');icon.setAttribute('aria-hidden','true');
  const path=doc.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d','M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7');icon.append(path);
  const text=doc.createElement('span');text.textContent='삭제';action.append(icon,text);
  let working=false;
  async function trash(){if(working||isBusy()||!allowed())return;working=true;action.disabled=true;close();
   try{await onTrash();}finally{working=false;if(action.isConnected)action.disabled=!allowed();}
  }
  action.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();void trash();});
  if(!enabled()){
   action.classList.add('home-video-trash-inline');controls.append(action);
   const item={node,destroy(){action.remove();entries.delete(item);}};entries.add(item);return item;
  }
  const content=doc.createElement('div');content.className='home-video-swipe-content';content.append(...node.childNodes);
  const toggle=doc.createElement('button');toggle.type='button';toggle.className='secondary home-video-delete-toggle';toggle.textContent='삭제 메뉴';
  toggle.setAttribute('aria-label',label+' 삭제 메뉴 열기');toggle.setAttribute('aria-controls',action.id='homeVideoTrashAction-'+(++sequence));controls.append(toggle);
  const hint=doc.createElement('small');hint.className='home-video-swipe-hint';hint.textContent='← 왼쪽으로 밀면 삭제';controls.append(hint);
  node.dataset.homeVideoSwipe='true';node.append(content,action);
  let open=false,gesture=null,until=0;
  const width=88;
  function paint(offset){node.style.setProperty('--home-video-delete-offset',offset+'px');action.hidden=offset===0;action.tabIndex=open?0:-1;action.disabled=working||isBusy()||!open||!allowed();}
  function show(value){if(value&&!allowed())return;gesture=null;node.classList.remove('home-video-swiping');
   if(value&&opened&&opened!==item)opened.show(false);
   open=value;opened=value?item:opened===item?null:opened;toggle.setAttribute('aria-expanded',String(value));toggle.setAttribute('aria-label',label+(value?' 삭제 메뉴 닫기':' 삭제 메뉴 열기'));paint(value?-width:0);
  }
  function start(event){gesture=null;if(!allowed()||working||isBusy()||event.touches.length!==1||event.target.closest('input,textarea,select,a,video[controls],[contenteditable="true"],.home-video-trash-action'))return;
   const p=event.touches[0],viewport=root.visualViewport?.width||root.innerWidth;if(p.clientX<16||p.clientX>viewport-16)return;
   gesture={x:p.clientX,y:p.clientY,at:Date.now(),base:open?-width:0,locked:false,wasOpen:open};
  }
  function move(event){if(!gesture)return;if(event.touches.length!==1||!allowed()){show(open);return;}
   const p=event.touches[0],dx=p.clientX-gesture.x,dy=p.clientY-gesture.y;
   if(!gesture.locked&&Math.abs(dy)>8&&Math.abs(dy)>Math.abs(dx)*1.15){gesture=null;return;}
   if(!gesture.locked&&Math.abs(dx)>10&&Math.abs(dx)>Math.abs(dy)*1.2){if(dx>0&&!open){gesture=null;return;}gesture.locked=true;node.classList.add('home-video-swiping');}
   if(gesture.locked){if(event.cancelable)event.preventDefault();event.stopPropagation();paint(Math.max(-width,Math.min(0,gesture.base+dx)));}
  }
  function end(event){const g=gesture;if(!g)return;gesture=null;
   if(!g.locked||event.changedTouches.length!==1){show(g.wasOpen);return;}
   event.stopPropagation();const p=event.changedTouches[0],dx=p.clientX-g.x,dy=p.clientY-g.y;
   until=Date.now()+450;
   if(!allowed()||Math.abs(dx)<Math.abs(dy)*1.2){show(g.wasOpen);return;}
   if(g.wasOpen)show(dx<30);else show(dx<=-44||(dx<=-24&&Date.now()-g.at<220));
  }
  function cancel(){show(open);}
  function click(event){if(action.contains(event.target)||toggle.contains(event.target))return;
   if(Date.now()<until||open){event.preventDefault();event.stopImmediatePropagation();show(false);}
  }
  function key(event){if(event.key==='Escape'&&open){event.preventDefault();event.stopPropagation();show(false);toggle.focus();}}
  toggle.addEventListener('click',()=>show(!open));
  node.addEventListener('touchstart',start,{passive:true});node.addEventListener('touchmove',move,{passive:false});node.addEventListener('touchend',end,{passive:true});node.addEventListener('touchcancel',cancel,{passive:true});node.addEventListener('click',click,true);node.addEventListener('keydown',key);
  const item={node,show,destroy(){if(opened===item)opened=null;gesture=null;node.removeEventListener('touchstart',start);node.removeEventListener('touchmove',move);node.removeEventListener('touchend',end);node.removeEventListener('touchcancel',cancel);node.removeEventListener('click',click,true);node.removeEventListener('keydown',key);action.remove();toggle.remove();hint.remove();content.replaceWith(...content.childNodes);node.classList.remove('home-video-swiping');node.style.removeProperty('--home-video-delete-offset');delete node.dataset.homeVideoSwipe;entries.delete(item);}};
  entries.add(item);show(false);return item;
 }
 doc.addEventListener('touchstart',event=>{if(opened&&!opened.node.contains(event.target))close();},{capture:true,passive:true});
 doc.addEventListener('click',event=>{if(opened&&!opened.node.contains(event.target))close();},true);
 return{attach,close,clearWithin(container){for(const item of [...entries])if(container.contains(item.node))item.destroy();},reset(){for(const item of [...entries])item.destroy();}};
}
root.CheonglaHomeVideoSwipe={mount,mobile};
})(globalThis);
