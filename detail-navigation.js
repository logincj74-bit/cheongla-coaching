/* Keep newly opened content at its heading after sibling panels collapse. */
(()=>{
 let sequence=0;
 function align(node){
  if(!node)return;
  const ticket=++sequence;
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
   if(ticket!==sequence||node.isConnected===false)return;
   const details=node.tagName==='SUMMARY'?node.parentElement:null;
   if(details?.tagName==='DETAILS'&&!details.open)return;
   node.scrollIntoView({behavior:'instant',block:'start'});
  }));
 }
 function open(details){
  if(!details||details.tagName!=='DETAILS')return;
  for(const sibling of details.parentElement?.children||[])if(sibling!==details&&sibling.tagName==='DETAILS')sibling.open=false;
  details.open=true;align(details.querySelector('summary')||details);
 }
 document.addEventListener('click',event=>{
  if(event.defaultPrevented||event.button>0)return;
  const summary=event.target?.closest?.('summary'),details=summary?.parentElement;
  if(!summary||details?.tagName!=='DETAILS'||details.classList.contains('site-menu'))return;
  const control=event.target.closest('a,button,input,select,textarea');
  if(control&&summary.contains(control))return;
  event.preventDefault();
  if(details.open){details.open=false;return;}
  open(details);
 },true);
 globalThis.CheonglaDetailNavigation={align,open};
})();
