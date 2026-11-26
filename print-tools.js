/* Local print previews only. No document data is uploaded or persisted. */
(function(root){'use strict';let preview=null,restorePrintTitle=null;
const css=`*{box-sizing:border-box}body{font:15px/1.75 -apple-system,BlinkMacSystemFont,'Malgun Gothic',sans-serif;color:#203e42;background:white;margin:0;padding:28px;overflow-wrap:anywhere}h1{font-size:24px}h2{font-size:19px;border-bottom:1px solid #cbd9d0;padding-bottom:8px}h3,h4{break-after:avoid}p{white-space:pre-wrap}table{border-collapse:collapse;width:100%}td,th{border:1px solid #aabdb0;padding:8px;text-align:left}article,section{margin:18px 0;padding:12px;border:1px solid #dce4dc;border-radius:8px}button,input,textarea,select,nav,script,style{display:none!important}img{max-width:100%;height:auto}.print-value{white-space:pre-wrap;overflow-wrap:anywhere}summary{font-weight:700}details{margin:12px 0}details:not([open])>:not(summary){display:none}.print-brand{display:flex;align-items:center;gap:12px;border-bottom:1px solid #cbd9d0;padding-bottom:8px;break-inside:avoid;break-after:avoid}.print-brand img{width:44px;height:44px}.print-meta{color:#566f61;font-size:12px}@page{size:A4;margin:15mm}@media print{body{padding:0;font-size:11pt}.no-print{display:none!important}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}tr{break-inside:avoid}a{color:inherit;text-decoration:none}}`;
function clear(){restorePrintTitle?.();if(preview){preview.cleanup?.();preview.remove();preview=null;}}
function visibleSnapshot(node,doc){if(node.nodeType===3)return doc.createTextNode(node.textContent);if(node.nodeType!==1)return null;const tag=node.tagName.toLowerCase();if(node.hidden||['button','script','style','nav','dialog'].includes(tag)||node.hasAttribute?.('data-no-print'))return null;if(root.getComputedStyle&&root.getComputedStyle(node).display==='none')return null;
 if(['input','select','textarea'].includes(tag)){if(['password','hidden','file'].includes(node.type))return null;const n=doc.createElement('span');n.className='print-value';n.textContent=node.type==='checkbox'||node.type==='radio'?(node.checked?'☑':'☐'):tag==='select'?(node.selectedOptions?.[0]?.textContent||node.value):node.value;return n;}
 const n=doc.createElement(['form','label'].includes(tag)?'div':tag);if(node.style?.color)n.style.color=node.style.color;if(tag==='details')n.open=node.open;if(tag==='img'){n.src=node.currentSrc||node.src;n.alt=node.alt;}if(tag==='a'){n.textContent=node.textContent;return n;}for(const child of node.childNodes){const c=visibleSnapshot(child,doc);if(c)n.append(c);}return n;}
let pdfModule;
function loadPdf(){
 if(root.CheonglaPrintPDF)return Promise.resolve(root.CheonglaPrintPDF);
 if(!pdfModule)pdfModule=new Promise((resolve,reject)=>{
  const script=root.document.createElement('script');script.src=new URL('print-pdf.js?v=1',root.document.baseURI).href;
  script.onload=()=>root.CheonglaPrintPDF?resolve(root.CheonglaPrintPDF):fail();script.onerror=fail;
  function fail(){script.remove();pdfModule=null;reject(Error('PDF 기능을 불러오지 못했습니다. 다시 눌러 주세요.'));}
  root.document.head.append(script);
 });
 return pdfModule;
}
function open(title,build,filename){
 clear();
 const doc=root.document,dialog=doc.createElement('dialog');
 dialog.setAttribute('aria-label','인쇄 미리보기');
 dialog.style.cssText='width:min(1000px,96vw);height:92dvh;max-height:92dvh;border:1px solid #b7cbc0;border-radius:18px;padding:16px;background:#fff;color:#203e42;display:flex;flex-direction:column;box-sizing:border-box';
 const bar=doc.createElement('div'),label=doc.createElement('strong'),print=doc.createElement('button'),close=doc.createElement('button'),pdf=doc.createElement('button'),feedback=doc.createElement('p'),links=doc.createElement('div'),frame=doc.createElement('iframe');
 label.textContent='인쇄 미리보기 · '+title;label.style.cssText='width:100%;overflow-wrap:anywhere';bar.style.cssText='display:flex;flex-wrap:wrap;gap:8px;flex-shrink:0';
 print.textContent='인쇄';close.textContent='닫기';pdf.textContent='PDF 파일 만들기';pdf.dataset.pdfExport='true';print.type=close.type=pdf.type='button';print.disabled=true;
 feedback.textContent='휴대폰·아이패드: PDF 파일 만들기 → PDF 저장·공유 → 파일에 저장을 선택하세요.';feedback.style.cssText='font-size:14px;line-height:1.5;flex-shrink:0';feedback.setAttribute('role','status');
 links.hidden=true;links.style.cssText='display:flex;flex-wrap:wrap;gap:16px;flex-shrink:0';
 frame.title='인쇄할 문서';frame.style.cssText='display:block;width:100%;flex:1;min-height:100px;border:0;margin-top:12px;background:white';
 bar.append(label,print,close,pdf);dialog.append(bar,feedback,links,frame);doc.body.append(dialog);preview=dialog;dialog.showModal();
 const out=frame.contentDocument;out.open();out.write('<!doctype html><html lang="ko"><head><meta charset="utf-8"><title></title></head><body></body></html>');out.close();out.title=filename||title;
 const style=out.createElement('style');style.textContent=css;out.head.append(style);
 const brand=root.CheonglaDocumentBrand,letterhead=out.createElement('header'),logo=out.createElement('img'),academy=out.createElement('strong');
 letterhead.className='print-brand';logo.alt='청라 로고';academy.textContent=brand.name;letterhead.append(logo,academy);out.body.append(letterhead);
 logo.addEventListener('load',()=>{print.disabled=false;});logo.addEventListener('error',()=>{print.disabled=false;feedback.textContent='로고를 불러오지 못했지만 문서를 인쇄하거나 PDF로 저장할 수 있습니다.';});logo.src=brand.logoUrl;
 const h=out.createElement('h1');h.textContent=title;const stamp=out.createElement('p');stamp.className='print-meta';stamp.textContent='출력 준비 '+new Date().toLocaleString('ko-KR',{timeZone:'Asia/Seoul'});out.body.append(h,stamp);build(out.body,out);
 const name=String(filename||title).replace(/[\\/:*?"<>|]/g,'_').slice(0,120).replace(/\.pdf$/i,'')+'.pdf';
 let file=null,url=null,disposed=false;
 dialog.cleanup=()=>{disposed=true;file=null;if(url){root.URL.revokeObjectURL(url);url=null;}};
 function alive(){return !disposed&&preview===dialog&&dialog.isConnected;}
 pdf.addEventListener('click',async()=>{
  if(file){
   // This click starts sharing synchronously: async generation on the previous click
   // must not consume the transient activation required by iOS/iPadOS.
   let supported=false;try{supported=!!root.navigator.share&&!!root.navigator.canShare?.({files:[file]});}catch{}
   if(supported){try{await root.navigator.share({files:[file]});if(alive())feedback.textContent='저장·공유 메뉴 처리가 끝났습니다. 파일 앱에서 저장 결과를 확인해 주세요.';}catch(error){if(alive())feedback.textContent=error.name==='AbortError'?'저장을 취소했습니다. 다시 누르거나 아래 링크를 이용할 수 있습니다.':'공유 메뉴를 열지 못했습니다. 아래 PDF 열기 또는 다운로드를 눌러 주세요.';}}
   else{links.querySelector('[download]').click();feedback.textContent='PDF 다운로드를 요청했습니다. PDF가 열리면 공유 메뉴에서 파일에 저장을 선택하세요.';}
   return;
  }
  pdf.disabled=true;feedback.textContent='PDF 파일을 만드는 중입니다… 문서 내용은 외부로 전송하지 않습니다.';
  try{
   const module=await loadPdf();if(!alive())return;const blob=await module.create(out);if(!alive())return;
   if(blob.type!=='application/pdf'||!blob.size)throw Error('PDF 파일을 만들지 못했습니다.');
   file=new root.File([blob],name,{type:'application/pdf'});url=root.URL.createObjectURL(blob);
   const download=doc.createElement('a'),view=doc.createElement('a');download.href=view.href=url;download.download=name;download.textContent='PDF 다운로드';view.textContent='PDF 열기';view.target='_blank';view.rel='noopener';links.append(view,download);links.hidden=false;
   pdf.textContent='PDF 저장·공유';feedback.textContent='PDF 준비 완료. PDF 저장·공유를 누르고 파일에 저장을 선택하세요. 공유 메뉴가 없으면 아래 PDF 열기 또는 다운로드를 이용하세요.';
  }catch(error){if(alive())feedback.textContent=error.message||'PDF를 만들지 못했습니다. 인쇄 메뉴를 이용해 주세요.';}
  finally{if(alive())pdf.disabled=false;}
 });
 print.addEventListener('click',()=>{restorePrintTitle?.();if(filename){const original=doc.title;const restore=()=>{doc.title=original;frame.contentWindow.removeEventListener('afterprint',restore);root.removeEventListener('afterprint',restore);restorePrintTitle=null;};restorePrintTitle=restore;doc.title=filename;frame.contentWindow.addEventListener('afterprint',restore);root.addEventListener('afterprint',restore);}try{frame.contentWindow.focus();frame.contentWindow.print();}catch(error){restorePrintTitle?.();feedback.textContent='인쇄 창을 열지 못했습니다. PDF 파일 만들기를 이용해 주세요.';}});
 close.addEventListener('click',clear);dialog.addEventListener('cancel',clear);return dialog;
}
function node(title,target){return open(title,(body,doc)=>{const snapshot=visibleSnapshot(target,doc);if(snapshot)body.append(snapshot);});}
function journals(title,records){
 const date=title.match(/^(\d{4})-(\d{2})(?:-(\d{2}))?(?=\s|$)/);
 const filename=date?'청라근무일지'+date[1].slice(2)+date[2]+(date[3]||''):undefined;
 return open(title,(body,doc)=>{
  const table=doc.createElement('table');
  table.className='journal-print-table';
  const header=table.createTHead().insertRow();
  for(const label of ['일자 / 요일','근무 내용','특이 사항 · 구체적인 시간 기재','신규 상담 내용 / 전달사항']){
   const th=doc.createElement('th');
   th.textContent=label;
   header.append(th);
  }
  const tbody=table.createTBody();
  function writeInk(node,text,runs,color){
   if(root.CheonglaJournalInk)root.CheonglaJournalInk.render(node,text,runs,color);
   else node.textContent=text;
  }
  for(const record of records){
   const row=tbody.insertRow();
   const day=row.insertCell();
   day.style.width='10%';
   day.textContent=record.work_on+'\n'+new Date(record.work_on+'T00:00:00+09:00').toLocaleDateString('ko-KR',{weekday:'short',timeZone:'Asia/Seoul'});
   for(const key of ['duty','special','handover']){
    const cell=row.insertCell();
    cell.style.width='30%';
    const text=doc.createElement('div');
    writeInk(text,record[key]||'',record.field_inks?.[key],record.ink_color);
    cell.append(text);
    for(const comment of (record.comments||[]).filter(c=>(c.field_key||'handover')===key)){
     const note=doc.createElement('p');
     writeInk(note,comment.body,comment.ink_runs,comment.ink_color);
     cell.append(note);
    }
   }
   if(Object.hasOwn(record,'patrol')){
    const cell=tbody.insertRow().insertCell();
    cell.colSpan=4;
    const heading=doc.createElement('div'),label=doc.createElement('strong'),text=doc.createElement('div');
    label.textContent='순시상황';
    heading.append(label);
    writeInk(text,record.patrol||'',record.field_inks?.patrol,record.ink_color);
    cell.append(heading,text);
   }
  }
  body.append(table);
  const style=doc.createElement('style');
  style.textContent='.journal-print-table{table-layout:fixed;border:2px solid #222}.journal-print-table th{font-weight:600;text-align:center}.journal-print-table td{white-space:pre-wrap;vertical-align:top;line-height:1.8;min-height:200px}.journal-print-table tr{break-inside:auto}';
  doc.head.append(style);
 },filename);
}

function mbti(code,guide,groups){
 if(!/^[IE][NS][TF][JP]$/.test(code)||!guide||!groups)throw Error('출력할 MBTI 유형을 선택해 주세요.');
 return open((guide.title&&guide.title!==code?code+' · '+guide.title:code)+' · 청라 MBTI 학습법',(body,doc)=>{
  const text=(parent,tag,value)=>{const n=doc.createElement(tag);n.textContent=value;parent.append(n);return n;};
  if(guide.subtitle)text(body,'p',guide.subtitle);
  for(const [key,group]of Object.entries(groups)){
   const block=doc.createElement('section');text(block,'h2',group.title);
   const section=s=>{if(!s?.title||typeof s.body!=='string'||!s.body.trim())return;text(block,'h3',s.title);text(block,'p',s.body);};
   if(group.sections){for(const s of guide[group.sections]||[])section(s);}
   else{section(guide.groupIntroductions?.[key]);for(const [subject,label]of group.subjects||[]){text(block,'h3',label);text(block,'p',guide.subjects?.[subject]||'학습법 준비 중');}}
   body.append(block);
  }
 },'청라MBTI학습법_'+code);
}
root.CheonglaPrint={open,node,journals,mbti,clear,visibleSnapshot};
})(globalThis);
